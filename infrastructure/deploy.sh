#!/bin/bash

echo "📦 Packaging Lambda function..."
cp lambda_function.py index.py
zip lambda.zip index.py
rm index.py

echo "🚀 Deploying infrastructure..."
terraform init
terraform plan
terraform apply -auto-approve

echo ""
echo "✅ Deployment complete!"
echo ""
echo "📊 Your API endpoint is:"
terraform output -raw api_endpoint
echo ""