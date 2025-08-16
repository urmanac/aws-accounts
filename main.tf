provider "aws" {
  # profile = "${var.environment}-bootstrap" # expects you to set up ~/.aws/credentials
  # profile = "terraform-admin-${var.environment}-mfa" # now with MFA required
  region  = "us-east-1"                    # pick one
}

module "bootstrap_admin" {
  source      = "./modules/bootstrap-admin"
  environment = var.environment
  account_id  = var.account_map[var.environment]
}
