#!/bin/bash

echo "🚀 Deploying Day 6: Monitoring, Alerting & Cost Optimization"
echo ""

# Check if we're in the right directory
if [ ! -d "infrastructure" ]; then
    echo "❌ Please run this script from the project root directory"
    exit 1
fi

cd infrastructure

# Update variables for Day 6
echo "📝 Setting up Day 6 variables..."

# Check if variables.tf has the new variables, if not add them
if ! grep -q "alert_email" variables.tf; then
    echo ""
    echo "# Day 6 Variables" >> variables.tf
    echo 'variable "alert_email" {' >> variables.tf
    echo '  description = "Email for pipeline alerts"' >> variables.tf
    echo '  type        = string' >> variables.tf
    echo '  default     = "your-email@example.com"  # UPDATE THIS!' >> variables.tf
    echo '}' >> variables.tf
    echo "" >> variables.tf
    
    echo 'variable "glue_job_schedule" {' >> variables.tf
    echo '  description = "Schedule for Glue ETL job"' >> variables.tf
    echo '  type        = string' >> variables.tf
    echo '  default     = "rate(2 hours)"' >> variables.tf
    echo '}' >> variables.tf
    echo "" >> variables.tf
    
    echo 'variable "monthly_budget_limit" {' >> variables.tf
    echo '  description = "Monthly budget limit in USD"' >> variables.tf
    echo '  type        = string' >> variables.tf
    echo '  default     = "50"' >> variables.tf
    echo '}' >> variables.tf
fi

echo "✅ Variables updated"

# Create the data quality Lambda function package
echo "📦 Creating data quality Lambda package..."
cd ..
mkdir -p lambda_functions

# Create data quality Lambda (save the Python code from above artifact)
echo "💾 Creating lambda_data_quality.py file..."
echo "⚠️  Please save the data quality Lambda code to lambda_functions/lambda_data_quality.py"
echo "   (Use the code from the artifact above)"

# Create the zip package for data quality Lambda
if [ -f "lambda_functions/lambda_data_quality.py" ]; then
    cd lambda_functions
    zip -r data_quality_lambda.zip lambda_data_quality.py
    mv data_quality_lambda.zip ../infrastructure/
    cd ..
    echo "✅ Data quality Lambda package created"
else
    echo "⚠️  lambda_data_quality.py not found - skipping data quality Lambda"
fi

cd infrastructure

echo "🏗️  Planning Terraform deployment..."
terraform plan

echo ""
read -p "Proceed with Day 6 deployment? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "❌ Deployment cancelled"
    exit 1
fi

echo "🚀 Deploying Day 6 infrastructure..."
terraform apply -auto-approve

echo ""
echo "📊 Getting deployment outputs..."

# Get outputs
ENHANCED_DASHBOARD=$(terraform output -raw enhanced_dashboard_url 2>/dev/null || echo "Not available")
SNS_TOPIC=$(terraform output -raw sns_topic_arn 2>/dev/null || echo "Not available")
BUDGET_NAME=$(terraform output -raw budget_name 2>/dev/null || echo "Not available")

echo "✅ Day 6 deployment complete!"
echo ""
echo "📊 Day 6 Summary:"
echo "  Enhanced Dashboard: $ENHANCED_DASHBOARD"
echo "  SNS Topic: $SNS_TOPIC"
echo "  Budget: $BUDGET_NAME"
echo ""

echo "🔧 Day 6 Features Added:"
echo "  ✅ Enhanced CloudWatch Dashboard"
echo "  ✅ Automated Alerts (Lambda, API, Kinesis, Glue)"
echo "  ✅ Cost Budget with Alerts"
echo "  ✅ S3 Intelligent Tiering"
echo "  ✅ Scheduled Glue Jobs (every 2 hours)"
echo "  ✅ Data Quality Monitoring (if Lambda created)"
echo "  ✅ Cost Anomaly Detection"
echo ""

echo "⚡ Next Steps:"
echo "1. 📧 Update your email in variables.tf (alert_email)"
echo "2. 📧 Confirm SNS subscription in your email"
echo "3. 📊 Visit enhanced dashboard: $ENHANCED_DASHBOARD"
echo "4. 🧪 Test alerts by generating some data:"
echo "   python advanced_generator.py --endpoint \"$(terraform output -raw api_endpoint)\" --duration 60 --users 5"
echo ""

echo "💰 Cost Optimization Active:"
echo "  📉 S3 data will auto-tier to cheaper storage"
echo "  📅 Glue jobs run on schedule instead of continuous"
echo "  💸 Budget alerts at 80% and 100% of $50/month"
echo "  🔍 Cost anomaly detection enabled"
echo ""

echo "🎉 Your pipeline is now production-ready with monitoring and cost controls!"