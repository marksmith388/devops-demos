provider "aws" {
  region = "eu-west-1"
}

resource "aws_vpc" "my_vpc" {
  cidr_block = "172.16.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "Linux Demo VPC"
  }
}

resource "aws_subnet" "my_subnet" {
  vpc_id            = aws_vpc.my_vpc.id
  availability_zone = "eu-west-1a"
  cidr_block        = "172.16.10.0/24"

  map_public_ip_on_launch = true

  tags = {
    Name = "Linux Demo Subnet"
  }
}

resource "aws_subnet" "my_subnet_b" {
  vpc_id            = aws_vpc.my_vpc.id
  availability_zone = "eu-west-1b"
  cidr_block        = "172.16.30.0/24"

  map_public_ip_on_launch = true

  tags = {
    Name = "Linux Demo Subnet"
  }
}

resource "aws_network_interface" "primary_enis" {
  count = 3
  subnet_id       = aws_subnet.my_subnet.id
  private_ips     = ["172.16.10.${250 + count.index}"]

  # Attach your security group directly to the interface
  security_groups = [aws_security_group.allow_http_app_server_frontend.id]
}

resource "aws_eip" "app_eip" {
  count             = 3
  network_interface = aws_network_interface.primary_enis[count.index].id
  domain            = "vpc"
}

resource "aws_subnet" "my_subnet2" {
  vpc_id            = aws_vpc.my_vpc.id
  availability_zone = "eu-west-1a"
  cidr_block        = "172.16.11.0/24"

  map_public_ip_on_launch = true

  tags = {
    Name = "Linux Demo Subnet 2"
  }
}

resource "aws_network_interface" "secondary_enis" {
  count = 3
  subnet_id       = aws_subnet.my_subnet2.id
  private_ips     = ["172.16.11.${250 + count.index}"]

  # Attach your security group directly to the interface
  security_groups = [aws_security_group.allow_ssh_app_server_backend.id]
}

resource "aws_subnet" "management_subnet" {
  vpc_id                  = aws_vpc.my_vpc.id
  availability_zone       = "eu-west-1a"
  cidr_block              = "172.16.20.0/24" # A fresh, unconflicted subnet range
  map_public_ip_on_launch = true

  tags = {
    Name = "Management Public Subnet"
  }
}

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.my_vpc.id
}

# Create a Route Table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.my_vpc.id

  # This route sends all out-of-VPC traffic (0.0.0.0/0) to the Internet Gateway
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "public-route-table"
  }
}

# Associate the Route Table with the Subnet
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.my_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Associate the Route Table with the Subnet
resource "aws_route_table_association" "public_assoc_b" {
  subnet_id      = aws_subnet.my_subnet_b.id
  route_table_id = aws_route_table.public_rt.id
}

# Associate ONLY this new subnet to your Internet Gateway Route Table
resource "aws_route_table_association" "mgmt_assoc" {
  subnet_id      = aws_subnet.management_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_lb" "application_lb" {
  name               = "application-lb-tf"
  internal           = false
  load_balancer_type = "application"

  # Attach the frontend security group you already created
  security_groups    = [aws_security_group.allow_http_app_server_frontend.id]

  subnets = [
    aws_subnet.my_subnet.id,
    aws_subnet.my_subnet_b.id
  ]

  tags = {
    Environment = "production"
  }
}

