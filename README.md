# Terraform AWS Project

This project stores its main Terraform state in a private, versioned S3 bucket.
The state bucket is provisioned separately because Terraform must have a
working backend before it can initialize the main configuration.

## Prerequisites

- Terraform 1.10 or later
- AWS credentials with permission to create the bootstrap bucket and manage
  the project infrastructure
- A globally unique S3 bucket name

## Create the state bucket

From the repository root, initialize and apply the bootstrap configuration.
The bootstrap's own state remains local, so keep its state file backed up and
secure.

```powershell
terraform -chdir=bootstrap/state init
terraform -chdir=bootstrap/state apply -var="state_bucket_name=your-unique-state-bucket-name"
```

The bucket enables versioning, server-side encryption, and all S3 Block Public
Access settings. Its bucket policy rejects non-TLS requests. The AWS identity
used for Terraform must still be granted access to the bucket and its objects,
including permissions needed for the S3 lock file. The bootstrap also prevents
accidental bucket destruction.

## Configure and initialize the S3 backend

Create a local backend configuration from the example and replace the bucket
name with the name used above. In `backend.hcl`, `bucket` must be only the
bucket name (for example, `my-unique-terraform-state`), not an S3 URI and not
a path. `key` is the object path inside that bucket, and `region` must be set.
`backend.hcl` is ignored by Git.

```powershell
Copy-Item backend.hcl.example backend.hcl
```

Initialize the main configuration and migrate any existing local state:

```powershell
terraform init -backend-config=backend.hcl -migrate-state
```

If initialization reports a missing region, confirm you ran this command from
the repository root and passed `-backend-config=backend.hcl`. If it says a
value must not contain `//`, remove `s3://` and any slash-separated path from
the `bucket` value; keep the path only in `key`.

Terraform uses S3's native lock file (`use_lockfile = true`); a DynamoDB lock
table is not required. Do not commit backend credentials or bucket-specific
configuration. Credentials should be supplied through the AWS CLI profile,
environment, or another standard AWS credential provider.

For a different environment, use a distinct state key, such as
`terraform-aws-project/prod/terraform.tfstate`.

## Apply the infrastructure

After backend initialization, use Terraform from the repository root as usual:

```powershell
terraform plan
terraform apply
```

The web instance uses the latest Canonical Ubuntu 24.04 LTS AMI in the selected
region, matching its `apt`-based Nginx installation script.

## Project structure

- `modules/vpc` creates the VPC, public and private subnets, gateways, and
  route tables.
- `modules/security` creates the ALB and EC2 security groups.
- `modules/ec2` discovers the Ubuntu 24.04 AMI and creates the private web
  instance.
- `modules/alb` creates the public Application Load Balancer, target group,
  attachment, and HTTP listener.
- `modules/s3` creates the private, encrypted, versioned S3 bucket and its
  public-access and TLS protections.
- `bootstrap/state` calls `modules/s3` to create the bucket used by the root
  configuration's remote backend.

The root configuration composes these modules and exposes the VPC ID, ALB URL,
and EC2 instance ID. `moved.tf` maps the original root-level resources to their
new module addresses so Terraform can preserve existing infrastructure during
the refactor.
