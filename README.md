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
│   │   ├── analytics/          the logs and Athena results buckets, the Athena workgroup, the Glue database and CloudFront log table
│   │   └── app/                per app: roles, Lambdas, function URLs, schedules, canary, CloudFront site, certificate, Cognito, alarms
│   ├── apps/
│   │   ├── donation.tf         the donation repo
│   │   ├── shorten.tf          the shorten repo
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

| Allowance | Free | Used by donation | Used by shorten |
|---|---|---|---|
| DynamoDB provisioned units | 25 read, 25 write | all, on the shared table | the same units, shared |
| CloudWatch alarms | 10 | 8, plus the 2 table throttle alarms | 3, all of them billed |
| CloudWatch custom metrics | 10 | 8 | none |
| Lambda | 1M invocations, 400k GB-seconds | about 20k invocations idle | about 50k invocations |
| CloudFront | 1 TB out, 10M requests, 2M function invocations | little | about 50k requests and as many function invocations |
| CloudWatch Logs | 5 GB ingested | little | little |
| SNS | 1,000 emails | little | none |
| Cognito | 10,000 monthly active users | a handful of administrators | none |
| ACM, AWS Budgets, EventBridge schedules, IAM, Glue catalog | free | | |

The ten free alarms are gone, so shorten's three bill about $0.10 a month each. What else bills, per
month: the sites bucket and the state bucket, a few cents for storage, since S3's own free tier is
12-month only; the logs bucket, about 50 MB behind a 90-day lifecycle, under a cent; the Athena results
bucket, emptied by a 7-day lifecycle, under a cent; thirty nightly Athena queries, almost all of them
charged at the 10 MB minimum, about a cent. Call the whole analytics stack $0.02 and shorten $0.35.
Secrets are function environment variables rather than Secrets Manager for the same reason.

## What an app gets

Every `apps/<name>.tf` produces, from one module call:

- a runtime role that may read and write the shared table, optionally fenced to its own key prefix, and
  write its own log groups
- a deploy role that GitHub Actions in the app's repository can assume, allowed to update the app's
  function code, sync its folder of the sites bucket, invalidate its distribution, and, when the app
  brings its own viewer-request CloudFront function, update and publish that function too
- one Lambda per entry in `functions`, named `<app>-<key>`, on `provided.al2023` arm64 with the committed
  `placeholder.zip` as its body until the app deploys; optional public function URL, schedule, reserved
  concurrency, alarms
- a CloudFront distribution serving `s3://<bucket>/<app>/` with client-side routing, and `/api*` proxied
  to the function marked `url = "api"` with the prefix stripped and GETs cached for 30 seconds; an app
  that sets `default_origin_function` puts a function on the default behaviour instead of the bucket,
  and may replace the default behaviour's cache policy, origin request policy and viewer-request
  function, override the `/api*` cache policy, and have CloudFront add a fixed verification header to
  every function origin
- optionally, with `analytics` set, CloudFront standard logging v2 into the shared logs bucket and
  Athena, Glue and S3 access for its functions
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
| secret   | `SHORTEN_ORIGIN_VERIFY`          | long random string CloudFront sends the shorten functions as `X-Origin-Verify` |
| variable | `DONATION_CONSOLE_URL`           | `<site_url>/admin.html`, see Administrator sign-in               |
| variable | `DONATION_DOMAIN_LIVE`           | `true` once the certificate is issued, see Custom domains        |
| variable | `SHORTEN_DOMAIN_LIVE`            | `true` once the certificate is issued, see Custom domains        |
| variable | `SHORTEN_PUBLIC_BASE_URL`        | `https://<distribution_domain>`, set after the first apply, see The shorten app |

```bash
gh secret set INFRA_ROLE_ARN -R poly-glot/aws-cloud --body "arn:aws:iam::123456789012:role/aws-cloud-terraform"
gh secret set ALERT_EMAIL -R poly-glot/aws-cloud
gh secret set DONATION_STRIPE_SECRET_KEY -R poly-glot/aws-cloud
gh secret set SHORTEN_ORIGIN_VERIFY -R poly-glot/aws-cloud --body "$(openssl rand -base64 32)"
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
so its keys read `donation#RAFFLE#winter-2026`. The shorten app sets `key_prefix = "shorten#"`.

The table has TTL enabled on the attribute `ttl`. It is free, and it changes nothing for an app that
does not write that attribute: DynamoDB only expires an item that carries one. shorten writes it on
every item it creates, five years out for a link, ninety days for a day of stats, two days for a rate
limit counter.

