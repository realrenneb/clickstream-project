#!/bin/bash

echo "🗑️  Starting comprehensive infrastructure destruction..."
echo "⚠️  This will delete ALL AWS resources and data!"
echo ""

# Confirm destruction
read -p "Are you sure you want to destroy everything? (type 'yes' to confirm): " confirm
if [ "$confirm" != "yes" ]; then
    echo "❌ Destruction cancelled"
    exit 1
fi

cd infrastructure

echo "📦 Getting bucket names for data cleanup..."

# Get bucket names before destroying (if state exists)
RAW_BUCKET=$(terraform output -raw raw_bucket_name 2>/dev/null || echo "")
PROCESSED_BUCKET=$(terraform output -raw processed_bucket_name 2>/dev/null || echo "")
ATHENA_BUCKET=$(terraform output -raw athena_results_bucket 2>/dev/null || echo "")

echo "🧹 Cleaning up S3 buckets..."

# Empty buckets by name (in case state is broken)
for bucket in "clickstream-demo-raw-265974217211" "clickstream-demo-processed-265974217211" "clickstream-demo-athena-results-265974217211"; do
    echo "  Checking bucket: $bucket"
    if aws s3api head-bucket --bucket "$bucket" --region eu-west-2 2>/dev/null; then
        echo "    Emptying $bucket"
        aws s3 rm s3://$bucket --recursive --region eu-west-2 2>/dev/null || true
    fi
done

# Also clean using terraform outputs if available
if [ ! -z "$RAW_BUCKET" ]; then
    echo "  Emptying raw bucket: $RAW_BUCKET"
    aws s3 rm s3://$RAW_BUCKET --recursive --region eu-west-2 2>/dev/null || true
fi

if [ ! -z "$PROCESSED_BUCKET" ]; then
    echo "  Emptying processed bucket: $PROCESSED_BUCKET"
    aws s3 rm s3://$PROCESSED_BUCKET --recursive --region eu-west-2 2>/dev/null || true
fi

if [ ! -z "$ATHENA_BUCKET" ]; then
    echo "  Emptying Athena results bucket: $ATHENA_BUCKET"
    aws s3 rm s3://$ATHENA_BUCKET --recursive --region eu-west-2 2>/dev/null || true
fi

echo "🕷️ Cleaning up Glue resources..."

# Delete crawlers
for crawler in "clickstream-demo-processed-crawler" "clickstream-processed-crawler"; do
    echo "  Checking crawler: $crawler"
    if aws glue get-crawler --name "$crawler" --region eu-west-2 >/dev/null 2>&1; then
        echo "    Stopping and deleting crawler: $crawler"
        aws glue stop-crawler --name "$crawler" --region eu-west-2 2>/dev/null || true
        sleep 5
        aws glue delete-crawler --name "$crawler" --region eu-west-2 2>/dev/null || true
    fi
done

echo "🔥 Attempting Terraform destroy..."

# Create temporary lambda.zip if needed for destroy
if [ ! -f "lambda.zip" ]; then
    echo "  Creating temporary lambda.zip for destroy process..."
    if [ -f "lambda_function.py" ]; then
        zip -j lambda.zip lambda_function.py >/dev/null 2>&1
    else
        echo "print('dummy')" > temp_lambda.py
        zip -j lambda.zip temp_lambda.py >/dev/null 2>&1
        rm -f temp_lambda.py
    fi
fi

# Try Terraform destroy first
if terraform destroy -auto-approve 2>/dev/null; then
    echo "✅ Terraform destroy successful"
