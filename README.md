# aws-cloud

Central infrastructure repo for one shared AWS account, sized to the always-free tier and capped at
$5 a month. It provisions the things every app shares and one slice per app, so app repositories contain
no Terraform: they build their code and push it with a per-app deploy role this repo hands them.

```
aws-cloud/
├── terraform/
│   ├── main.tf                 providers, the S3 state backend, shared modules, the apps layer
│   ├── modules/
│   │   ├── github-oidc/        the account's GitHub OIDC provider and this repo's Terraform role
│   │   ├── alerts/             one SNS topic, its email subscription, the $5 monthly budget
│   │   ├── table/              the shared DynamoDB single table at the free 25 units, throttle alarms
│   │   ├── sites/              one S3 bucket for every frontend, the CloudFront router function, API cache policy
│   │   └── app/                per app: roles, Lambdas, function URLs, schedules, canary, CloudFront site, certificate, Cognito, alarms
│   ├── apps/
│   │   ├── donation.tf         the donation repo
│   │   ├── outputs.tf          one line per app
│   │   └── _template.tf.example
│   ├── outputs.tf
│   ├── variables.tf
│   └── terraform.tfvars.example
├── scripts/bootstrap.sh        run once from CloudShell: state bucket, OIDC provider, the Terraform role
└── .github/workflows/terraform.yml   plan on pull request, apply on main
```

## The cost rule

The account costs between $0 and $5 a month with every app running. Everything below is either in the
always-free tier or costs pennies, and the `aws-cloud-monthly` budget emails `alert_email` when 80% of
$5 has been spent, when $5 has been spent, and when the month's forecast passes $5. An alert means
something is removed, not that the budget is raised.

| Allowance | Free | Used by donation |
|---|---|---|
| DynamoDB provisioned units | 25 read, 25 write | all, on the shared table |
| CloudWatch alarms | 10 | 8, plus the 2 table throttle alarms |
| CloudWatch custom metrics | 10 | 8 |
| Lambda | 1M invocations, 400k GB-seconds | about 20k invocations idle |
| CloudFront | 1 TB out, 10M requests, 2M function invocations | little |
| CloudWatch Logs | 5 GB ingested | little |
| SNS | 1,000 emails | little |
| Cognito | 10,000 monthly active users | a handful of administrators |
| ACM, AWS Budgets, EventBridge schedules, IAM | free | |

The next app therefore starts with no alarm budget and two metrics unless donation gives some up. What
bills: the sites bucket and the state bucket, a few cents a month for storage, since S3's own free tier
is 12-month only. Secrets are function environment variables rather than Secrets Manager for the same
reason.

## What an app gets

Every `apps/<name>.tf` produces, from one module call:

- a runtime role that may read and write the shared table, optionally fenced to its own key prefix, and
  write its own log groups
- a deploy role that GitHub Actions in the app's repository can assume, allowed to update the app's
  function code, sync its folder of the sites bucket, and invalidate its distribution
- one Lambda per entry in `functions`, named `<app>-<key>`, on `provided.al2023` arm64 with the committed
  `placeholder.zip` as its body until the app deploys; optional public function URL, schedule, reserved
  concurrency, alarms
- a CloudFront distribution serving `s3://<bucket>/<app>/` with client-side routing, and `/api*` proxied
  to the function marked `url = "api"` with the prefix stripped and GETs cached for 30 seconds
- optionally a canary function that probes a path on the site every few minutes, a Cognito user pool for
  administrators, a certificate for a custom domain, plus alarms on the app's own metrics

The api function URL stays public rather than locked to CloudFront: Lambda origin access control requires
browsers to send a payload hash header on every POST, which is more ceremony than a demo app wants. A
public URL needs two resource policy statements for every principal: `lambda:InvokeFunctionUrl`
conditioned on the NONE auth type, and a plain `lambda:InvokeFunction`, which the API refuses to
condition. With only the first, which was enough before 2025, every request answers 403. The second
means any AWS principal may also invoke the function through the Lambda API, which is the same exposure
the public URL already has: the webhook checks Stripe's signature and the console functions check the
bearer token before reading anything.

