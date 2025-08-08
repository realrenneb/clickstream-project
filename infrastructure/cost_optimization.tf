# cost_optimization.tf - Updated for current architecture

# S3 Intelligent Tiering for Raw Data
resource "aws_s3_bucket_intelligent_tiering_configuration" "raw_data_tiering" {
  bucket = aws_s3_bucket.raw_data.id
  name   = "EntireBucket"

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }
}

# S3 Intelligent Tiering for Processed Data
resource "aws_s3_bucket_intelligent_tiering_configuration" "processed_data_tiering" {
  bucket = aws_s3_bucket.processed_data.id
  name   = "EntireBucket"

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 365  # Processed data kept longer
  }

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 180
  }
}

# EventBridge rule to run Glue job on schedule (instead of continuous)
resource "aws_cloudwatch_event_rule" "glue_schedule" {
  name                = "${var.project_name}-glue-schedule"
  description         = "Trigger Glue ETL job on schedule"
  schedule_expression = var.glue_job_schedule
  
  tags = {
    Name = "${var.project_name}-glue-schedule"
  }
}

resource "aws_cloudwatch_event_target" "glue_target" {
  rule      = aws_cloudwatch_event_rule.glue_schedule.name
  target_id = "GlueJobTarget"
  arn       = "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:job/${aws_glue_job.json_to_parquet.name}"
  role_arn  = aws_iam_role.eventbridge_glue_role.arn
}

# IAM role for EventBridge to trigger Glue
resource "aws_iam_role" "eventbridge_glue_role" {
  name = "${var.project_name}-eventbridge-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "eventbridge_glue_policy" {
  name = "${var.project_name}-eventbridge-glue-policy"
  role = aws_iam_role.eventbridge_glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "glue:StartJobRun"
        ]
        Resource = "arn:aws:glue:${var.aws_region}:${data.aws_caller_identity.current.account_id}:job/${aws_glue_job.json_to_parquet.name}"
      }
    ]
  })
}

# Budget for cost control
resource "aws_budgets_budget" "clickstream_budget" {
  name         = "${var.project_name}-monthly-budget"
  budget_type  = "COST"
  limit_amount = var.monthly_budget_limit
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
  time_period_start = "2025-07-01_00:00"

  cost_filter {
    name   = "TagKey"
    values = ["Project"]
  }

  cost_filter {
    name   = "TagValue"
    values = [var.project_name]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 80
    threshold_type            = "PERCENTAGE"
    notification_type         = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                 = 100
    threshold_type            = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.alert_email]
  }

  depends_on = [aws_sns_topic.pipeline_alerts]
}

# CloudWatch Log Group retention (reduce costs)
resource "aws_cloudwatch_log_group" "lambda_logs_retention" {
  name              = "/aws/lambda/${aws_lambda_function.ingestion.function_name}"
  retention_in_days = 7  # Reduced from default 30 days
}

resource "aws_cloudwatch_log_group" "glue_logs_retention" {
  name              = "/aws-glue/jobs/logs-v2"
  retention_in_days = 14  # Keep Glue logs a bit longer for debugging
}

# Cost anomaly detection - Removed (requires newer AWS provider)
# You can set this up manually in the AWS Console under Cost Management

# Outputs
output "budget_name" {
  description = "Name of the cost budget"
  value = aws_budgets_budget.clickstream_budget.name
}

output "glue_schedule" {
  description = "Glue job schedule expression"
  value = aws_cloudwatch_event_rule.glue_schedule.schedule_expression
}