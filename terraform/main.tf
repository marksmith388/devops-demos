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

resource "aws_internet_gateway" "gw" {
  vpc_id = aws_vpc.my_vpc.id
}

resource "aws_subnet" "my_subnet" {
  vpc_id            = aws_vpc.my_vpc.id
  availability_zone = "eu-west-1a"
  cidr_block        = "172.16.10.0/24"

  tags = {
    Name = "Linux Demo Subnet"
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

  tags = {
    Name = "prod-vm-1"
  }
}

resource "aws_instance" "app_server-2" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.my_subnet.id

  tags = {
    Name = "prod-vm-2"
  }
}

resource "aws_instance" "app_server-3" {
  ami           = data.aws_ami.debian-11.id
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.my_subnet.id

  tags = {
    Name = "prod-vm-3"
  }
}

resource "aws_instance" "dev-machine" {
  ami           = data.aws_ami.debian-11.id
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.my_subnet.id

  tags = {
    Name = "dev-machine"
  }
}

#Creating elastic IP

resource "aws_eip" "lb" {
  domain = "vpc"

  tags = {
    Name = "fluffy-eip"
  }
}

#Attaching Elatic IP to Instance 

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.dev-machine.id
  allocation_id = aws_eip.lb.id
}