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

resource "aws_instance" "app_server-1" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.my_subnet.id

  # Reference the key pair name from the resource above
  key_name      = aws_key_pair.deployer.key_name

  # Attach the security group here
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  tags = {
    Name = "prod-vm-1"
  }
}

resource "aws_instance" "app_server-2" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.my_subnet.id

  # Reference the key pair name from the resource above
  key_name      = aws_key_pair.deployer.key_name

  # Attach the security group here
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  tags = {
    Name = "prod-vm-2"
  }
}

resource "aws_instance" "app_server-3" {
  ami           = data.aws_ami.debian-11.id
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.my_subnet.id

  # Reference the key pair name from the resource above
  key_name      = aws_key_pair.deployer.key_name

  # Attach the security group here
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  tags = {
    Name = "prod-vm-3"
  }
}

resource "aws_instance" "dev-machine" {
  ami           = data.aws_ami.debian-11.id
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.my_subnet.id

  # Reference the key pair name from the resource above
  key_name      = aws_key_pair.deployer.key_name

  # Attach the security group here
  vpc_security_group_ids = [aws_security_group.allow_ssh.id]

  tags = {
    Name = "dev-machine"
  }
}