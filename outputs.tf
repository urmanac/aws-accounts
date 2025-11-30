output "admin_username" {
  value = module.bootstrap_admin.admin_username
}

output "admin_policy_arn" {
  value = module.bootstrap_admin.admin_policy_arn
}

output "asg_name" { value = module.bastion_ci.asg_name }
# output "bastion_role_arn" { value = module.bastion_ci.bastion_instance_role_arn }
# output "terraform_ci_role_arn" { value = module.bastion_ci.terraform_ci_role_arn }

# VPC and Subnet IDs for cozystack deployment
output "vpc_eu_west_1_id" {
  value       = module.vpc_eu_west_1.vpc_id
  description = "EU West 1 VPC ID for cozystack deployment"
}

output "private_subnet_ids_eu_west_1" {
  value       = module.vpc_eu_west_1.private_subnet_ids
  description = "EU West 1 private subnet IDs for Talos nodes"
}

output "public_subnet_ids_eu_west_1" {
  value       = module.vpc_eu_west_1.public_subnet_ids  
  description = "EU West 1 public subnet IDs for load balancers"
}

output "talos_security_group_id" {
  value       = module.vpc_eu_west_1.talos_cluster_security_group_id
  description = "Security group ID for Talos cluster communication"
}

output "registry_cache_endpoint" {
  value       = "${module.bastion_ci.bastion_private_ip}:5000"  # Bastion private IP with registry cache
  description = "Internal registry cache endpoint for GHCR pull-through"
}
