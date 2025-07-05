#!/bin/bash

echo "⚠️  This will destroy all AWS resources!"
read -p "Are you sure? (yes/no) " -n 3 -r
echo
if [[ $REPLY =~ ^yes$ ]]
then
    terraform destroy -auto-approve
    echo "✅ All resources destroyed"
else
    echo "❌ Destruction cancelled"
fi