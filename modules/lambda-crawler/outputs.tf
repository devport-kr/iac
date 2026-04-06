output "function_names" {
  description = "Map of tier name to Lambda function name"
  value       = { for k, f in aws_lambda_function.crawler : k => f.function_name }
}

output "function_arns" {
  description = "List of all Lambda function ARNs"
  value       = [for f in aws_lambda_function.crawler : f.arn]
}

output "function_role_arn" {
  description = "ARN of the Lambda IAM role"
  value       = aws_iam_role.lambda.arn
}

output "ecr_repository_url" {
  description = "ECR repository URL for the crawler image"
  value       = aws_ecr_repository.crawler.repository_url
}

output "ecr_repository_arn" {
  description = "ECR repository ARN"
  value       = aws_ecr_repository.crawler.arn
}
