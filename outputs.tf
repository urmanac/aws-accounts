output "admin_username" {
  value = module.bootstrap_admin.admin_username
}

output "admin_policy_arn" {
  value = module.bootstrap_admin.admin_policy_arn
}

output "asg_name" { value = module.bastion_ci.asg_name }
# output "bastion_role_arn" { value = module.bastion_ci.bastion_instance_role_arn }
# output "terraform_ci_role_arn" { value = module.bastion_ci.terraform_ci_role_arn }