The runtime policy every app receives grants `dynamodb:BatchGetItem` and `dynamodb:BatchWriteItem`
alongside the single-item actions. They were added for shorten, whose stats endpoint reads up to a
hundred days in one `BatchGetItem` and whose nightly rollup writes in batches, and **every app's
runtime role is now wider by those two actions**. The `dynamodb:LeadingKeys` fence still applies to
both, so an app with a `key_prefix` still cannot read or write outside its own prefix; an app without
one could already reach the whole table with `GetItem` in a loop, so the widening grants no reach that
was not already there, only fewer requests.

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

## The shorten app

`apps/shorten.tf` is the shorten repository, the rule-based link shortener. It is the first app with no
frontend in the sites bucket: **the default cache behaviour's origin is a Lambda, not S3**. Three
functions, all Rust on `provided.al2023` arm64:

| Function | Name | Where |
|---|---|---|
| redirect | `shorten-redirect` | the default behaviour's origin; answers `GET /{code}` with a 302 and `GET /` with an embedded page |
| mgmt | `shorten-mgmt` | behind `/api*`, caching disabled |
| rollup | `shorten-rollup` | no url; EventBridge `cron(15 2 * * ? *)`, 900-second timeout |

Because the default origin is a function, `default_root_object` is left unset. `index.html` would
rewrite `GET /` at the edge before the redirect function ever saw it, and the page it would look for
does not exist: the function carries the page in its own binary.

### The two viewer-request functions

The default behaviour runs `shorten-segment`, the app's own CloudFront function. The `/api*` behaviour
keeps the shared `aws-cloud-router`, whose first branch strips the leading `/api`, so `shorten-mgmt`
sees `/links`, `/links/{code}` and `/links/{code}/stats?from=…&to=…` exactly as `donation-api` sees
`/raffles/...`. Putting `shorten-segment` on `/api*` instead would overwrite the stats call's `from` and
`to` with `s=…` and strip nothing, so `default_viewer_request_function_arn` deliberately overrides the
default behaviour only.

`shorten-segment` derives `{COUNTRY}|{REGION}|{PLATFORM}|{DEVICE}` from the CloudFront device and
geolocation headers and **overwrites the querystring** with `s={segment}`. That single value then keys
the cache and lands in `cs-uri-query` on every log line, including cache hits, which is what makes
analytics free of any per-click write.

Its source is `edge/segment.js` in the shorten repository, and Terraform cannot read across repositories.
So this repo commits a placeholder body and `lifecycle { ignore_changes = [code] }`, the same split that
`placeholder.zip` gives the Lambdas, and the app's deploy workflow publishes the real thing:

```bash
aws cloudfront update-function --name shorten-segment --function-stage DEVELOPMENT \
  --function-config '{"Comment":"segment","Runtime":"cloudfront-js-2.0"}' \
  --function-code fileb://edge/segment.js --if-match "$ETAG"
aws cloudfront publish-function --name shorten-segment --if-match "$ETAG"
```

The placeholder emits `s=XX%7CXX%7Cother%7Cother`, which is the same value the real function emits for a
viewer it cannot classify, so a distribution running the placeholder answers correctly from the default
URL rather than erroring. The separator is percent-encoded because a Lambda function URL refuses a raw `|`
in a query string with a 400 before the function is invoked; the redirect decodes it.

### Why the headers are on the origin request policy

A CloudFront function at the viewer-request event runs before the cache lookup, so it is not obvious
that an *origin request* policy makes `CloudFront-Viewer-Country` visible to it. It does. CloudFront's
own documentation says it adds these headers "to the requests that CloudFront receives from viewers and
forwards on to your origin **or edge function**", and AWS's `redirect-based-on-country` function sample
states the requirement directly: you must "allow these headers (or allow all viewer headers) in a
CloudFront origin request policy **or** cache policy".

- https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/adding-cloudfront-headers.html
- https://github.com/aws-samples/amazon-cloudfront-functions/blob/main/redirect-based-on-country/README.md

So `shorten-viewer`, the origin request policy on the default behaviour, whitelists the six
`CloudFront-Is-*-Viewer` headers plus `CloudFront-Viewer-Country` and `CloudFront-Viewer-Country-Region`,
and forwards all query strings. The managed `AllViewerAndCloudFrontHeaders` policy is not usable here
because it omits `CloudFront-Viewer-Country-Region`, which the region dimension needs.

**These headers must never move into the cache policy.** `shorten-code`, the cache policy, keys on the
URL path and the single query string `s`, with no headers and no cookies. Adding the geolocation headers
there would multiply the cache key by every country, region, platform and device *on top of* the `s`
value that already encodes them, and the redirect cache would stop hitting.

### Origin protection

