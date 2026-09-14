terraform {
  required_providers {
    aws = {
      configuration_aliases = [aws.us_east_1]
      source                = "hashicorp/aws"
    }
  }
}
