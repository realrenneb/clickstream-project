# processing_layer.tf - Complete updated version with FIXED IAM policy

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

    # Apply to all objects in the bucket
    filter {
      prefix = ""
    }

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

# FIXED Glue policy - Now includes GetObject permission on processed bucket
resource "aws_iam_role_policy" "glue_policy" {
  name = "${var.project_name}-glue-policy"
  role = aws_iam_role.glue_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Read access to RAW bucket (source data)
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
      # FULL access to PROCESSED bucket (script + output data) - FIXED!
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",     # <- THIS WAS MISSING! Needed for script access
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket"     # <- THIS WAS MISSING! Needed for listing
        ]
        Resource = [
          aws_s3_bucket.processed_data.arn,
          "${aws_s3_bucket.processed_data.arn}/*"
        ]
      },
      # Glue catalog access
      {
        Effect = "Allow"
        Action = [
          "glue:*"
        ]
        Resource = "*"
      },
      # CloudWatch logs
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

# Glue Database for processed data
resource "aws_glue_catalog_database" "processed_db" {
  name        = "${var.project_name}-processed-db"
  description = "Database for processed clickstream data"
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
    "--enable-job-insights"              = "true"
    "--enable-metrics"                   = "true"
    "--enable-continuous-cloudwatch-log" = "true"
    "--job-language"                     = "python"
    "--SOURCE_BUCKET"                    = aws_s3_bucket.raw_data.id
    "--TARGET_BUCKET"                    = aws_s3_bucket.processed_data.id
    "--DATABASE_NAME"                    = aws_glue_catalog_database.processed_db.name
  }

  max_capacity = 2.0  # Minimum for cost savings
  timeout      = 60   # 1 hour timeout
}

# Glue Table for processed Parquet data
resource "aws_glue_catalog_table" "events_processed" {
  name          = "events_processed"
  database_name = aws_glue_catalog_database.processed_db.name
  description   = "Processed clickstream events in Parquet format"

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "classification"                   = "parquet"
    "compressionType"                 = "none"
    "typeOfData"                      = "file"
    "has_encrypted_data"              = "false"
    "parquet.compress"                = "SNAPPY"
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
      type = "string"
    }

    columns {
      name = "processed_at"
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

    columns {
      name = "lambda_request_id"
      type = "string"
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

# Glue Crawler for automatic schema detection
resource "aws_glue_crawler" "processed_data_crawler" {
  database_name = aws_glue_catalog_database.processed_db.name
  name          = "${var.project_name}-processed-crawler"
  role          = aws_iam_role.glue_role.arn

  s3_target {
    path = "s3://${aws_s3_bucket.processed_data.id}/events/"
  }

  # Run the crawler automatically after each ETL job
  configuration = jsonencode({
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
    }
    Version = 1.0
  })

  tags = {
    Name        = "${var.project_name}-processed-crawler"
    Environment = "demo"
  }
}

# Outputs
output "processed_bucket_name" {
  description = "Name of the processed data bucket"
  value       = aws_s3_bucket.processed_data.id
}

output "processed_database_name" {
  description = "Name of the processed data Glue database"
  value       = aws_glue_catalog_database.processed_db.name
}

output "glue_job_name" {
  description = "Glue ETL job name"
  value       = aws_glue_job.json_to_parquet.name
}