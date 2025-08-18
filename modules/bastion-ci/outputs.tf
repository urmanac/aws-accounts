output "asg_name" {
  value = aws_autoscaling_group.bastion.name
}

output "bastion_instance_role_arn" {
  description = "ARN of the bastion instance role"
  value       = aws_iam_role.bastion_role.arn
}

# output "terraform_ci_role_arn" {
#   value = aws_iam_role.terraform_ci.arn
# }
