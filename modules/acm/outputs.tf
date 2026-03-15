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

output "api_certificate_arn" {
  description = "ARN of the regional ACM certificate for the API origin"
  value       = aws_acm_certificate.api.arn
}

output "api_validated_certificate_arn" {
  description = "ARN of the validated regional ACM certificate for the API origin"
  value       = aws_acm_certificate_validation.api.certificate_arn
}
