#------------------------------------------------------------------------------
# Spring Boot PGO — long-lived bucket + IAM glue
#
# - Bucket lives in modules/s3-pgo (versioned, encrypted, private)
# - EC2 (Spring Boot host) gets PutObject so it can upload freshly extracted
#   profiles via `aws s3 cp` after a JFR run
# - A standalone managed policy grants s3:GetObject on the canonical key. Attach
#   it to whichever IAM user backs the GitHub Actions AWS_ACCESS_KEY_ID secret:
#       aws iam attach-user-policy \
#         --user-name <user> \
#         --policy-arn $(terraform output -raw pgo_read_policy_arn)
#
# After apply, set the GitHub secret PGO_S3_BUCKET to the value of
# `terraform output -raw pgo_bucket_name`.
#------------------------------------------------------------------------------

module "s3_pgo" {
  source = "./modules/s3-pgo"

  project_name = var.project_name
  environment  = var.environment
}

# EC2 → PGO bucket: upload freshly extracted .iprof from the running JVM
resource "aws_iam_role_policy" "ec2_pgo_upload" {
  name = "${var.project_name}-${var.environment}-ec2-pgo-upload"
  role = module.ec2.iam_role_name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.s3_pgo.bucket_arn,
          "${module.s3_pgo.bucket_arn}/*"
        ]
      }
    ]
  })
}

# Managed read-only policy for CI: only the canonical iprof key
resource "aws_iam_policy" "pgo_read" {
  name        = "${var.project_name}-${var.environment}-pgo-read"
  description = "Read-only access to the canonical Spring Boot PGO profile"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = module.s3_pgo.iprof_arn
      },
      {
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = module.s3_pgo.bucket_arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["pgo/", "pgo/*"]
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-pgo-read"
  }
}

output "pgo_bucket_name" {
  description = "Set as GitHub secret PGO_S3_BUCKET (just the bucket name, no s3:// prefix)"
  value       = module.s3_pgo.bucket_name
}

output "pgo_iprof_key" {
  description = "Object key for the canonical PGO profile"
  value       = module.s3_pgo.iprof_key
}

output "pgo_read_policy_arn" {
  description = "Attach to the IAM user backing GitHub Actions static AWS keys"
  value       = aws_iam_policy.pgo_read.arn
}
