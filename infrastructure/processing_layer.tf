# S3 Bucket for Processed Data (Parquet)
resource "aws_s3_bucket" "processed_data" {
  bucket = "${var.project_name}-processed-${data.aws_caller_identity.current.account_id}"
  
  tags = {
    Name        = "${var.project_name}-processed-data"
    Environment = "demo"
    Layer       = "processed"
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle policy to move old data to cheaper storage
resource "aws_s3_bucket_lifecycle_configuration" "processed_data" {
  bucket = aws_s3_bucket.processed_data.id

  rule {
    id     = "transition-old-data"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }
  }
}

# IAM Role for Glue
resource "aws_iam_role" "glue_role" {
  name = "${var.project_name}-glue-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
      }
    ]
  })
}

# Glue policy
resource "aws_iam_role_policy" "glue_policy" {
  name = "${var.project_name}-glue-policy"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.raw_data.arn,
          "${aws_s3_bucket.raw_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:DeleteObject"
        ]
        Resource = [
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "glue:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# Attach AWS managed policy for Glue
resource "aws_iam_role_policy_attachment" "glue_service_role" {
  role       = aws_iam_role.glue_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

# Glue Job for ETL
resource "aws_glue_job" "json_to_parquet" {
  name         = "${var.project_name}-json-to-parquet"
  role_arn     = aws_iam_role.glue_role.arn
  glue_version = "4.0"
  
  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.processed_data.id}/scripts/json_to_parquet.py"
    python_version  = "3"
  }

  default_arguments = {
    "--enable-job-insights"     = "true"
    "--enable-metrics"          = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--job-language"            = "python"
    "--SOURCE_BUCKET"           = aws_s3_bucket.raw_data.id
    "--TARGET_BUCKET"           = aws_s3_bucket.processed_data.id
    "--DATABASE_NAME"           = aws_glue_catalog_database.clickstream_db.name
  }

  max_capacity = 2.0  # Minimum for cost savings
  timeout      = 60   # 1 hour timeout

  execution_property {
    max_concurrent_runs = 1
  }
}

# Create table for processed data
resource "aws_glue_catalog_table" "events_processed" {
  name          = "events_processed"
  database_name = aws_glue_catalog_database.clickstream_db.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "projection.enabled"        = "true"
    "projection.year.type"      = "integer"
    "projection.year.range"     = "2024,2025"
    "projection.month.type"     = "integer"
    "projection.month.range"    = "1,12"
    "projection.month.digits"   = "2"
    "projection.day.type"       = "integer"
    "projection.day.range"      = "1,31"
    "projection.day.digits"     = "2"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.processed_data.id}/events/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
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
      type = "timestamp"
    }
    columns {
      name = "processed_at"
      type = "timestamp"
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
}

# Outputs
output "processed_bucket_name" {
  description = "S3 bucket for processed data"
  value       = aws_s3_bucket.processed_data.id
}

output "glue_job_name" {
  description = "Glue ETL job name"
  value       = aws_glue_job.json_to_parquet.name
}