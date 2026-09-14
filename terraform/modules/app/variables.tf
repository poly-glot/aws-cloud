variable "account_id" {
  type = string
}

variable "alerts_topic_arn" {
  type = string
}

variable "aws_region" {
  type = string
}

variable "analytics" {
  default     = null
  description = "The shared analytics stack: CloudFront standard logging v2 into its logs bucket, and Athena, Glue and S3 access for the app's functions; null leaves the app with none of it"

  type = object({
    athena_workgroup     = string
    athena_workgroup_arn = string
    glue_arns            = list(string)
    glue_database        = string
    glue_table           = string
    log_destination_arn  = string
    logs_bucket          = string
    logs_bucket_arn      = string
    results_bucket       = string
    results_bucket_arn   = string
  })
}

variable "api_cache_policy_id" {
  default     = null
  description = "Cache policy for the api behaviours; null takes the shared 30-second policy"
  type        = string
}

variable "admins" {
  default     = null
  description = "A Cognito user pool for the app's administrators; null leaves the app without one"

  type = object({
    console_url = string
    emails      = optional(list(string), [])
  })
}

variable "canary" {
  default     = null
  description = "Probe a path on the app's site from a canary function the app repo deploys; its alarm period follows the interval so a missing datapoint means a missed run"

  type = object({
    interval_minutes = optional(number, 1)
    path             = string
  })
}

variable "custom_alarms" {
  default     = {}
  description = "Alarms on the app's own EMF metrics, in the namespace named after the app, or on an AWS namespace when namespace and dimensions are given"
  type = map(object({
    comparison_operator = optional(string, "GreaterThanThreshold")
    description         = string
    dimensions          = optional(map(string), {})
    evaluation_periods  = optional(number, 1)
    metric_name         = string
    namespace           = optional(string)
    period              = number
    statistic           = string
    threshold           = number
    treat_missing_data  = optional(string, "notBreaching")
  }))
}

variable "default_cache_policy_id" {
  default     = null
  description = "Cache policy for the default behaviour; null takes the managed CachingOptimized policy"
  type        = string
}

variable "default_origin_function" {
  default     = null
  description = "Serve the default behaviour from this function's url instead of the sites bucket; null keeps the S3 site origin"
  type        = string
}

variable "default_origin_request_policy_id" {
  default     = null
  description = "Origin request policy for the default behaviour; null forwards nothing beyond the cache key"
  type        = string
}

variable "default_viewer_request_function_arn" {
  default     = null
  description = "CloudFront function on the default behaviour's viewer request; null takes the shared router"
  type        = string
}

variable "domain" {
  default     = null
  description = "A custom domain for the site: the certificate is requested at once, and live puts the distribution on the name once the validation record exists and the certificate is issued"

  type = object({
    live = optional(bool, false)
    name = string
  })
}

variable "env" {
  default = {}
  type    = map(string)
}

variable "functions" {
  description = "One Lambda per key, named <app>-<key>; url is null, public, or a site path such as api or api/admin"
  type = map(object({
    concurrency     = optional(number, -1)
    console         = optional(bool, false)
    env             = optional(map(string), {})
    errors_alarm    = optional(bool, false)
    memory          = optional(number, 256)
    schedule        = optional(string)
    throttles_alarm = optional(bool, false)
    timeout         = optional(number, 30)
    url             = optional(string)
  }))

  validation {
    condition     = alltrue([for function in var.functions : function.url == null || can(regex("^(public|api(/[a-z0-9-]+)?)$", function.url))])
    error_message = "url must be null, \"public\", \"api\" or \"api/<segment>\"."
  }

  validation {
    condition     = length(distinct([for function in var.functions : function.url if function.url != null])) == length([for function in var.functions : function.url if function.url != null])
    error_message = "Two functions cannot share a site path."
  }
}

variable "github_subject" {
  description = "The OIDC subject prefix GitHub reports for the app's repository, repo:<owner>@<id>/<repo>@<id>"
  type        = string
}

variable "http_5xx_alarm" {
  default     = false
  description = "Count log lines with status >= 500 from every function that has a url, alarm on five in five minutes"
  type        = bool
}

variable "key_prefix" {
  default     = null
  description = "When set, the runtime role may only touch table items whose partition key starts with this prefix"
  type        = string
}

variable "name" {
  type = string
}

variable "oidc_provider_arn" {
  type = string
}

variable "origin_header" {
  default     = null
  description = "Name of a header CloudFront adds to every request it sends to a function origin, carrying origin_header_value, so the function can refuse anything that bypassed CloudFront"
  type        = string
}

variable "origin_header_value" {
  default   = ""
  sensitive = true
  type      = string
}

variable "secrets" {
  default   = {}
  sensitive = true
  type      = map(string)
}

variable "sites" {
  type = object({
    api_cache_policy_id = string
    bucket              = string
    bucket_arn          = string
    bucket_domain       = string
    router_function_arn = string
    s3_oac_id           = string
  })
}

variable "table" {
  type = object({
    arn  = string
    name = string
  })
}
