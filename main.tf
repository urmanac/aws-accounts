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
