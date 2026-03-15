#------------------------------------------------------------------------------
# GitHub Actions OIDC — keyless auth, no long-lived AWS keys needed
#------------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github_actions" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]

  tags = {
    Name = "${var.project_name}-${var.environment}-github-oidc"
  }
}

#------------------------------------------------------------------------------
# IAM Role — only the devport-kr/devport-web main branch can assume it
#------------------------------------------------------------------------------
resource "aws_iam_role" "github_actions_frontend" {
  name = "${var.project_name}-${var.environment}-github-actions-frontend"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github_actions.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:devport-kr/devport-web:ref:refs/heads/main"
          }
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-github-actions-frontend"
  }
}

resource "aws_iam_role_policy" "github_actions_frontend" {
  name = "${var.project_name}-${var.environment}-github-actions-frontend-policy"
  role = aws_iam_role.github_actions_frontend.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          module.s3_cloudfront.frontend_bucket_arn,
          "${module.s3_cloudfront.frontend_bucket_arn}/*"
        ]
      },
      {
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:distribution/${module.s3_cloudfront.cloudfront_distribution_id}"
      }
    ]
  })
}
