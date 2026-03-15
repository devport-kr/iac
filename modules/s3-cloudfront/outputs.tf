output "frontend_bucket_id" {
  description = "ID of the frontend S3 bucket"
  value       = aws_s3_bucket.frontend.id
}

output "frontend_bucket_arn" {
  description = "ARN of the frontend S3 bucket"
  value       = aws_s3_bucket.frontend.arn
}

output "frontend_bucket_domain_name" {
  description = "Domain name of the frontend S3 bucket"
  value       = aws_s3_bucket.frontend.bucket_regional_domain_name
}

output "cloudfront_distribution_id" {
  description = "ID of the CloudFront distribution"
  value       = aws_cloudfront_distribution.frontend.id
}

output "cloudfront_distribution_arn" {
  description = "ARN of the CloudFront distribution"
  value       = aws_cloudfront_distribution.frontend.arn
}

output "cloudfront_domain_name" {
  description = "Domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.frontend.domain_name
}

output "cloudfront_hosted_zone_id" {
  description = "Route 53 zone ID for CloudFront distribution"
  value       = aws_cloudfront_distribution.frontend.hosted_zone_id
}

output "logs_bucket_id" {
  description = "ID of the CloudFront logs S3 bucket"
  value       = var.enable_logging ? aws_s3_bucket.logs[0].id : ""
}

output "backup_bucket_id" {
  description = "ID of the backups S3 bucket"
  value       = var.enable_backup_bucket ? aws_s3_bucket.backups[0].id : ""
}

output "backup_bucket_arn" {
  description = "ARN of the backups S3 bucket"
  value       = var.enable_backup_bucket ? aws_s3_bucket.backups[0].arn : ""
}

output "backup_bucket_name" {
  description = "Name of the backups S3 bucket"
  value       = var.enable_backup_bucket ? aws_s3_bucket.backups[0].bucket : ""
}
