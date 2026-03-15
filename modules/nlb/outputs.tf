output "nlb_arn" {
  description = "ARN of the NLB"
  value       = aws_lb.api.arn
}

output "nlb_dns_name" {
  description = "DNS name of the NLB"
  value       = aws_lb.api.dns_name
}

output "nlb_zone_id" {
  description = "Route 53 zone ID of the NLB"
  value       = aws_lb.api.zone_id
}

output "target_group_arn" {
  description = "ARN of the target group"
  value       = aws_lb_target_group.api.arn
}

output "listener_arn" {
  description = "ARN of the HTTPS listener"
  value       = aws_lb_listener.api.arn
}