Reserved concurrency needs the account's Lambda concurrency quota above the 100 units Lambda keeps
unreserved, and a new account starts at 10, where every reservation is refused. The module reads the
quota and reserves nothing until it is above 100, so the first apply succeeds; request 1,000 in Service
Quotas (`L-B99A9384`) and the next apply reserves what each app asked for.

## Bootstrap

Once. Sign in to the console, open CloudShell in `eu-west-2`, and run:

```bash
curl -sL https://raw.githubusercontent.com/poly-glot/aws-cloud/main/scripts/bootstrap.sh | bash
```

It creates the versioned state bucket, installs Terraform, and applies only the `github_oidc` module:
the OIDC provider and the `aws-cloud-terraform` role, trusting this repository's subject in
`infra_subject`. It prints the role ARN, the account id and the account's Lambda concurrency quota. It is
safe to run again, which is also how a change to that trust lands, since the workflow cannot fix the role
it can no longer assume. Everything else is applied by the workflow, which needs these in the
repository settings:

| Where    | Name                             | Value                                                            |
|----------|----------------------------------|------------------------------------------------------------------|
| secret   | `INFRA_ROLE_ARN`                 | what the bootstrap printed                                       |
| secret   | `ALERT_EMAIL`                    | who receives alarms and budget notices                           |
| secret   | `DONATION_ADMIN_EMAILS`          | JSON list, `["you@example.org"]`; each gets a Cognito invitation |
| secret   | `DONATION_STRIPE_SECRET_KEY`     | Stripe secret key                                                |
| secret   | `DONATION_STRIPE_WEBHOOK_SECRET` | signing secret of the Stripe webhook endpoint, once it exists    |
| variable | `DONATION_CONSOLE_URL`           | `<site_url>/admin.html`, see Administrator sign-in               |
| variable | `DONATION_DOMAIN_LIVE`           | `true` once the certificate is issued, see Custom domains        |

```bash
gh secret set INFRA_ROLE_ARN -R poly-glot/aws-cloud --body "arn:aws:iam::123456789012:role/aws-cloud-terraform"
gh secret set ALERT_EMAIL -R poly-glot/aws-cloud
gh secret set DONATION_STRIPE_SECRET_KEY -R poly-glot/aws-cloud
```

The apply job runs in the `production` environment; add a required reviewer there once the platform
is stable. The `Outputs` step of every apply writes every output to the run summary, which is where
the values for an app repository come from.

## Onboarding an app

1. Copy `terraform/apps/_template.tf.example` to `terraform/apps/<app>.tf` and fill in the functions
   and the repository's OIDC subject. GitHub issues immutable subjects, `repo:<owner>@<id>/<repo>@<id>`,
   so a deleted and recreated repository of the same name cannot inherit the role; read it with
   `gh api repos/poly-glot/<app>/actions/oidc/customization/sub --jq .sub_claim_prefix`.
2. Add `<app> = module.<app>.wiring` to `terraform/apps/outputs.tf`.
3. Open a pull request, read the plan, merge. CI applies.
4. Give the app repository what it needs, from the `outputs` artifact of the apply:

```bash
APP=myapp
gh run download -R poly-glot/aws-cloud -n outputs
gh secret set AWS_DEPLOY_ROLE_ARN -R poly-glot/$APP --body "$(jq -r .apps.value.$APP.deploy_role_arn outputs.json)"
gh variable set SITES_BUCKET      -R poly-glot/$APP --body "$(jq -r .apps.value.$APP.sites_bucket outputs.json)"
gh variable set DISTRIBUTION_ID   -R poly-glot/$APP --body "$(jq -r .apps.value.$APP.distribution_id outputs.json)"
```

5. In the app repository, deploy with the role. A Rust Lambda app looks like this:

