provider "aws" {
  # profile = "${var.environment}-bootstrap" # expects you to set up ~/.aws/credentials
  # profile = "terraform-admin-${var.environment}-mfa" # now with MFA required
  #profile= To use Session Token AWS authentication, run ./get_mfa_session.sh
  region = "us-east-1" # pick one
}

# Alias for eu-west-1
provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}

module "bootstrap_admin" {
  source      = "./modules/bootstrap-admin"
  environment = var.environment
  account_id  = var.account_map[var.environment]
  
  # Connect break-glass users to assumable roles
  break_glass_assume_roles_policy_arn = module.assumable_roles.break_glass_policy_arn
}

# OIDC Identity Providers
module "oidc_identity" {
  source      = "./modules/oidc-identity"
  environment = var.environment
  
  # Enable GitHub OIDC (primary)
  enable_github_oidc   = true
  github_organizations = ["urmanac", "kingdon-ci"]
  
  # Future: Enable GitLab and Custom OIDC
  enable_gitlab_oidc = false
  enable_custom_oidc = false
}

# Assumable Roles for RBAC
module "assumable_roles" {
  source = "./modules/assumable-roles"
  
  environment       = var.environment
  role_prefix      = "${var.environment}-"
  oidc_trust_policy = module.oidc_identity.multi_provider_trust_policy
  
  # Regional restrictions for CI role
  allowed_regions = ["us-east-1", "eu-west-1"]
}


locals {
  env = { for kv in regexall("(\\w+)=(.*)", file(".env")) : kv[0] => kv[1] }
}

module "bastion_ci" {
  source      = "./modules/bastion-ci"
  # providers   = { aws = aws.eu_west_1 }
  
  name                      = "tf"
  region                    = "eu-west-1"
  vpc_id                    = module.vpc_eu_west_1.vpc_id
  public_subnet_ids         = module.vpc_eu_west_1.public_subnet_ids
  private_subnet_ids        = module.vpc_eu_west_1.private_subnet_ids
  ssm_security_group_id     = module.vpc_eu_west_1.ssm_security_group_id
  bastion_security_group_id = module.vpc_eu_west_1.bastion_security_group_id
  instance_type             = "t4g.small"
  # assign from .env
  my_public_ssh_key         = local.env["MY_PUBLIC_SSH_KEY"]
  my_wireguard_client_key   = local.env["MY_WIREGUARD_CLIENT_KEY"]
  my_wireguard_client_pub   = local.env["MY_WIREGUARD_CLIENT_PUB"]
  my_wireguard_server_pub   = local.env["MY_WIREGUARD_SERVER_PUB"]
  my_wireguard_server_ipv6  = local.env["MY_WIREGUARD_SERVER_IPV6"]
}

module "vpc_eu_west_1" {
  source = "./modules/vpc"
  name   = "sandbox-eu"
  providers = { aws = aws.eu_west_1 }
  cidr   = "10.10.0.0/16"
  region = "eu-west-1"
  enable_bastion_networking = true
  enable_bastion_private_networking = false
}

module "vpc_us_east_1" {
  source = "./modules/vpc"
  name   = "sandbox-us"
  cidr   = "10.20.0.0/16"
  region = "us-east-1"
}
