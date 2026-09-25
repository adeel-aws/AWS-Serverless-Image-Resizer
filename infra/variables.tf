variable "region" {
  type        = string
  description = "AWS region for the application."
  default     = "us-east-1"
}

variable "project_name" {
  type        = string
  description = "Lowercase project prefix used in resource names."
  default     = "pixeldrop"
}

variable "bucket_suffix" {
  type        = string
  description = "A globally unique lowercase suffix for the two S3 bucket names, e.g. yourname-2026."
}

variable "github_application_repository" {
  type        = string
  description = "GitHub application repository allowed to deploy, in owner/repository form. Leave empty to disable GitHub Actions deployment access."
  default     = ""
}
