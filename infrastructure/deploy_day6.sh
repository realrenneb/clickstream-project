#!/bin/bash

echo "🚀 Deploying Day 6: Monitoring, Alerting & Cost Optimization"
echo ""

# Check if we're in the right directory
if [ ! -d "infrastructure" ]; then
    echo "❌ Please run this script from the project root directory"
    exit 1
fi

cd infrastructure

# Check for duplicate variables and clean them up
echo "🧹 Checking for duplicate variables..."

# Remove variables from monitoring_enhanced.tf if they exist
if grep -q "variable \"alert_email\"" monitoring_enhanced.tf; then
    echo "  Removing duplicate variables from monitoring_enhanced.tf..."
    sed -i '/^variable "alert_email"/,/^}$/d' monitoring_enhanced.tf
    sed -i '/^# Variables$/,$d' monitoring_enhanced.tf
fi

# Remove variables from cost_optimization.tf if they exist
if grep -q "variable \"glue_job_schedule\"" cost_optimization.tf; then
    echo "  Removing duplicate variables from cost_optimization.tf..."
    sed -i '/^variable "glue_job_schedule"/,/^}$/d' cost_optimization.tf
    sed -i '/^variable "monthly_budget_limit"/,/^}$/d' cost_optimization.tf
    sed -i '/^# Variables for cost optimization$/d' cost_optimization.tf
fi

# Check if we have variables.tf, if not create it or add to main.tf
if [ ! -f "variables.tf" ]; then
    echo "📝 Creating variables.tf..."
    cat > variables.tf << 'EOF'
# Core variables
variable "aws_region" {
  description = "AWS region"
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Project name"
  default     = "clickstream-demo"
}

# Day 6 Variables for Monitoring and Cost Optimization
variable "alert_email" {
  description = "Email for pipeline alerts"
  type        = string
  default     = "your-email@example.com"  # UPDATE THIS!
}

variable "glue_job_schedule" {
  description = "Schedule for Glue ETL job"
  type        = string
  default     = "rate(2 hours)"
}

variable "monthly_budget_limit" {
  description = "Monthly budget limit in USD"
  type        = string
  default     = "50"
}
EOF
else
    echo "📝 variables.tf already exists, checking for missing variables..."
    
    # Add missing variables if they don't exist
    if ! grep -q "alert_email" variables.tf; then
        echo "" >> variables.tf
        echo "# Day 6 Variables" >> variables.tf
        echo 'variable "alert_email" {' >> variables.tf
        echo '  description = "Email for pipeline alerts"' >> variables.tf
        echo '  type        = string' >> variables.tf
        echo '  default     = "your-email@example.com"  # UPDATE THIS!' >> variables.tf
        echo '}' >> variables.tf
    fi
    
    if ! grep -q "glue_job_schedule" variables.tf; then
        echo "" >> variables.tf
        echo 'variable "glue_job_schedule" {' >> variables.tf
        echo '  description = "Schedule for Glue ETL job"' >> variables.tf
        echo '  type        = string' >> variables.tf
        echo '  default     = "rate(2 hours)"' >> variables.tf
        echo '}' >> variables.tf
    fi
    
    if ! grep -q "monthly_budget_limit" variables.tf; then
        echo "" >> variables.tf
        echo 'variable "monthly_budget_limit" {' >> variables.tf
        echo '  description = "Monthly budget limit in USD"' >> variables.tf
        echo '  type        = string' >> variables.tf
        echo '  default     = "50"' >> variables.tf
        echo '}' >> variables.tf
    fi
fi

echo "✅ Variables configured"

# Prompt user to update email if it's still the default
if grep -q "your-email@example.com" variables.tf; then
    echo ""
    echo "⚠️  IMPORTANT: Update your email address for alerts!"
    echo "   Current: your-email@example.com"
    read -p "Enter your email address (or press Enter to skip): " user_email
    
    if [ ! -z "$user_email" ]; then
        sed -i "s/your-email@example.com/$user_email/g" variables.tf
        echo "✅ Email updated to: $user_email"
    else
        echo "⚠️  Skipping email update - remember to update variables.tf manually"
    fi
fi

# Create the data quality Lambda function package if the file exists
echo "📦 Checking for data quality Lambda..."
cd ..

if [ -f "lambda_functions/lambda_data_quality.py" ]; then
    echo "📦 Creating data quality Lambda package..."
    cd lambda_functions
    zip -r data_quality_lambda.zip lambda_data_quality.py
    mv data_quality_lambda.zip ../infrastructure/
    cd ../infrastructure
    echo "✅ Data quality Lambda package created"
else
    echo "⚠️  lambda_data_quality.py not found - data quality monitoring will be skipped"
    echo "   You can add it later if needed"
    cd infrastructure
fi

echo "🏗️  Planning Terraform deployment..."
terraform plan

if [ $? -ne 0 ]; then
    echo "❌ Terraform plan failed. Please check the errors above."
    exit 1
fi

echo ""
read -p "Proceed with Day 6 deployment? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "❌ Deployment cancelled"
    exit 1
fi

echo "🚀 Deploying Day 6 infrastructure..."
terraform apply -auto-approve

if [ $? -ne 0 ]; then
    echo "❌ Deployment failed. Please check the errors above."
    exit 1
fi

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