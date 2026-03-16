output "cloudfront_certificate_arn" {
  description = "ARN of the CloudFront ACM certificate"
  value       = aws_acm_certificate.cloudfront.arn
}

output "validated_certificate_arn" {
  description = "ARN of the validated CloudFront ACM certificate"
  value       = aws_acm_certificate_validation.cloudfront.certificate_arn
}

output "cloudfront_certificate_status" {
  description = "Status of the CloudFront certificate"
  value       = aws_acm_certificate.cloudfront.status
}

