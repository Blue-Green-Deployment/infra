# Root glue file. Optionally configure a remote state backend.
#
# terraform {
#   backend "s3" {
#     bucket = "your-tfstate-bucket"
#     key    = "ecs-bluegreen/terraform.tfstate"
#     region = "us-east-1"
#     encrypt = true
#   }
# }
#
# Helper data sources (useful for debugging and tagging)

#data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Example: expose current account/region as outputs for quick checks
output "account_id" { value = data.aws_caller_identity.current.account_id }
output "aws_region_name" { value = data.aws_region.current.id }
