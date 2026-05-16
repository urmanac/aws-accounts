# =============================================================================
# Sunkworks SCPs - Variables
# =============================================================================

variable "organization_root_id" {
  description = "Root ID of the AWS Organization"
  type        = string
}

variable "episodes_ou_id" {
  description = "Organizational Unit ID for episode accounts"
  type        = string
}

variable "approved_regions" {
  description = "List of approved AWS regions for resource creation"
  type        = list(string)
  default     = ["us-east-1", "eu-west-1"]
}

variable "allowed_instance_types" {
  description = "Allowed EC2 instance types (supports wildcards)"
  type        = list(string)
  default = [
    "t3.micro",
    "t3.small",
    "t3.medium",
    "t3a.micro",
    "t3a.small",
    "t3a.medium",
    "t4g.micro",
    "t4g.small",
    "t4g.medium"
  ]
}

variable "allowed_rds_classes" {
  description = "Allowed RDS instance classes"
  type        = list(string)
  default = [
    "db.t3.micro",
    "db.t3.small",
    "db.t4g.micro",
    "db.t4g.small"
  ]
}

variable "max_ebs_size_gb" {
  description = "Maximum EBS volume size in GB"
  type        = number
  default     = 100
}
