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

resource "aws_network_interface" "primary_enis" {
  count = 3
  subnet_id       = aws_subnet.my_subnet.id
  private_ips     = ["172.16.10.${250 + count.index}"]

  # Attach your security group directly to the interface
  security_groups = [aws_security_group.allow_ssh.id]
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
  security_groups = [aws_security_group.allow_ssh.id]
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

# Associate ONLY this new subnet to your Internet Gateway Route Table
resource "aws_route_table_association" "mgmt_assoc" {
  subnet_id      = aws_subnet.management_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_key_pair" "deployer" {
  key_name   = "deployer-key"
  public_key = file("~/.ssh/terraform_key.pub") # Reads your local public key file
}

# Create a Security Group for SSH
resource "aws_security_group" "allow_ssh" {
  name        = "allow_ssh"
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

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  owners = ["099720109477"] # Canonical
}

data "aws_ami" "debian-11" {
  most_recent = true

  filter {
    name   = "name"
    values = ["debian-11-amd64-*"]
  }

  owners = ["136693071363"] # Canonical
}

resource "aws_instance" "app_server" {
  count = 3
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"

  # Reference the key pair name from the resource above
  key_name      = aws_key_pair.deployer.key_name

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
  key_name      = aws_key_pair.deployer.key_name

  # Attach the security group here
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  associate_public_ip_address = true

  tags = {
    Name = "dev_ops_machine"
  }

  user_data = file("../scripts/install-ansible.yaml")

}



output app_server_ip{
  description = "Private IPs for the VMs"
  value = { 
    for server in aws_instance.app_server : server.tags["Name"] => server.public_dns
  }
}

output dev_ops_machine_dns_name{
  description  = "DNS name for dev_ops_machine"
  value = aws_instance.dev_ops_machine.public_dns
}