```yaml
permissions:
  contents: read
  id-token: write

steps:
  - uses: actions/checkout@v4
  - uses: aws-actions/configure-aws-credentials@v4
    with:
      aws-region: eu-west-2
      role-to-assume: ${{ secrets.AWS_DEPLOY_ROLE_ARN }}
  - run: cargo build --release
  - run: |
      for f in api stripe-webhook subscription-charge reconcile canary draw-run admin; do
        cp "target/release/$f" bootstrap && zip -q "$f.zip" bootstrap
        aws lambda update-function-code --function-name "donation-$f" --zip-file "fileb://$f.zip"
      done
  - run: aws s3 sync dist/ "s3://${{ vars.SITES_BUCKET }}/donation/" --delete
  - run: aws cloudfront create-invalidation --distribution-id "${{ vars.DISTRIBUTION_ID }}" --paths '/*'
```

Function names are `<app>-<key>` for every key in `functions`, plus `<app>-canary` when a canary is set.
The functions run on Amazon Linux 2023, so build on it: a job on an `ubuntu-24.04-arm` runner inside the
`amazonlinux:2023` container links against the same glibc the runtime has.

## Sharing the table

Every app reads the same table through `TABLE_NAME`. Keep apps apart by prefixing every partition key
value with the app name, `myapp#RAFFLE#winter-2026`, and set `key_prefix = "myapp#"` on the module so the
runtime role cannot reach anything else. Sort keys and the two overloaded indexes are shared as they are.
The donation app does this through one `partition` helper in its shared crate and sets `key_prefix = "donation#"`,
so its keys read `donation#RAFFLE#winter-2026`.

## Custom domains

An app with `domain = { name = "app.example.org" }` gets an ACM certificate for the name in `us-east-1`,
where CloudFront reads certificates from, and its `domain_validation` output is the CNAME that proves
ownership. DNS stays at the registrar; a Route 53 hosted zone would be the one line item this repo does
not otherwise have. Two records at the registrar, both DNS-only rather than proxied:

1. the validation record, `domain_validation.name` → `domain_validation.value`
2. the site, `app.example.org` → `distribution_domain`

ACM issues the certificate within minutes of seeing the first record. Then set `live = true` on the
domain — for donation, the `DONATION_DOMAIN_LIVE` repository variable — and re-run the workflow: the
distribution takes the name and the certificate, `site_url` and the canary move onto it, and the apply
waits for the certificate rather than failing if the record is missing. Until then the site answers on
its `cloudfront.net` name and the certificate simply waits.

## The donation app

`apps/donation.tf` is the donation repository, the charity raffle: seven functions, the webhook on a
public URL, `api` behind `/api*`, `admin` and `draw-run` behind `/api/admin*` and `/api/draw*` for
signed-in administrators, a canary on `/api/raffles/current` every five minutes, `donation.junaid.guru` as its domain, and
its ten alarms. Its Stripe webhook endpoint is the `stripe-webhook` function URL in the `apps` output,
subscribed to `charge.succeeded`, `charge.refunded` and `payment_intent.payment_failed`.

## Administrator sign-in

An app that sets `admins` gets a Cognito user pool, an app client for the browser's authorization-code
flow with PKCE, and a hosted-UI domain at `<app>-admins.auth.<region>.amazoncognito.com`. A user pool on
the Lite or Essentials tier is free to 10,000 monthly active users and that allowance is permanent, so a
handful of staff costs nothing; keep the pool off the Plus tier, off SMS and email MFA, and away from a
custom domain, each of which bills. TOTP MFA is enabled and free. Each address in `emails` gets a user
and an invitation email with a temporary password that lasts three days; resend one with
`aws cognito-idp admin-create-user --message-action RESEND`.

`console_url` is where Cognito sends the browser back. It cannot be derived from the app's own CloudFront
distribution, because the distribution depends on the function URLs, which depend on the functions, which
carry the client id in their environment — a cycle. So the first apply runs with the local default, the
`site_url` output names the distribution, and `DONATION_CONSOLE_URL` is set to that plus `/admin.html`
for the second apply. When the custom domain goes live, the console URL moves with it.

A function with `console = true` receives `COGNITO_CLIENT_ID` and `COGNITO_ISSUER` in its environment.
A function's `url` may be a site path rather than only `api`: `api/admin` puts it behind
`/api/admin*`, ordered ahead of `/api*` so the more specific path wins, and the pattern has no slash
before its star because the console posts to `/api/admin` itself. The router function still strips the
leading `/api`, so the function sees `/admin`.
