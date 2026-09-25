locals {
  raw_bucket_name       = "${var.project_name}-raw-${var.bucket_suffix}"
  processed_bucket_name = "${var.project_name}-processed-${var.bucket_suffix}"
  backend_path          = abspath("${path.module}/../app/backend")
  backend_package_path  = abspath("${path.module}/../app/backend/pixeldrop-lambda-prod.zip")
  frontend_path         = abspath("${path.module}/../app/frontend/dist")

  tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }

  mime_types = {
    css  = "text/css"
    html = "text/html"
    ico  = "image/x-icon"
    js   = "application/javascript"
    json = "application/json"
    png  = "image/png"
    svg  = "image/svg+xml"
  }
}

# Two private buckets only: raw uploads and processed images plus the static web build.
module "raw_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.14.1"

  bucket = local.raw_bucket_name

  block_public_acls                     = true
  block_public_policy                   = true
  ignore_public_acls                    = true
  restrict_public_buckets               = true
  attach_deny_insecure_transport_policy = true

  cors_rule = [
    {
      allowed_methods = ["PUT"]
      allowed_origins = ["*"]
      allowed_headers = ["content-type"]
      expose_headers  = ["ETag"]
      max_age_seconds = 300
    }
  ]

  lifecycle_rule = [
    {
      id      = "delete-uploaded-images"
      enabled = true
      expiration = {
        days = 1
      }
    }
  ]
}

