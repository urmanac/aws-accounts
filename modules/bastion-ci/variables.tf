variable "name" {
  description = "Name prefix for bastion resources"
  type        = string
  default     = "bastion"
}

variable "region" {
  description = "The region where the bastion will be deployed"
  type        = string
  default     = "eu-west-1"
}

variable "vpc_id" {
  description = "The VPC ID where the bastion will be deployed"
  type        = string
}

variable "bastion_security_group_id" {
  description = "Security group ID for bastion instances (from VPC module)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the bastion"
  type        = string
}

variable "public_subnet_ids" {
  description = "List of private subnet IDs where the bastion may launch"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs where the bastion may launch"
  type        = list(string)
}

variable "ssm_security_group_id" {
  description = "Security group ID to attach to the bastion instance"
  type        = string
}

variable "my_public_ssh_key" {
  description = "Public SSH key of the user who should get ec2-user access"
  type        = string
}

variable "my_wireguard_client_key" {
  description = "Private key for the wireguard client"
  type        = string
}

variable "my_wireguard_client_pub" {
  description = "Public key for the client's wireguard key"
  type        = string
}

variable "my_wireguard_server_pub" {
  description = "Public key for the wireguard server"
  type        = string
}

variable "my_wireguard_server_ipv6" {
  description = "Public IPv6 address for the wireguard server"
  type        = string
}
