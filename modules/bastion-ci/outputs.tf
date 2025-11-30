output "bastion_instance_id" {
  value = aws_instance.bastion.id
}

output "bastion_instance_role_arn" {
  description = "ARN of the bastion instance role"
  value       = aws_iam_role.bastion_role.arn
}

output "bastion_eni_id" {
  description = "ENI ID of the bastion host"
  value       = aws_network_interface.bastion_eni.id
}

output "bastion_private_ip" {
  description = "Private IP address of the bastion host"
  value       = aws_network_interface.bastion_eni.private_ip
}

# output "terraform_ci_role_arn" {
#   value = aws_iam_role.terraform_ci.arn
# }
