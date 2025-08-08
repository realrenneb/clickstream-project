#!/bin/bash

echo "🚀 Starting fresh clickstream pipeline deployment..."
echo ""

# Check if we're in the right directory
if [ ! -d "infrastructure" ]; then
    echo "❌ Please run this script from the project root directory"
    exit 1
fi

cd infrastructure

echo "📦 Creating Lambda deployment package..."
# Create the Lambda zip file that Terraform expects
zip -j lambda.zip lambda_function.py

echo "🔧 Initializing Terraform..."
terraform init

echo "📋 Planning deployment..."
terraform plan

echo ""
read -p "Proceed with deployment? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "❌ Deployment cancelled"
    exit 1
fi

echo "🏗️  Deploying infrastructure..."
if terraform apply -auto-approve; then
    echo ""
    echo "📝 Getting deployment outputs..."
    API_ENDPOINT=$(terraform output -raw api_endpoint 2>/dev/null || echo "FAILED")
    RAW_BUCKET=$(terraform output -raw raw_bucket_name 2>/dev/null || echo "FAILED")
    PROCESSED_BUCKET=$(terraform output -raw processed_bucket_name 2>/dev/null || echo "FAILED")
    GLUE_JOB=$(terraform output -raw glue_job_name 2>/dev/null || echo "FAILED")

    if [ "$API_ENDPOINT" = "FAILED" ]; then
        echo "❌ Deployment failed! No outputs available."
        echo "Check Terraform errors above."
        exit 1
    fi

    echo "✅ Infrastructure deployed successfully!"
    echo ""
    echo "📊 Deployment Summary:"
    echo "  API Endpoint: $API_ENDPOINT"
    echo "  Raw Bucket: $RAW_BUCKET"
    echo "  Processed Bucket: $PROCESSED_BUCKET"
    echo "  Glue Job: $GLUE_JOB"
else
    echo "❌ Terraform deployment failed!"
    exit 1
fi
echo ""

echo "📄 Creating Glue ETL script..."
cd ..
mkdir -p glue_scripts

# Create the robust Glue script
cat > glue_scripts/json_to_parquet.py << 'EOF'
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql.functions import *
from pyspark.sql.types import *

# Get job parameters
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'SOURCE_BUCKET', 'TARGET_BUCKET', 'DATABASE_NAME'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Set up paths
source_path = f"s3://{args['SOURCE_BUCKET']}/clickstream-data/year=*/month=*/day=*/hour=*/*.gz"
target_path = f"s3://{args['TARGET_BUCKET']}/events/"

print(f"Reading from: {source_path}")
print(f"Writing to: {target_path}")

try:
    # Read JSON files
    df = spark.read.option("multiLine", "false").json(source_path)
    
    print(f"Total records read: {df.count()}")
    
    # Filter out records with null essential fields
    df_clean = df.filter(
        col("processed_at").isNotNull() | 
        col("test_time").isNotNull()
    )
    
    print(f"Records after filtering nulls: {df_clean.count()}")
    
    # Add partitioning columns - keep timestamps as strings
    if 'processed_at' in df_clean.columns:
        df_with_partitions = df_clean.withColumn(
            "processed_at_clean", 
            regexp_replace(col("processed_at"), r"\.\d+$", "")
        ).withColumn(
            "timestamp_parsed", 
            to_timestamp(col("processed_at_clean"), "yyyy-MM-dd'T'HH:mm:ss")
        )
    elif 'test_time' in df_clean.columns:
        df_with_partitions = df_clean.withColumn(
            "timestamp_parsed", 
            to_timestamp(col("test_time"), "yyyy-MM-dd'T'HH:mm:ss'Z'")
        )
    else:
        print("No timestamp found, using current time")
        df_with_partitions = df_clean.withColumn("timestamp_parsed", current_timestamp())
    
    # Extract partition columns
    df_with_partitions = df_with_partitions \
        .withColumn("year", year("timestamp_parsed")) \
        .withColumn("month", month("timestamp_parsed")) \
        .withColumn("day", dayofmonth("timestamp_parsed"))
    
    # Filter out any remaining null partitions
    df_final = df_with_partitions.filter(
        col("year").isNotNull() & 
        col("month").isNotNull() & 
        col("day").isNotNull()
    )
    
    df_final = df_final.drop("timestamp_parsed", "processed_at_clean")
    
    final_count = df_final.count()
    print(f"Final records to write: {final_count}")
    
    if final_count > 0:
        print("Final schema:")
        df_final.printSchema()
        
        print("Partition distribution:")
        df_final.groupBy("year", "month", "day").count().show()
        
        # Write as Parquet with partitioning
        df_final.write \
            .mode("overwrite") \
            .partitionBy("year", "month", "day") \
            .option("compression", "snappy") \
            .parquet(target_path)
        
        print("ETL job completed successfully")
    else:
        print("No data to write after filtering")
        
except Exception as e:
    print(f"ETL job failed with error: {str(e)}")
    import traceback
    traceback.print_exc()
    raise e

job.commit()
EOF

echo "📤 Uploading Glue script to S3..."
aws s3 cp glue_scripts/json_to_parquet.py s3://$PROCESSED_BUCKET/scripts/json_to_parquet.py --region eu-west-2

echo ""
echo "🎉 Deployment complete!"
echo ""
echo "🎯 Next steps:"
echo "1. Run: ./run_demo.sh"
echo "2. Monitor in AWS Console:"
echo "   - CloudWatch Dashboard: $(terraform output -raw dashboard_url)"
echo "   - S3 Buckets: Raw data will flow to $RAW_BUCKET"
echo "   - Processed data will be in: $PROCESSED_BUCKET"
echo ""