Both function URLs stay public, as they must to serve as CloudFront custom origins. CloudFront adds
`X-Origin-Verify` to every request it sends to them, from `SHORTEN_ORIGIN_VERIFY`, and the same value
reaches both functions as `ORIGIN_VERIFY` in their environment, so each rejects anything that arrived
without it. Rotating it is one repository secret and one workflow run; the functions read the
environment variable on cold start, so allow a few minutes of both values being in flight.

The two functions answer a missing or wrong header differently, deliberately but inconsistently:
`shorten-redirect` returns **403**, `shorten-mgmt` returns **404**. The redirect path is a public
endpoint whose only caller is CloudFront, so refusing loudly is fine; the management API prefers to give
a prober nothing to distinguish "wrong header" from "no such route". Anything asserting on these — a QA
script, a monitor — should expect the two different codes rather than assume one.

### The two post-apply steps

`SHORTEN_ORIGIN_VERIFY` is a secret and can be set before the first apply. `SHORTEN_PUBLIC_BASE_URL`
cannot: it is the distribution's own address, and threading it back into a function's environment is the
cycle described under Administrator sign-in — function environment → function → function URL →
distribution → distribution domain. So the first apply runs with it empty, `site_url` in the `apps`
output names the distribution, and the second apply gives `shorten-mgmt` the value as `PUBLIC_BASE_URL`.
It moves to the custom domain if one is ever configured.

It matters more than it looks. `POST /api/links` returns `short_url`, the link the user copies, and with
`PUBLIC_BASE_URL` empty the function falls back to the request host — which behind the `/api*`
behaviour's managed AllViewerExceptHostHeader policy is the `*.lambda-url.*.on.aws` origin, not the
distribution. Links handed out in that window **bypass CloudFront entirely**: no cache, no `s=` segment,
no access log line, so those clicks never appear in the analytics. Nothing errors. Set it on the second
apply, and treat any link created before that as disposable.

### Analytics

`modules/analytics` is shared, like `modules/sites`, because an app never owns a bucket:

| Thing | Name |
|---|---|
| logs bucket | `aws-cloud-logs-<account-id>` |
| Athena results bucket | `aws-cloud-athena-<account-id>` |
| Athena workgroup | `aws-cloud-analytics` |
| Glue database | `aws_cloud` |
| Glue table | `cloudfront_logs` |

CloudFront standard logging v2 writes gzipped W3C files into the logs bucket under
`AWSLogs/<account-id>/CloudFront/{yyyy}/{MM}/{dd}/`, expiring after 90 days. The delivery source and the
delivery itself are created through the `aws.us_east_1` provider alias, because CloudFront is a global
service and its log deliveries live in `us-east-1`; the delivery destination sits in the analytics module
for the same reason and is shared by anything else that later logs into the same bucket. **Confirm the
`AWSLogs/<account-id>/CloudFront/` prefix against the first delivered object** (`aws s3 ls
s3://aws-cloud-logs-<account-id>/ --recursive | head`); it is AWS's default for vended CloudFront logs
and both the Glue table's `location` and its `storage.location.template` are built from it, so if AWS
ever spells the service segment differently the fix is `local.cloudfront_log_prefix`.

The Glue table uses **partition projection** on `year`, `month` and `day` — never a crawler, which bills
per run. Column names are the log field names mechanically lowercased with every `-` turned into `_` and
`cs(Host)`-style parentheses dropped, so `cs-uri-stem` is `cs_uri_stem`, `sc-status` is `sc_status`,
`x-edge-result-type` is `x_edge_result_type` and `cs(User-Agent)` is `cs_user_agent`. The first two
columns keep their log names, `date` and `time`, which are reserved words in Athena and must be written
with backticks. The two header lines of each W3C file are skipped by `skip.header.line.count`.

The Athena workgroup enforces its configuration and caps every query at 1 GB scanned, so a mistake in
the rollup query fails rather than bills. Results expire from their bucket after 7 days. The rollup
function receives `ATHENA_OUTPUT`, `ATHENA_WORKGROUP`, `GLUE_DATABASE`, `GLUE_TABLE` and `LOGS_BUCKET`
in its environment, and its runtime role — and only shorten's, because `analytics` is null for every
other app — may start and read queries in that workgroup, read the Glue catalog, read the logs bucket
and read and write the results bucket.

### Alarms

Three, and no more, because the ten free alarms were already spent: `shorten-redirect-errors` and
`shorten-mgmt-errors` on each function's `Errors` metric, and `shorten-rollup-failed`, which watches
`AWS/Lambda` `Errors` for `shorten-rollup` over a 24-hour period with `treat_missing_data = "breaching"`,
so a night where the rollup did not run at all alarms exactly like a night where it crashed. No canary:
the redirect path is the site, and the redirect errors alarm already covers it.

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
