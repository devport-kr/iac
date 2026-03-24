output "function_name" {
  description = "Name of the Lambda function"
  value       = aws_lambda_function.crawler.function_name
}

output "function_arn" {
  description = "ARN of the Lambda function"
  value       = aws_lambda_function.crawler.arn
}

output "function_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda.arn
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.crawler.name
}

output "ecr_repository_url" {
  description = "ECR repository URL for the crawler image"
  value       = aws_ecr_repository.crawler.repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.crawler.arn
}

output "function_url" {
  description = "Lambda function URL (if enabled)"
  value       = var.enable_function_url ? aws_lambda_function_url.crawler[0].function_url : ""
}
