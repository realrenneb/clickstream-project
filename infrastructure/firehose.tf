# S3 bucket for Athena query results
resource "aws_s3_bucket" "athena_results" {
  bucket = "${var.project_name}-athena-results-${data.aws_caller_identity.current.account_id}"
  
  tags = {
    Name        = "${var.project_name}-athena-results"
    Environment = "demo"
  }
}

# S3 bucket public access block for Athena results
resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# IAM role for Kinesis Firehose
resource "aws_iam_role" "firehose_role" {
  name = "${var.project_name}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      }
    ]
  })
}

# IAM policy for Firehose
resource "aws_iam_role_policy" "firehose_policy" {
  name = "${var.project_name}-firehose-policy"
  role = aws_iam_role.firehose_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "kinesis:DescribeStream",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:ListShards"
        ]
        Resource = aws_kinesis_stream.clickstream.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# Kinesis Firehose Delivery Stream - Simple Version (no format conversion)
resource "aws_kinesis_firehose_delivery_stream" "clickstream_firehose" {
  name        = "${var.project_name}-firehose"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.clickstream.arn
    role_arn          = aws_iam_role.firehose_role.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose_role.arn
    bucket_arn = aws_s3_bucket.raw_data.arn

    # Partitioning for Athena
    prefix              = "clickstream-data/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "clickstream-errors/"

    # Buffering configuration
    buffering_interval = 60  # 1 minute
    buffering_size    = 5   # 5 MB

    # Compression for cost savings
    compression_format = "GZIP"
  }

  depends_on = [
    aws_iam_role_policy.firehose_policy
  ]
}

# Glue Database
resource "aws_glue_catalog_database" "clickstream_db" {
  name = "${var.project_name}_db"
  
  description = "Database for clickstream analytics"
}

# Glue Table for JSON data
resource "aws_glue_catalog_table" "clickstream_events" {
  name          = "events"
  database_name = aws_glue_catalog_database.clickstream_db.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "projection.enabled"              = "true"
    "projection.year.type"            = "integer"
    "projection.year.range"           = "2024,2025"
    "projection.month.type"           = "integer"
    "projection.month.range"          = "1,12"
    "projection.month.digits"         = "2"
    "projection.day.type"             = "integer"
    "projection.day.range"            = "1,31"
    "projection.day.digits"           = "2"
    "projection.hour.type"            = "integer"
    "projection.hour.range"           = "0,23"
    "projection.hour.digits"          = "2"
    "storage.location.template"       = "s3://${aws_s3_bucket.raw_data.id}/clickstream-data/year=$${year}/month=$${month}/day=$${day}/hour=$${hour}"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.raw_data.id}/clickstream-data/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
    }

    columns {
      name = "event_id"
      type = "string"
    }
    columns {
      name = "event_type"
      type = "string"
    }
    columns {
      name = "user_id"
      type = "string"
    }
    columns {
      name = "session_id"
      type = "string"
    }
    columns {
      name = "timestamp"
      type = "string"
    }
    columns {
      name = "processed_at"
      type = "string"
    }
    columns {
      name = "lambda_request_id"
      type = "string"
    }
    columns {
      name = "device_type"
      type = "string"
    }
    columns {
      name = "browser"
      type = "string"
    }
    columns {
      name = "country"
      type = "string"
    }
    columns {
      name = "properties"
      type = "map<string,string>"
    }
  }

  partition_keys {
    name = "year"
    type = "int"
  }
  partition_keys {
    name = "month"
    type = "int"
  }
  partition_keys {
    name = "day"
    type = "int"
  }
  partition_keys {
    name = "hour"
    type = "int"
  }
}

# Outputs
output "firehose_name" {
  description = "Kinesis Firehose delivery stream name"
  value       = aws_kinesis_firehose_delivery_stream.clickstream_firehose.name
}

output "glue_database" {
  description = "Glue database name"
  value       = aws_glue_catalog_database.clickstream_db.name
}

output "athena_results_bucket" {
  description = "S3 bucket for Athena query results"
  value       = aws_s3_bucket.athena_results.id
}