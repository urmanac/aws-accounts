terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

variable "name" {
  type        = string
  description = "Name prefix for the VPC"
}

variable "cidr" {
  type        = string
  description = "CIDR block for the VPC"
}

variable "region" {
  type        = string
  description = "Region to create the VPC in"
}

variable "enable_bastion_networking" {
  type        = bool
  description = "Enable networking components required for bastion hosts (bastion security group)"
  default     = false
}

variable "enable_bastion_private_networking" {
  type        = bool
  description = "Enable SSM VPC endpoints (cost something) networking components required for private bastion hosts"
  default     = false
}

provider "aws" {
  alias  = "this"
  region = var.region
}

data "aws_availability_zones" "available" {
  state = "available"
}

# VPC with IPv6
resource "aws_vpc" "this" {
  cidr_block                     = var.cidr
  assign_generated_ipv6_cidr_block = true
  enable_dns_support             = true
  enable_dns_hostnames           = true
  tags = { Name = "${var.name}-vpc" }
}

# Internet Gateway for public subnets
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = { Name = "${var.name}-igw" }
}

# Public subnets (2 AZs for now)
resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.cidr, 8, count.index)
  ipv6_cidr_block         = cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = { Name = "${var.name}-public-${count.index}" }
}

# Private subnets (2 AZs for now)
resource "aws_subnet" "private" {
  count                   = 2
  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.cidr, 8, count.index + 10)
  ipv6_cidr_block         = cidrsubnet(aws_vpc.this.ipv6_cidr_block, 8, count.index + 10)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-private-${count.index}" }
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.this.id
  }

  tags = { Name = "${var.name}-public-rt" }
}

# Associate public subnets with public RT
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# S3 Gateway endpoint (needed for SSM agent to pull updates)
resource "aws_vpc_endpoint" "s3_gateway" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id]
}

# SG for interface endpoints
resource "aws_security_group" "endpoints" {
  name        = "${var.name}-endpoints"
  description = "Allow HTTPS to VPC endpoints"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.this.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
}

# Security group for bastion hosts (only created if bastion networking is enabled)
resource "aws_security_group" "bastion" {
  count       = var.enable_bastion_networking ? 1 : 0
  name        = "${var.name}-bastion-sg"
  description = "Security group for bastion hosts"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${var.name}-bastion-sg"
  }
}

# Interface endpoints for SSM (only created if bastion networking is enabled)
resource "aws_vpc_endpoint" "ssm" {
  count              = var.enable_bastion_private_networking ? 1 : 0
  vpc_id             = aws_vpc.this.id
  service_name       = "com.amazonaws.${var.region}.ssm"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ec2messages" {
  count              = var.enable_bastion_private_networking ? 1 : 0
  vpc_id             = aws_vpc.this.id
  service_name       = "com.amazonaws.${var.region}.ec2messages"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.endpoints.id]
  private_dns_enabled = true
}

resource "aws_vpc_endpoint" "ssmmessages" {
  count              = var.enable_bastion_private_networking ? 1 : 0
  vpc_id             = aws_vpc.this.id
  service_name       = "com.amazonaws.${var.region}.ssmmessages"
  vpc_endpoint_type  = "Interface"
  subnet_ids         = aws_subnet.private[*].id
  security_group_ids = [aws_security_group.endpoints.id]
  private_dns_enabled = true
}

# Outputs
output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "ssm_security_group_id" {
  description = "The ID of the SSM security group"
  value       = aws_security_group.endpoints.id
}

output "bastion_security_group_id" {
  description = "The ID of the bastion security group (only available if bastion networking is enabled)"
  value       = var.enable_bastion_networking ? aws_security_group.bastion[0].id : null
}
