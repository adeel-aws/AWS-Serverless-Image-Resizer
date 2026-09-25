# PixelDrop — Serverless Image Resizer on AWS

<p align="center">
  <strong>Resize, convert, and download images through a polished serverless web experience.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/AWS-Serverless-FF9900?logo=amazonaws&logoColor=white" alt="AWS Serverless" />
  <img src="https://img.shields.io/badge/IaC-Terraform-7B42BC?logo=terraform&logoColor=white" alt="Terraform" />
  <img src="https://img.shields.io/badge/Frontend-React-61DAFB?logo=react&logoColor=0B1020" alt="React" />
  <img src="https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-2088FF?logo=githubactions&logoColor=white" alt="GitHub Actions" />
</p>

PixelDrop is an image-resizing website built as a practical cloud project. A visitor uploads a JPEG, PNG, or WebP image, selects dimensions, format, and quality, then downloads the processed result. The browser never sends the file through a traditional application server: it uploads safely to S3 through a short-lived pre-signed URL.

## Architecture

<p align="center">
  <img src="Architecture/architecture.png" alt="PixelDrop AWS architecture" width="100%" />
</p>

## Why this project is interesting

| User experience | Serverless platform | Delivery |
| --- | --- | --- |
| Responsive React interface, direct uploads, resize progress, and download action | Private S3 buckets, Lambda, DynamoDB, API Gateway, CloudFront, lifecycle deletion | Terraform modules plus a GitHub Actions application-release workflow using OIDC |

- Original and generated files expire after 24 hours to limit storage cost and retention.
- Only CloudFront can read the processed/web bucket; the raw upload bucket remains private.
- DynamoDB tracks the state transition from `waiting` to `processing`, `complete`, or `failed`.
- GitHub Actions uses temporary OIDC credentials—no long-lived AWS access keys need to be stored in GitHub.

## Application flow

```mermaid
flowchart LR
    A[Visitor chooses image and resize options]
    B[POST /api/uploads]
    C[Upload Lambda creates job]
    D[(DynamoDB job status)]
    E[Pre-signed S3 upload URL]
    F[Visitor uploads original to raw S3]
    G[Raw S3 ObjectCreated event]
    H[Resizer Lambda processes image]
    I[Processed S3 stores download]
    J[Visitor polls GET /api/jobs/id]
    K[CloudFront serves resized download]

    A --> B --> C
    C --> D
    C --> E --> F
    F --> G --> H
    H --> D
    H --> I --> K
    F --> J --> D
    D -->|complete download path| K
```

## Website screenshots

| Dashboard | Select an image |
| --- | --- |
| ![PixelDrop dashboard](screenshots/dashboard.png) | ![Image selection screen](screenshots/select-image.png) |

| Resize settings | Processing complete |
| --- | --- |
| ![Image resize settings](screenshots/resize-image.png) | ![Resized image ready to download](screenshots/resized-and-ready-to-download.png) |

| Downloaded result |
| --- |
| ![Downloaded resized image](screenshots/downloaded.png) |

## Start here

```text
1. Provision the AWS platform           → infra/
2. Configure repository Actions values  → app/
3. Push application changes             → GitHub Actions deploys them automatically
```

| Directory | Purpose |
| --- | --- |
| [infra/](infra/README.md) | Terraform for the AWS platform, GitHub OIDC trust, outputs, first deployment, and cleanup. |
| [app/](app/README.md) | React frontend and Lambda backend. The deployment workflow lives at the repository root. |
| [Architecture/](Architecture/) | Architecture image and application-flow Mermaid source. |
| [screenshots/](screenshots/) | Browser screenshots captured after deployment. |

## Project flow

```text
Terraform apply → AWS platform and GitHub OIDC role ready → push app source
                → GitHub Actions builds React + Lambda package → S3 + Lambda deployment
                → CloudFront cache invalidation → visitors see the release
```

Want to deploy the same project? Start with the [infrastructure manual](infra/README.md), then continue to the [application delivery guide](app/README.md).
