import boto3
import time
import sys

def run_athena_query(query, database, output_location):
    """Run an Athena query and return results"""
    athena = boto3.client('athena', region_name='eu-west-2')
    
    # Start query execution
    response = athena.start_query_execution(
        QueryString=query,
        QueryExecutionContext={'Database': database},
        ResultConfiguration={'OutputLocation': f's3://{output_location}/'}
    )
    
    query_execution_id = response['QueryExecutionId']
    
    # Wait for query to complete
    while True:
        response = athena.get_query_execution(QueryExecutionId=query_execution_id)
        status = response['QueryExecution']['Status']['State']
        
        if status in ['SUCCEEDED', 'FAILED', 'CANCELLED']:
            break
            
        time.sleep(1)
    
    if status == 'SUCCEEDED':
        # Get query results
        results = athena.get_query_results(QueryExecutionId=query_execution_id)
        
        # Process results
        rows = []
        for row in results['ResultSet']['Rows'][1:]:  # Skip header
            rows.append([col.get('VarCharValue', '') for col in row['Data']])
        
        # Get column names
        columns = [col['Label'] for col in results['ResultSet']['ResultSetMetadata']['ColumnInfo']]
        
        return {'columns': columns, 'rows': rows}
    else:
        return {'error': response['QueryExecution']['Status'].get('StateChangeReason')}

if __name__ == "__main__":
    # Example usage
    query = """
    SELECT event_type, COUNT(*) as count
    FROM events
    WHERE year = YEAR(CURRENT_DATE)
      AND month = MONTH(CURRENT_DATE)
      AND day = DAY(CURRENT_DATE)
    GROUP BY event_type
    ORDER BY count DESC
    """
    
    # Get bucket name from Terraform
    import subprocess
    result = subprocess.run(['terraform', 'output', '-raw', 'athena_results_bucket'], 
                          capture_output=True, text=True, cwd='infrastructure')
    output_bucket = result.stdout.strip()
    
    results = run_athena_query(query, 'clickstream_demo_db', output_bucket)
    
    if 'error' in results:
        print(f"Query failed: {results['error']}")
    else:
        print("\nQuery Results:")
        print("-" * 50)
        print("\t".join(results['columns']))
        print("-" * 50)
        for row in results['rows']:
            print("\t".join(row))