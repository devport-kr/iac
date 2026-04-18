output "bucket_name" {
  description = "Name of the PGO S3 bucket (set this as GitHub secret PGO_S3_BUCKET)"
  value       = aws_s3_bucket.pgo.bucket
}

output "bucket_arn" {
  description = "ARN of the PGO S3 bucket"
  value       = aws_s3_bucket.pgo.arn
}

output "iprof_key" {
  description = "S3 object key of the canonical PGO profile"
  value       = var.iprof_key
}

output "iprof_arn" {
  description = "Full ARN of the canonical PGO profile object"
  value       = "${aws_s3_bucket.pgo.arn}/${var.iprof_key}"
}