resource "aws_lb_target_group" "app_tg" {
  name        = "app-servers-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.my_vpc.id
  target_type = "instance" # Tells the ALB to route directly to the instances

  health_check {
    path                = "/"
    protocol            = "HTTP"
    port                = "80"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Create an HTTP Listener (Listens to the public internet on Port 80)
resource "aws_lb_listener" "http_listener" {
  load_balancer_arn = aws_lb.application_lb.arn
  port              = "80"
  protocol          = "HTTP"

  # Tells the listener to forward all public traffic into your target group
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_key_pair" "dev_deployer" {
  key_name   = "deployer-key"
  public_key = file("~/.ssh/terraform_key.pub") # Reads your local public key file
}

resource "aws_key_pair" "app_deployer" {
  key_name   = "deployer-key"
  public_key = file("~/.ssh/terraform_secondary_key.pub") # Reads your local public key file
}

# Store the private key in AWS Secrets Manager immediately
resource "aws_secretsmanager_secret" "ssh_private_key" {
  name        = "prod/ssh/private-key"
  description = "SSH private key for PROD EC2 instances"

  # Prevent accidental deletion
  recovery_window_in_days = 30
}

resource "aws_secretsmanager_secret_version" "ssh_private_key" {
  secret_id     = aws_secretsmanager_secret.ssh_private_key.id
  secret_string = file("~/.ssh/terraform_secondary_key")
}

# Create a Security Group for SSH
resource "aws_security_group" "allow_ssh_dev_machine" {
  name        = "allow_ssh_dev_machine"
  description = "Allow SSH inbound traffic"

  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description = "SSH from anywhere" # For production, replace "0.0.0.0/0" with your actual IP (e.g., "1.2.3.4/32")
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a Security Group for HTTP
resource "aws_security_group" "allow_http_app_server_frontend" {
  name        = "allow_http_app_server_frontend"
  description = "Allow HTTP inbound traffic"

  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description = "HTTP from anywhere" # For production, replace "0.0.0.0/0" with your actual IP (e.g., "1.2.3.4/32")
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Create a Security Group for SSH
resource "aws_security_group" "allow_ssh_app_server_backend" {
  name        = "allow_ssh_app_server_backend"
  description = "Allow SSH inbound traffic"

  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description = "SSH from anywhere" # For production, replace "0.0.0.0/0" with your actual IP (e.g., "1.2.3.4/32")
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["172.16.20.0/24"] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_instance" "app_server" {
  count = 3
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"

  # Reference the key pair name from the resource above
  key_name      = aws_key_pair.app_deployer.key_name

  # Primary Interface (Subnet 1 - Auto-allocated by AWS)
  network_interface {
    network_interface_id = aws_network_interface.primary_enis[count.index].id
    device_index         = 0
  }

  # Secondary Interface (Subnet 2 - Your Static Management IPs)
  network_interface {
    network_interface_id = aws_network_interface.secondary_enis[count.index].id
    device_index         = 1
  }

  tags = {
    Name = "prod-vm-${count.index + 1}"
  }

  user_data = file("../scripts/add-ssh-key.yaml")
}

resource "aws_instance" "dev_ops_machine" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  subnet_id = aws_subnet.management_subnet.id

  # Reference the key pair name from the resource above
  key_name      = aws_key_pair.dev_deployer.key_name

  # Attach the security group here
  vpc_security_group_ids = [aws_security_group.allow_ssh_dev_machine.id]

  associate_public_ip_address = true

  tags = {
    Name = "dev_ops_machine"
  }

  user_data = file("../scripts/install-ansible.yaml")

}

# Create the instance profile wrapper
#resource "aws_iam_instance_profile" "devops_profile" {
#  name = "devops-instance-profile"
#  role = aws_iam_role.devops_role.name
#}

resource "aws_lb_target_group_attachment" "tg_attachment" {
  count            = 3
  target_group_arn = aws_lb_target_group.app_tg.arn
  target_id        = aws_instance.app_server[count.index].id
  port             = 80
}

output app_server_dns{
  description = "Public DNS for the VMs"
  value = { 
    for server in aws_instance.app_server : server.tags["Name"] => server.public_dns
  }
}

#output "load_balancer_dns_name" {
#  description = "The public entry point for your entire application infrastructure"
#  value       = aws_lb.application_lb.dns_name
#}

output dev_ops_machine_dns_name{
  description  = "DNS name for dev_ops_machine"
  value = aws_instance.dev_ops_machine.public_dns
}
