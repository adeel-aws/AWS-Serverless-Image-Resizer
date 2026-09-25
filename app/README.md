# Application delivery

This directory contains the application portion of the PixelDrop monorepo. The GitHub Actions workflow is at the project root so one repository contains the website, backend, and infrastructure.

```text
app/
├── frontend/ React + Vite visitor interface
└── backend/  Node.js Lambda handlers
```

## Before the first release

Complete the [infrastructure manual](../infra/README.md) first. It uses the account-wide GitHub OIDC provider and creates an IAM role trusted only by this repository's `main` branch.

In the one project repository, add these **Actions variables** under **Settings → Secrets and variables → Actions → Variables**. These are values, not secrets; OIDC means you must not add an AWS access key or secret key.

| Variable | Terraform output / value |
| --- | --- |
| `AWS_DEPLOY_ROLE_ARN` | `github_deploy_role_arn` |
| `AWS_REGION` | The region in `terraform.tfvars`, for example `us-east-1` |
| `PROCESSED_BUCKET_NAME` | `processed_bucket_name` |
| `CLOUDFRONT_DISTRIBUTION_ID` | `cloudfront_distribution_id` |
| `UPLOAD_LAMBDA_NAME` | `upload_lambda_name` |
| `STATUS_LAMBDA_NAME` | `status_lambda_name` |
| `RESIZER_LAMBDA_NAME` | `resizer_lambda_name` |

## Push the one project repository

1. Create one empty GitHub repository, for example `<your-owner>/pixeldrop-app`. Do not initialise it with a README.
2. Set `github_application_repository = "<your-owner>/pixeldrop-app"` in `infra/terraform.tfvars`, then run `terraform apply` so the role trusts that exact repository. This deployment already trusts `adeel-aws/pixeldrop-app`.
3. Add the seven Actions variables shown above.
4. From the `cloud-image-resizer` project root, push the whole project:

```powershell
cd "D:\DevOps Projects\Internship Projects\Others\cloud-image-resizer"
git init
git add .
git commit -m "Initial PixelDrop release"
git branch -M main
git remote add origin https://github.com/<your-owner>/pixeldrop-app.git
git push -u origin main
```

That first push triggers the deployment workflow.

## What GitHub Actions deploys

```text
Push to main → GitHub OIDC → temporary AWS credentials
             → build React → sync static files to processed S3 bucket
             → invalidate CloudFront → package backend → update three Lambdas
```

Later, commit and push frontend or backend changes. The root workflow rebuilds and deploys the application without running Terraform again. Use Terraform only when changing AWS infrastructure or IAM permissions.

## Local development

```powershell
cd frontend
npm.cmd install
npm.cmd run dev
```

Open the Vite URL printed in the terminal. The page UI works locally; real image processing starts only after the AWS infrastructure is deployed because `/api/*` is served through CloudFront.

## Manual application deployment

GitHub Actions is the recommended route. If needed, build locally before a first Terraform apply:

```powershell
cd frontend
npm.cmd install
npm.cmd run build

cd ../backend
npm.cmd install --omit=dev
```

> **Application ready?** Continue to the [infrastructure manual](../infra/README.md) for the first Terraform deployment.
