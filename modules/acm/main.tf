#------------------------------------------------------------------------------
# ACM Certificate for CloudFront (must be in us-east-1)
#------------------------------------------------------------------------------
resource "aws_acm_certificate" "cloudfront" {
  provider = aws.us_east_1

  domain_name               = var.domain_name
  subject_alternative_names = var.create_www_cert ? ["www.${var.domain_name}"] : []
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-cloudfront-cert"
  }
}

#------------------------------------------------------------------------------
# Route 53 DNS Validation Records
#------------------------------------------------------------------------------
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  zone_id         = var.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

#------------------------------------------------------------------------------
# ACM Certificate Validation
#------------------------------------------------------------------------------
resource "aws_acm_certificate_validation" "cloudfront" {
  provider = aws.us_east_1

  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}
