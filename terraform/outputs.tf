output "apps" {
  description = "Per-app values to copy into each app repository's GitHub secrets and variables"
  value       = module.apps.apps
}

output "infra_role_arn" {
  description = "Set as INFRA_ROLE_ARN on this repository"
  value       = module.github_oidc.infra_role_arn
}

output "sites_bucket" {
  value = module.sites.wiring.bucket
}

output "table_name" {
  value = module.table.wiring.name
}
