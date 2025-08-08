#!/bin/bash

echo "🎬 Starting Clickstream Pipeline Demo..."
echo ""

# Check if infrastructure exists
if [ ! -d "infrastructure" ]; then
    echo "❌ Infrastructure directory not found. Run ./deploy.sh first."
    exit 1
fi

cd infrastructure

# Get infrastructure details
echo "📊 Getting infrastructure details..."
API_ENDPOINT=$(terraform output -raw api_endpoint 2>/dev/null)
RAW_BUCKET=$(terraform output -raw raw_bucket_name 2>/dev/null)
PROCESSED_BUCKET=$(terraform output -raw processed_bucket_name 2>/dev/null)
GLUE_JOB=$(terraform output -raw glue_job_name 2>/dev/null)

if [ -z "$API_ENDPOINT" ]; then
    echo "❌ Infrastructure not deployed. Run ./deploy.sh first."
    exit 1
fi

echo "✅ Infrastructure ready:"
echo "  API Endpoint: $API_ENDPOINT"
echo "  Raw Bucket: $RAW_BUCKET"
echo "  Processed Bucket: $PROCESSED_BUCKET"
echo ""

cd ..

echo "🎯 Step 1: Generate sample data (2 minutes, 10 users)..."
echo "Starting data generation in 3 seconds..."
sleep 3

# Generate realistic clickstream data
python advanced_generator.py --endpoint "$API_ENDPOINT" --duration 120 --users 10

echo ""
echo "⏳ Step 2: Waiting for data to flow through Firehose (60 seconds)..."
echo "   Data flows: API → Lambda → Kinesis → Firehose → S3"
sleep 60

echo ""
echo "📥 Step 3: Checking raw data in S3..."
aws s3 ls s3://$RAW_BUCKET/clickstream-data/ --recursive --region eu-west-2

echo ""
echo "🔄 Step 4: Running ETL job (JSON → Parquet)..."
JOB_RUN_ID=$(aws glue start-job-run \
  --job-name $GLUE_JOB \
  --region eu-west-2 \
  --query 'JobRunId' \
  --output text)

echo "   Job Run ID: $JOB_RUN_ID"
echo "   Monitoring job progress..."

# Monitor job progress
while true; do
    JOB_STATE=$(aws glue get-job-run \
      --job-name $GLUE_JOB \
      --run-id $JOB_RUN_ID \
      --region eu-west-2 \
      --query 'JobRun.JobRunState' \
      --output text)
    
    echo "   Job State: $JOB_STATE"
    
    if [ "$JOB_STATE" = "SUCCEEDED" ]; then
        echo "✅ ETL job completed successfully!"
        break
    elif [ "$JOB_STATE" = "FAILED" ] || [ "$JOB_STATE" = "ERROR" ]; then
        echo "❌ ETL job failed!"
        echo "Check logs: aws logs tail /aws-glue/jobs/logs-v2 --region eu-west-2"
        exit 1
    fi
    
    sleep 30
done

echo ""
echo "📤 Step 5: Checking processed data..."
aws s3 ls s3://$PROCESSED_BUCKET/events/ --recursive --region eu-west-2

echo ""
echo "🕷️ Step 6: Running Glue crawler for schema discovery..."
aws glue start-crawler \
  --name clickstream-demo-processed-crawler \
  --region eu-west-2

# Wait for crawler to complete
echo "   Waiting for crawler to complete..."
while true; do
    CRAWLER_STATE=$(aws glue get-crawler \
      --name clickstream-demo-processed-crawler \
      --region eu-west-2 \
      --query 'Crawler.State' \
      --output text)
    
    echo "   Crawler State: $CRAWLER_STATE"
    
    if [ "$CRAWLER_STATE" = "READY" ]; then
        echo "✅ Crawler completed!"
        break
    elif [ "$CRAWLER_STATE" = "STOPPING" ]; then
        echo "⏳ Crawler stopping..."
        sleep 10
    fi
    
    sleep 20
done

echo ""
echo "🎉 Demo Complete! Your full data pipeline is working:"
echo ""
echo "📊 Data Flow Summary:"
echo "1. ✅ Generated realistic clickstream events"
echo "2. ✅ Data streamed through API → Lambda → Kinesis"
echo "3. ✅ Firehose saved raw JSON data to S3"
echo "4. ✅ Glue ETL converted JSON → Parquet"
echo "5. ✅ Crawler discovered schema for Athena"
echo ""
echo "🔍 Next Steps - Query Your Data:"
echo ""
echo "Open Athena and run:"
echo "  USE \`clickstream-demo-processed-db\`;"
echo "  MSCK REPAIR TABLE events;"
echo "  SELECT * FROM events LIMIT 10;"
echo ""
echo "📈 Monitor Your Pipeline:"
echo "  CloudWatch Dashboard: $(terraform output -raw dashboard_url)"
echo ""
echo "🎯 Data Locations:"
echo "  Raw JSON: s3://$RAW_BUCKET/clickstream-data/"
echo "  Processed Parquet: s3://$PROCESSED_BUCKET/events/"
echo ""