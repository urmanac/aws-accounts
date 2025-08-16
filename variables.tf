variable "environment" {
  description = "Environment (sb, prod)"
  type        = string
}

variable "account_map" {
  description = "Map of environment -> AWS account ID"
  type        = map(string)
  default = {
    sb   = "**REMOVED**" # <-- replace me
    prod = "**REMOVED**" # <-- replace me
  }
}
