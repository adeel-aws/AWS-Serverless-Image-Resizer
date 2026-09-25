output "website_url" {
  description = "Open this CloudFront URL after apply."
  value       = "https://${module.cloudfront.cloudfront_distribution_domain_name}"
}

output "api_endpoint" {
  description = "The API Gateway endpoint; the frontend normally uses CloudFront /api instead."
  value       = module.api.apigatewayv2_api_api_endpoint
}

output "raw_bucket_name" {
  value = module.raw_bucket.s3_bucket_id
}

output "processed_bucket_name" {
  value = module.processed_bucket.s3_bucket_id
}

output "cloudfront_distribution_id" {
  description = "GitHub Actions uses this to invalidate the frontend cache after deployment."
  value       = module.cloudfront.cloudfront_distribution_id
}

output "github_deploy_role_arn" {
  description = "Add this as the AWS_DEPLOY_ROLE_ARN GitHub Actions repository variable in the application repository."
  value       = module.github_deploy_role.arn
}

output "upload_lambda_name" {
  value = module.upload_lambda.lambda_function_name
}

output "status_lambda_name" {
  value = module.status_lambda.lambda_function_name
}

output "resizer_lambda_name" {
  value = module.resizer_lambda.lambda_function_name
}
