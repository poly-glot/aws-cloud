variable "infra_subject" {
  description = "The OIDC subject prefix GitHub reports for this repository, repo:<owner>@<id>/<repo>@<id>"
  type        = string
}

variable "prefix" {
  type = string
}
