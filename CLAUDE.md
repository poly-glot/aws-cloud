# aws-cloud

Shared AWS platform for demo apps, held inside the always-free tier. One module call per app in
`terraform/apps/<app>.tf`, one line per app in `terraform/apps/outputs.tf`, nothing app-specific anywhere
else. App repositories carry no Terraform; they deploy code with the role this repo outputs.

## Rules

- The account costs between $0 and $5 a month, every app included. That is a hard ceiling, not a
  target: the `aws-cloud-monthly` budget emails at $4 spent, $5 spent and a $5 forecast, and the cure
  for any of those is removing what bills, not raising the budget. Sharing one account, one table, one
  bucket and one alerts topic between apps is what keeps the number there.
- Do not add anything that bills without asking: API Gateway, Route 53, autoscaling, PITR, Lambda@Edge,
  WAF, KMS-managed keys, Secrets Manager, extra alarms or metric series. The budgets in `README.md` are
  per account and every app draws on the same ten alarms, ten custom metrics and 25 table units.
- Attributes alphabetical inside every block; `count`, `for_each`, `provider` and `providers` first,
  then a blank line, then attributes, then nested blocks. No comments in `.tf` files; explain in
  `README.md`.
- Shared things live in `modules/`; an app never creates its own bucket, table, topic or OIDC provider.
  Extend `modules/app` when an app needs a new kind of resource, and keep the new input optional so
  existing apps are untouched.
- App secrets enter as `TF_VAR_<app>_<name>` from repository secrets in the workflow, thread through
  `variables.tf` and `apps/variables.tf`, and land in the app's `secrets` map, which becomes function
  environment. Never write a secret into a `.tf` file, a `.tfvars` file that is committed, or a log.
- State lives in the `poly-glot-aws-cloud-state` bucket with S3's own lockfile, applied only by the
  workflow. Nobody runs `terraform apply` from a laptop after `scripts/bootstrap.sh`; a change is a
  push to `main`.
- `terraform fmt -recursive -check` and `terraform validate` before every change lands; both run without
  credentials after `terraform init -backend=false`.
