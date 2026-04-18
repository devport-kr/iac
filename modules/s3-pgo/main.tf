#------------------------------------------------------------------------------
# S3 Bucket for Spring Boot PGO (Profile-Guided Optimization) artifacts
# Long-lived, permanent storage. CI downloads `<iprof_key>` at build time;
# the EC2 host uploads a freshly extracted profile after running JFR.
#------------------------------------------------------------------------------

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "pgo" {
  bucket = "${var.project_name}-${var.environment}-pgo-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "${var.project_name}-${var.environment}-pgo"
  }
}

resource "aws_s3_bucket_versioning" "pgo" {
  bucket = aws_s3_bucket.pgo.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pgo" {
  bucket = aws_s3_bucket.pgo.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "pgo" {
  bucket = aws_s3_bucket.pgo.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Keep storage tidy: drop noncurrent versions after 30 days. Current versions
# (the live profile) are never expired.
resource "aws_s3_bucket_lifecycle_configuration" "pgo" {
  bucket = aws_s3_bucket.pgo.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
