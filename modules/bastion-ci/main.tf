terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "${var.region}"
}

# IAM role + instance profile for SSM
resource "aws_iam_role" "bastion_role" {
  name               = "${var.name}-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
}

resource "aws_iam_role" "terraform_ci" {
  name               = "${var.name}-terraform-ci"
  assume_role_policy = data.aws_iam_policy_document.terraform_ci_assume.json
}

# Attach AdministratorAccess to terraform-ci role
resource "aws_iam_role_policy_attachment" "terraform_ci_admin" {
  role       = aws_iam_role.terraform_ci.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "terraform_ci_assume" {
  statement {
    sid = "AllowBastionAssume"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.bastion_role.arn]
    }
  }
}

# Attach AmazonSSMManagedInstanceCore
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.name}-instance-profile"
  role = aws_iam_role.bastion_role.name
}

# Security group is now managed by the VPC module

# Log group
resource "aws_cloudwatch_log_group" "bastion" {
  name              = "/bastion/logs"
  retention_in_days = 30
  tags = {
    Name = "${var.name}-bastion"
  }
}

# Policy attachment for CloudWatch agent
resource "aws_iam_role_policy_attachment" "bastion_cwagent" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Launch template for bastion
resource "aws_launch_template" "bastion" {
  name_prefix   = "${var.name}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.bastion.arn
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = 4
      volume_type = "gp3"
      encrypted   = true
      delete_on_termination = true
    }
  }

  metadata_options {
    http_endpoint               = "enabled"   # allows IMDS
    http_tokens                 = "required"  # enforce IMDSv2
    http_protocol_ipv6           = "enabled"  # allow IPv6
    http_put_response_hop_limit = 2           # standard
  }

  network_interfaces {
    subnet_id                   = element(var.public_subnet_ids, 0)
    associate_public_ip_address = false
    ipv6_address_count          = 1
    security_groups             = [var.bastion_security_group_id, var.ssm_security_group_id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name}-bastion"
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/userdata.tftpl", {
    my_public_ssh_key     = var.my_public_ssh_key
    my_wireguard_client_key = var.my_wireguard_client_key
    my_wireguard_server_pub = var.my_wireguard_server_pub
    my_wireguard_server_ipv6 = var.my_wireguard_server_ipv6
    region                = var.region
    terraform_ci_role_arn = aws_iam_role.terraform_ci.arn
  }))
}

# Auto Scaling group
resource "aws_autoscaling_group" "bastion" {
  name = "${var.name}-asg"

  lifecycle {
    ignore_changes = [name]
    create_before_destroy = true
  }

  desired_capacity    = 0
  max_size            = 1
  min_size            = 0
  vpc_zone_identifier  = var.public_subnet_ids


  launch_template {
    id      = aws_launch_template.bastion.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-bastion"
    propagate_at_launch = true
  }
}

# Scheduled actions: start at 7 AM, stop at 12 PM EST daily
resource "aws_autoscaling_schedule" "start" {
  scheduled_action_name  = "${var.name}-start"
  min_size               = 0
  max_size               = 1
  desired_capacity       = 1
  recurrence             = "0 12 * * *" # 7 AM US/Eastern == 12 UTC
  autoscaling_group_name = aws_autoscaling_group.bastion.name
}

resource "aws_autoscaling_schedule" "stop" {
  scheduled_action_name  = "${var.name}-stop"
  min_size               = 0
  max_size               = 1
  desired_capacity       = 0
  recurrence             = "0 17 * * *" # 12 PM US/Eastern == 17 UTC
  autoscaling_group_name = aws_autoscaling_group.bastion.name
}

# Find Amazon Linux 2 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-kernel-6.1-arm64"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

