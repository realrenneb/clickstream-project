# monitoring_enhanced.tf - Updated with working metrics

# SNS Topic for Alerts
resource "aws_sns_topic" "pipeline_alerts" {
  name = "${var.project_name}-pipeline-alerts"
  
  tags = {
    Name = "${var.project_name}-alerts"
    Environment = "demo"
  }
}

# SNS Topic Subscription (update with your email)
resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.pipeline_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Enhanced CloudWatch Dashboard with WORKING metrics
resource "aws_cloudwatch_dashboard" "enhanced_pipeline" {
  dashboard_name = "${var.project_name}-enhanced-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # Row 1: API Gateway and Lambda metrics (FIXED)
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/ApiGateway", "DataProcessed", "ApiId", "td08v6xi88"],
            [".", "4xx", ".", "."],
            [".", "Latency", ".", ".", { yAxis = "right" }]
          ]
          view = "timeSeries"
          stacked = false
          region = var.aws_region
          title = "API Gateway Metrics (Working)"
          period = 300
          stat = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.ingestion.function_name],
            [".", "Errors", ".", "."],
            [".", "Duration", ".", ".", { yAxis = "right" }],
            [".", "Throttles", ".", "."]
          ]
          view = "timeSeries"
          stacked = false
          region = var.aws_region
          title = "Lambda Performance"
          period = 300
          stat = "Sum"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          metrics = [
            ["AWS/Kinesis", "IncomingRecords", "StreamName", aws_kinesis_stream.clickstream.name],
            [".", "IncomingBytes", ".", ".", { yAxis = "right" }]
          ]
          view = "timeSeries"
          stacked = false
          region = var.aws_region
          title = "Kinesis Throughput"
          period = 300
          stat = "Sum"
        }
      },
      
      # Row 2: S3 Data Flow and Glue Job Status
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/S3", "NumberOfObjects", "BucketName", aws_s3_bucket.raw_data.id, "StorageType", "AllStorageTypes"],
            [".", "BucketSizeBytes", ".", ".", ".", "StandardStorage", { yAxis = "right" }]
          ]
          view = "timeSeries"
          stacked = false
          region = var.aws_region
          title = "S3 Raw Data Storage (Proves Firehose Works)"
          period = 3600
          stat = "Average"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Glue", "glue.driver.aggregate.bytesRead", "JobName", aws_glue_job.json_to_parquet.name, "Type", "gauge"],
            [".", "glue.driver.aggregate.recordsRead", ".", ".", ".", ".", { yAxis = "right" }],
            [".", "glue.driver.jvm.heap.usage", ".", ".", ".", ".", { yAxis = "right" }]
          ]
          view = "timeSeries"
          stacked = false
          region = var.aws_region
          title = "Glue ETL Processing (When Running)"
          period = 300
          stat = "Average"
        }
      },
      
      # Row 3: Processed Data and Pipeline Health
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/S3", "NumberOfObjects", "BucketName", aws_s3_bucket.processed_data.id, "StorageType", "AllStorageTypes"],
            [".", "BucketSizeBytes", ".", ".", ".", "StandardStorage", { yAxis = "right" }]
          ]
          view = "timeSeries"
          stacked = false
          region = var.aws_region
          title = "S3 Processed Data (Parquet Files)"
          period = 3600
          stat = "Average"
        }
      },
      {
        type   = "log"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          query = "SOURCE '/aws/lambda/${aws_lambda_function.ingestion.function_name}'\n| fields @timestamp, @message\n| filter @message like /ERROR/ or @message like /Failed/\n| sort @timestamp desc\n| limit 20"
          region = var.aws_region
          title = "Recent Pipeline Errors"
        }
      },
      
      # Row 4: Cost and Summary Metrics
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Billing", "EstimatedCharges", "Currency", "USD", { stat = "Maximum", period = 86400 }]
          ]
          view = "singleValue"
          region = "us-east-1"
          title = "Estimated Daily Charges"
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 18
        width  = 12
        height = 6
        properties = {
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", aws_lambda_function.ingestion.function_name, { stat = "Sum", label = "Total Lambda Invocations" }],
            ["AWS/Kinesis", "IncomingRecords", "StreamName", aws_kinesis_stream.clickstream.name, { stat = "Sum", label = "Total Kinesis Records" }]
          ]
          view = "singleValue"
          region = var.aws_region
          title = "Pipeline Summary (Last 24h)"
          period = 86400
        }
      }
    ]
  })
}

# Lambda Error Alarm
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = "300"
  statistic           = "Sum"
  threshold           = "5"
  alarm_description   = "Lambda function errors"
  alarm_actions       = [aws_sns_topic.pipeline_alerts.arn]

  dimensions = {
    FunctionName = aws_lambda_function.ingestion.function_name
  }

  tags = {
    Name = "${var.project_name}-lambda-errors"
  }
}

# API Gateway Error Alarm (FIXED)
resource "aws_cloudwatch_metric_alarm" "api_gateway_errors" {
  alarm_name          = "${var.project_name}-api-4xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "4xx"
  namespace           = "AWS/ApiGateway"
  period              = "300"
  statistic           = "Sum"
  threshold           = "10"
  alarm_description   = "API Gateway 4XX errors"
  alarm_actions       = [aws_sns_topic.pipeline_alerts.arn]

  dimensions = {
    ApiId = "td08v6xi88"
  }

  tags = {
    Name = "${var.project_name}-api-errors"
  }
}

# Kinesis Consumer Lag Alarm
resource "aws_cloudwatch_metric_alarm" "kinesis_lag" {
  alarm_name          = "${var.project_name}-kinesis-lag"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "IncomingRecords"
  namespace           = "AWS/Kinesis"
  period              = "300"
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Kinesis stream has no incoming records for 15 minutes"
  alarm_actions       = [aws_sns_topic.pipeline_alerts.arn]
  treat_missing_data  = "breaching"

  dimensions = {
    StreamName = aws_kinesis_stream.clickstream.name
  }

  tags = {
    Name = "${var.project_name}-kinesis-lag"
  }
}

# Glue Job Success/Failure Tracking (More Reliable)
resource "aws_cloudwatch_metric_alarm" "glue_job_monitoring" {
  alarm_name          = "${var.project_name}-glue-job-health"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "glue.driver.aggregate.recordsRead"
  namespace           = "AWS/Glue"
  period              = "3600"  # Check every hour
  statistic           = "Sum"
  threshold           = "1"
  alarm_description   = "Glue job not processing data when expected"
  alarm_actions       = [aws_sns_topic.pipeline_alerts.arn]
  treat_missing_data  = "notBreaching"  # Don't alarm when job isn't running

  dimensions = {
    JobName = aws_glue_job.json_to_parquet.name
    Type    = "gauge"
  }

  tags = {
    Name = "${var.project_name}-glue-health"
  }
}

# Outputs
output "enhanced_dashboard_url" {
  description = "Enhanced CloudWatch dashboard URL"
  value = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${aws_cloudwatch_dashboard.enhanced_pipeline.dashboard_name}"
}

output "sns_topic_arn" {
  description = "SNS topic ARN for alerts"
  value = aws_sns_topic.pipeline_alerts.arn
}