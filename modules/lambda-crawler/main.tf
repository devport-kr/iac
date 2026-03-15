#------------------------------------------------------------------------------
# IAM Role for Lambda
#------------------------------------------------------------------------------
resource "aws_iam_role" "lambda" {
  name = "${var.project_name}-${var.environment}-crawler-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-crawler-role"
  }
}

# Lambda execution role with VPC access
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

#------------------------------------------------------------------------------
# Lambda Function
# VPC-attached - connects to DB via private IP
# Uses NAT Gateway for internet access (crawling external APIs)
#------------------------------------------------------------------------------

# Create placeholder Lambda code
data "archive_file" "lambda_placeholder" {
  type        = "zip"
  output_path = "${path.module}/lambda_placeholder.zip"

  source {
    content  = <<-EOF
      import json
      import os
      import urllib.request

      # psycopg2 comes from Lambda layer
      import psycopg2

      def get_db_connection():
          """Create PostgreSQL connection from environment variables."""
          return psycopg2.connect(
              host=os.environ['DB_HOST'],
              port=int(os.environ.get('DB_PORT', 5432)),
              database=os.environ['DB_NAME'],
              user=os.environ['DB_USER'],
              password=os.environ['DB_PASSWORD'],
              connect_timeout=10
          )

      def lambda_handler(event, context):
          """
          DevPort Crawler Lambda

          This Lambda crawls tech news from various sources and writes
          directly to the PostgreSQL database.

          Sources:
          - GitHub Trending
          - Hacker News
          - Reddit (r/programming, r/webdev, etc.)
          """

          print(f"Crawler invoked. Connecting to DB at {os.environ['DB_HOST']}")

          # TODO: Implement crawling logic
          # 1. Fetch from GitHub trending
          # 2. Fetch from Hacker News API
          # 3. Fetch from Reddit API

          # Example: Write to database
          # conn = get_db_connection()
          # try:
          #     with conn.cursor() as cur:
          #         cur.execute(
          #             "INSERT INTO crawled_items (source, title, url, crawled_at) VALUES (%s, %s, %s, NOW())",
          #             ('github', 'Example Repo', 'https://github.com/example/repo')
          #         )
          #     conn.commit()
          # finally:
          #     conn.close()

          return {
              'statusCode': 200,
              'body': json.dumps({
                  'message': 'Crawler executed successfully',
                  'timestamp': context.get_remaining_time_in_millis()
              })
          }
      EOF
    filename = "handler.py"
  }
}

# Current region for Lambda layer ARN
data "aws_region" "current" {}

resource "aws_lambda_function" "crawler" {
  filename         = data.archive_file.lambda_placeholder.output_path
  function_name    = "${var.project_name}-${var.environment}-crawler"
  role             = aws_iam_role.lambda.arn
  handler          = "handler.lambda_handler"
  source_code_hash = data.archive_file.lambda_placeholder.output_base64sha256
  runtime          = "python3.12"
  timeout          = var.timeout
  memory_size      = var.memory_size

  # psycopg2 layer - you'll need to deploy your own or use a public one
  # See: https://github.com/jetbridge/psycopg2-lambda-layer
  layers = var.psycopg2_layer_arn != "" ? [var.psycopg2_layer_arn] : []

  environment {
    variables = {
      ENVIRONMENT = var.environment
      DB_HOST     = var.db_host
      DB_PORT     = tostring(var.db_port)
      DB_NAME     = var.db_name
      DB_USER     = var.db_user
      DB_PASSWORD = var.db_password
    }
  }

  # VPC configuration for private subnet access
  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-crawler"
  }
}

#------------------------------------------------------------------------------
# CloudWatch Log Group
#------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "crawler" {
  name              = "/aws/lambda/${aws_lambda_function.crawler.function_name}"
  retention_in_days = 14

  tags = {
    Name = "${var.project_name}-${var.environment}-crawler-logs"
  }
}

#------------------------------------------------------------------------------
# EventBridge Scheduler
#------------------------------------------------------------------------------
resource "aws_cloudwatch_event_rule" "crawler_schedule" {
  name                = "${var.project_name}-${var.environment}-crawler-schedule"
  description         = "Trigger crawler Lambda on schedule"
  schedule_expression = var.schedule_expression

  tags = {
    Name = "${var.project_name}-${var.environment}-crawler-schedule"
  }
}

resource "aws_cloudwatch_event_target" "crawler" {
  rule      = aws_cloudwatch_event_rule.crawler_schedule.name
  target_id = "crawler-lambda"
  arn       = aws_lambda_function.crawler.arn

  input = jsonencode({
    source    = "eventbridge-schedule"
    timestamp = "$${time}"
  })
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.crawler.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.crawler_schedule.arn
}

#------------------------------------------------------------------------------
# Lambda for Manual Invocation (Optional API Gateway Trigger)
#------------------------------------------------------------------------------
resource "aws_lambda_function_url" "crawler" {
  count = var.enable_function_url ? 1 : 0

  function_name      = aws_lambda_function.crawler.function_name
  authorization_type = "AWS_IAM"

  cors {
    allow_origins = ["https://${var.api_domain}"]
    allow_methods = ["POST"]
    max_age       = 3600
  }
}
