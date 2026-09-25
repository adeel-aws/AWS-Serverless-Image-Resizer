# AWS infrastructure

This directory contains the entire Terraform root configuration—there is no nested `terraform/` folder.

## What `terraform apply` creates

| Area | AWS services |
| --- | --- |
| Application delivery | CloudFront distribution, private processed S3 bucket for the website and generated downloads |
| Image processing | Private raw S3 bucket, S3 event notification, and three Node.js Lambda functions |
| API and state | API Gateway HTTP API and DynamoDB resize-job table |
| Continuous delivery | Existing account-wide GitHub OIDC provider, a main-branch-only deploy role, and a least-privilege deployment policy |

The root configuration uses module blocks only; it contains no Terraform `resource` blocks.

## Before you apply

1. Install Terraform 1.5.7+, AWS CLI v2, Node.js 20+, and Python 3.
2. Configure AWS CLI credentials and verify the intended account:

   ```powershell
   aws sts get-caller-identity
   ```

3. Create one empty GitHub repository for this entire project, for example `<your-owner>/pixeldrop-app`.

## Configure the variables

From this `infra` directory:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
```

Set your values in `terraform.tfvars`:

```hcl
region                        = "us-east-1"
project_name                  = "pixeldrop"
bucket_suffix                 = "yourname-2026-01"
github_application_repository = "<your-owner>/pixeldrop-app"
```

`bucket_suffix` must be globally unique because S3 bucket names are shared across AWS. The GitHub repository must be exact; the deployment role trusts only `main` in that repository.

## First deployment — exact steps

Before the first apply, prepare the application package so Terraform can upload the initial frontend and Lambda code:

```powershell
cd ../app/frontend
npm.cmd install
npm.cmd run build

cd ../backend
npm.cmd install --omit=dev

cd ../../infra
terraform init
terraform fmt -check
terraform validate
terraform plan
terraform apply
```

Review the plan and type `yes` only if the account, region, and resources are correct. CloudFront usually needs several minutes to finish provisioning.

## After apply: configure GitHub Actions

Copy these Terraform outputs into the project repository's **GitHub → Settings → Secrets and variables → Actions → Variables**:

```powershell
terraform output -raw github_deploy_role_arn
terraform output -raw processed_bucket_name
terraform output -raw cloudfront_distribution_id
terraform output -raw upload_lambda_name
terraform output -raw status_lambda_name
terraform output -raw resizer_lambda_name
```

Create Actions variables named `AWS_DEPLOY_ROLE_ARN`, `PROCESSED_BUCKET_NAME`, `CLOUDFRONT_DISTRIBUTION_ID`, `UPLOAD_LAMBDA_NAME`, `STATUS_LAMBDA_NAME`, and `RESIZER_LAMBDA_NAME` respectively. Also add `AWS_REGION` with the configured region.

Then follow the [application delivery guide](../app/README.md) to push this entire project from its root. The initial GitHub push deploys the application automatically.

## Open the website

```powershell
terraform output -raw website_url
```

Open the generated CloudFront HTTPS URL and upload a JPEG, PNG, or WebP image smaller than 8 MB. No DNS zone or ACM certificate is needed.

## When to use Terraform again

- **Application code change:** push the project repository; GitHub Actions deploys it.
- **AWS, IAM, bucket, Lambda memory, API, or CloudFront change:** modify this directory and run `terraform plan`, then `terraform apply`.

## Costs and cleanup

S3, Lambda, DynamoDB, API Gateway, and CloudFront can incur usage charges. Original and processed uploads expire after one day. When finished with the project:

```powershell
terraform destroy
```

> **Infrastructure ready?** Continue to the [application delivery guide](../app/README.md).