module "processed_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "5.14.1"

  bucket = local.processed_bucket_name

  block_public_acls                     = true
  block_public_policy                   = true
  ignore_public_acls                    = true
  restrict_public_buckets               = true
  attach_deny_insecure_transport_policy = true

  # CloudFront is the only public path to website assets and resized downloads.
  attach_policy = true
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${module.processed_bucket.s3_bucket_arn}/*"
        Condition = { StringEquals = { "AWS:SourceArn" = module.cloudfront.cloudfront_distribution_arn } }
      }
    ]
  })

  lifecycle_rule = [
    {
      id      = "delete-resized-images"
      enabled = true
      filter = {
        prefix = "downloads/"
      }
      expiration = {
        days = 1
      }
    }
  ]
}

module "jobs_table" {
  source  = "terraform-aws-modules/dynamodb-table/aws"
  version = "5.5.0"

  name                           = "${var.project_name}-jobs"
  billing_mode                   = "PAY_PER_REQUEST"
  hash_key                       = "id"
  attributes                     = [{ name = "id", type = "S" }]
  ttl_enabled                    = true
  ttl_attribute_name             = "expiresAt"
  point_in_time_recovery_enabled = true
}

module "upload_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "8.8.0"

  function_name          = "${var.project_name}-create-upload"
  description            = "Creates image resize jobs and pre-signed S3 upload URLs."
  handler                = "upload.handler"
  runtime                = "nodejs20.x"
  timeout                = 15
  memory_size            = 256
  create_package         = false
  local_existing_package = local.backend_package_path

  environment_variables = {
    RAW_BUCKET = module.raw_bucket.s3_bucket_id
    JOBS_TABLE = module.jobs_table.dynamodb_table_id
  }

  allowed_triggers = {
    api_gateway = {
      service = "apigateway"
    }
  }
  create_current_version_allowed_triggers = false

  attach_policy_json = true
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${module.raw_bucket.s3_bucket_arn}/uploads/*" },
      { Effect = "Allow", Action = ["dynamodb:PutItem"], Resource = module.jobs_table.dynamodb_table_arn }
    ]
  })
}

module "status_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "8.8.0"

  function_name          = "${var.project_name}-job-status"
  description            = "Returns the status of an image resize job."
  handler                = "status.handler"
  runtime                = "nodejs20.x"
  timeout                = 10
  memory_size            = 256
  create_package         = false
  local_existing_package = local.backend_package_path

  environment_variables = {
    JOBS_TABLE = module.jobs_table.dynamodb_table_id
  }

  allowed_triggers = {
    api_gateway = {
      service = "apigateway"
    }
  }
  create_current_version_allowed_triggers = false

  attach_policy_json = true
  policy_json = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["dynamodb:GetItem"], Resource = module.jobs_table.dynamodb_table_arn }]
  })
}

module "resizer_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "8.8.0"

  function_name          = "${var.project_name}-resize-image"
  description            = "Resizes an uploaded image and saves the result."
  handler                = "resizer.handler"
  runtime                = "nodejs20.x"
  timeout                = 60
  memory_size            = 1024
  create_package         = false
  local_existing_package = local.backend_package_path

  environment_variables = {
    RAW_BUCKET       = module.raw_bucket.s3_bucket_id
    PROCESSED_BUCKET = module.processed_bucket.s3_bucket_id
    JOBS_TABLE       = module.jobs_table.dynamodb_table_id
  }

  attach_policy_json = true
  policy_json = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["s3:GetObject"], Resource = "${module.raw_bucket.s3_bucket_arn}/uploads/*" },
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${module.processed_bucket.s3_bucket_arn}/downloads/*" },
      { Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:UpdateItem"], Resource = module.jobs_table.dynamodb_table_arn }
    ]
  })
}

# This module creates both the S3 event notification and Lambda invoke permission.
module "raw_upload_notification" {
  source  = "terraform-aws-modules/s3-bucket/aws//modules/notification"
  version = "5.14.1"

  bucket = module.raw_bucket.s3_bucket_id
  lambda_notifications = {
    resize = {
      function_arn  = module.resizer_lambda.lambda_function_arn
      function_name = module.resizer_lambda.lambda_function_name
      events        = ["s3:ObjectCreated:*"]
      filter_prefix = "uploads/"
    }
  }
}

module "api" {
  source  = "terraform-aws-modules/apigateway-v2/aws"
  version = "4.0.0"

  name                   = "${var.project_name}-api"
  description            = "HTTP API for the PixelDrop frontend."
  protocol_type          = "HTTP"
  create_api_domain_name = false

  cors_configuration = {
    allow_headers = ["content-type"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_origins = ["*"]
  }

  integrations = {
    "POST /api/uploads" = {
      lambda_arn             = module.upload_lambda.lambda_function_arn
      payload_format_version = "2.0"
      timeout_milliseconds   = 15000
    }
    "GET /api/jobs/{id}" = {
      lambda_arn             = module.status_lambda.lambda_function_arn
      payload_format_version = "2.0"
      timeout_milliseconds   = 10000
    }
  }
}

module "cloudfront" {
  source  = "terraform-aws-modules/cloudfront/aws"
  version = "6.7.1"

  enabled             = true
  comment             = "${var.project_name} image resizer"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"

  # Use CloudFront's generated domain and default certificate; no DNS or ACM is required.
  viewer_certificate = {
    cloudfront_default_certificate = true
  }

  origin_access_control = {
    processed_s3 = {
      description      = "Read private PixelDrop web and download files"
      origin_type      = "s3"
      signing_behavior = "always"
      signing_protocol = "sigv4"
    }
  }

  origin = {
    processed_s3 = {
      domain_name               = module.processed_bucket.s3_bucket_bucket_regional_domain_name
      origin_access_control_key = "processed_s3"
    }
    api = {
      domain_name = trimprefix(module.api.apigatewayv2_api_api_endpoint, "https://")
      custom_origin_config = {
        http_port              = 80
        https_port             = 443
        origin_protocol_policy = "https-only"
        origin_ssl_protocols   = ["TLSv1.2"]
      }
    }
  }

  default_cache_behavior = {
    target_origin_id       = "processed_s3"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  ordered_cache_behavior = [
    {
      path_pattern           = "api/*"
      target_origin_id       = "api"
      viewer_protocol_policy = "https-only"
      allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
      cached_methods         = ["GET", "HEAD"]
      compress               = true
      cache_policy_name      = "Managed-CachingDisabled"
    }
  ]

}

# GitHub Actions receives short-lived AWS credentials through OIDC. The role is
# created only after you specify the standalone application repository.
module "github_oidc_provider" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-oidc-provider"
  version = "6.8.1"

  # The GitHub OIDC provider is account-wide and already exists in this account.
  create = false
}

module "github_deploy_policy" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-policy"
  version = "6.8.1"

  create      = var.github_application_repository != ""
  name        = "${var.project_name}-github-deploy"
  description = "Least-privilege deployment access for the PixelDrop application workflow."
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DeployFrontend"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = module.processed_bucket.s3_bucket_arn
      },
      {
        Sid      = "WriteFrontendFiles"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${module.processed_bucket.s3_bucket_arn}/*"
      },
      {
        Sid    = "DeployLambdaCode"
        Effect = "Allow"
        Action = ["lambda:GetFunction", "lambda:GetFunctionConfiguration", "lambda:UpdateFunctionCode"]
        Resource = [
          module.upload_lambda.lambda_function_arn,
          module.status_lambda.lambda_function_arn,
          module.resizer_lambda.lambda_function_arn
        ]
      },
      {
        Sid      = "InvalidateCloudFront"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation", "cloudfront:GetDistribution", "cloudfront:GetDistributionConfig"]
        Resource = module.cloudfront.cloudfront_distribution_arn
      }
    ]
  })
}

module "github_deploy_role" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role"
  version = "6.8.1"

  create             = var.github_application_repository != ""
  name               = "${var.project_name}-github-deploy"
  enable_github_oidc = true
  oidc_subjects = var.github_application_oidc_subject == null ? [] : [
    var.github_application_oidc_subject
  ]
  oidc_wildcard_subjects = var.github_application_oidc_subject == null ? [
    "${var.github_application_repository}:ref:refs/heads/main"
  ] : []
  policies = {
    PixelDropDeployment = module.github_deploy_policy.arn
  }

  depends_on = [module.github_oidc_provider]
}

# Upload the Vite build to the processed bucket. Run `npm run build` first.
module "frontend_files" {
  for_each = fileset(local.frontend_path, "**")

  source  = "terraform-aws-modules/s3-bucket/aws//modules/object"
  version = "5.14.1"

  bucket        = module.processed_bucket.s3_bucket_id
  key           = each.value
  file_source   = "${local.frontend_path}/${each.value}"
  source_hash   = filemd5("${local.frontend_path}/${each.value}")
  content_type  = lookup(local.mime_types, element(reverse(split(".", each.value)), 0), "application/octet-stream")
  cache_control = each.value == "index.html" ? "no-cache" : "public, max-age=31536000, immutable"
}