else
    echo "⚠️  Terraform destroy failed, performing manual cleanup..."
    
    echo "🧼 Manual resource cleanup..."
    
    # Delete ALL IAM roles with 'clickstream' in the name
    echo "  Cleaning ALL clickstream IAM roles..."
    
    aws iam list-roles --query 'Roles[?contains(RoleName, `clickstream`)].RoleName' --output text --region eu-west-2 | while read role_name; do
        if [ ! -z "$role_name" ]; then
            echo "    Force deleting role: $role_name"
            
            # Detach ALL managed policies
            aws iam list-attached-role-policies --role-name "$role_name" --region eu-west-2 --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null | while read policy_arn; do
                if [ ! -z "$policy_arn" ]; then
                    echo "      Detaching managed policy: $policy_arn"
                    aws iam detach-role-policy --role-name "$role_name" --policy-arn "$policy_arn" --region eu-west-2 2>/dev/null || true
                fi
            done
            
            # Delete ALL inline policies
            aws iam list-role-policies --role-name "$role_name" --region eu-west-2 --query 'PolicyNames' --output text 2>/dev/null | while read policy_name; do
                if [ ! -z "$policy_name" ]; then
                    echo "      Deleting inline policy: $policy_name"
                    aws iam delete-role-policy --role-name "$role_name" --policy-name "$policy_name" --region eu-west-2 2>/dev/null || true
                fi
            done
            
            # Wait a moment for AWS to process
            sleep 2
            
            # Delete the role
            echo "      Deleting role: $role_name"
            aws iam delete-role --role-name "$role_name" --region eu-west-2 2>/dev/null || true
        fi
    done
    
    echo "  Cleaning other resources..."
    
    # Delete Kinesis stream
    aws kinesis delete-stream --stream-name clickstream-demo-stream --region eu-west-2 2>/dev/null || true
    
    # Delete Lambda function
    aws lambda delete-function --function-name clickstream-demo-ingestion --region eu-west-2 2>/dev/null || true
    
    # Delete CloudWatch log groups
    aws logs delete-log-group --log-group-name /aws/lambda/clickstream-demo-ingestion --region eu-west-2 2>/dev/null || true
    aws logs delete-log-group --log-group-name /aws-glue/jobs/logs-v2 --region eu-west-2 2>/dev/null || true
    
    # Delete Glue databases and jobs
    aws glue delete-job --job-name clickstream-demo-json-to-parquet --region eu-west-2 2>/dev/null || true
    aws glue delete-database --name clickstream-demo_db --region eu-west-2 2>/dev/null || true
    aws glue delete-database --name clickstream-demo-processed-db --region eu-west-2 2>/dev/null || true
    
    # Delete Firehose
    aws firehose delete-delivery-stream --delivery-stream-name clickstream-demo-firehose --region eu-west-2 2>/dev/null || true
    
    # Delete API Gateway (harder to target by name, skip for now)
    echo "  Note: API Gateway resources may need manual cleanup in console"
    
    # Delete S3 buckets (should be empty now)
    for bucket in "clickstream-demo-raw-265974217211" "clickstream-demo-processed-265974217211" "clickstream-demo-athena-results-265974217211"; do
        aws s3api delete-bucket --bucket "$bucket" --region eu-west-2 2>/dev/null || true
    done
fi

echo "🧼 Cleaning up local files..."

# Clean up local files
rm -f ../glue_scripts/json_to_parquet.py 2>/dev/null || true
rm -rf ../glue_scripts 2>/dev/null || true
rm -f lambda.zip 2>/dev/null || true
rm -rf lambda_Current current_lambda 2>/dev/null || true
rm -f *.zip 2>/dev/null || true

# Clean up Terraform state
read -p "Do you want to delete Terraform state files for a completely fresh start? (y/n): " delete_state
if [ "$delete_state" = "y" ]; then
    echo "  Removing Terraform state files..."
    rm -f terraform.tfstate*
    rm -f .terraform.lock.hcl
    rm -rf .terraform/
fi

echo ""
echo "✅ Comprehensive destruction complete!"
echo "🚀 Ready for fresh deployment!"
echo ""
echo "Next steps:"
echo "1. Run: ./deploy.sh"
echo "2. Run: ./run_demo.sh"