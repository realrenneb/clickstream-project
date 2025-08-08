#!/bin/bash
echo "🧹 Force deleting ALL clickstream IAM roles..."

ROLES=$(aws iam list-roles --query 'Roles[?contains(RoleName, `clickstream`)].RoleName' --output text)

for role in $ROLES; do
    if [ ! -z "$role" ]; then
        echo "Deleting role: $role"
        
        # Detach managed policies
        MANAGED_POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null)
        for policy in $MANAGED_POLICIES; do
            if [ ! -z "$policy" ]; then
                echo "  Detaching: $policy"
                aws iam detach-role-policy --role-name "$role" --policy-arn "$policy" 2>/dev/null
            fi
        done
        
        # Delete inline policies
        INLINE_POLICIES=$(aws iam list-role-policies --role-name "$role" --query 'PolicyNames' --output text 2>/dev/null)
        for policy in $INLINE_POLICIES; do
            if [ ! -z "$policy" ]; then
                echo "  Deleting: $policy"
                aws iam delete-role-policy --role-name "$role" --policy-name "$policy" 2>/dev/null
            fi
        done
        
        # Delete the role
        echo "  Deleting role: $role"
        aws iam delete-role --role-name "$role" 2>/dev/null
        
        # Check if deleted
        if aws iam get-role --role-name "$role" >/dev/null 2>&1; then
            echo "  ❌ Failed to delete $role"
        else
            echo "  ✅ Successfully deleted $role"
        fi
    fi
done
