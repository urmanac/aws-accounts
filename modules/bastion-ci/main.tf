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

# Launch template for bastion
resource "aws_launch_template" "bastion" {
  name_prefix   = "${var.name}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.bastion.arn
  }

  network_interfaces {
    subnet_id                   = element(var.public_subnet_ids, 0)
    associate_public_ip_address = false # <– important, disables IPv4
    ipv6_address_count          = 1     # <– asks for a single IPv6
    security_groups             = [var.bastion_security_group_id, var.ssm_security_group_id]
  }

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.name}-bastion"
    }
  }

  user_data = base64encode(<<-EOT
              #!/usr/bin/env bash
              set -euo pipefail

              # Create SSH authorized_keys for ec2-user
              mkdir -p /home/ec2-user/.ssh
              echo "${var.my_public_ssh_key}" > /home/ec2-user/.ssh/authorized_keys
              chown -R ec2-user:ec2-user /home/ec2-user/.ssh
              chmod 700 /home/ec2-user/.ssh
              chmod 600 /home/ec2-user/.ssh/authorized_keys

              dnf update -y
              dnf install -y git unzip jq
              cd /root
              # Download the installer script:
              curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh -o install-opentofu.sh
              # Alternatively: wget --secure-protocol=TLSv1_2 --https-only https://get.opentofu.org/install-opentofu.sh -O install-opentofu.sh
              # Give it execution permissions:
              chmod +x install-opentofu.sh
              # Please inspect the downloaded script
              # Run the installer:
              ./install-opentofu.sh --install-method rpm
              # Remove the installer:
              rm -f install-opentofu.sh

              cat >/etc/profile.d/assume-tf-ci.sh <<'EOP'
              export AWS_REGION=${var.region}
              export AWS_PAGER=""
              assume_tf_ci() {
                CREDS=$(aws sts assume-role --role-arn ${aws_iam_role.terraform_ci.arn} --role-session-name tfci-$$)
                export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .Credentials.AccessKeyId)
                export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r .Credentials.SecretAccessKey)
                export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r .Credentials.SessionToken)
                echo "Assumed ${aws_iam_role.terraform_ci.arn}"
              }
              EOP

              # SSM Agent is preinstalled on AL2/AL2023; ensure it's running
              systemctl enable amazon-ssm-agent
              systemctl start amazon-ssm-agent
              echo "Bootstrap complete" | logger

              EOT
  )
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

