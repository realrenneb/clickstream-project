import json
import boto3
import os
from datetime import datetime, timedelta
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
cloudwatch = boto3.client('cloudwatch')
s3 = boto3.client('s3')
athena = boto3.client('athena')

def lambda_handler(event, context):
    """
    Data Quality Monitoring Lambda
    Checks data freshness, record counts, and data integrity
    """
    
    try:
        # Configuration from environment variables
        raw_bucket = os.environ.get('RAW_BUCKET_NAME')
        processed_bucket = os.environ.get('PROCESSED_BUCKET_NAME')
        database_name = os.environ.get('DATABASE_NAME', 'clickstream-demo-processed-db')
        
        logger.info(f"Starting data quality checks for buckets: {raw_bucket}, {processed_bucket}")
        
        # 1. Check data freshness
        freshness_results = check_data_freshness(raw_bucket, processed_bucket)
        
        # 2. Check record counts
        count_results = check_record_counts(database_name)
        
        # 3. Check for data anomalies
        anomaly_results = check_data_anomalies(database_name)
        
        # 4. Publish metrics to CloudWatch
        publish_metrics(freshness_results, count_results, anomaly_results)
        
        # 5. Generate summary report
        report = generate_quality_report(freshness_results, count_results, anomaly_results)
        
        logger.info("Data quality checks completed successfully")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'status': 'success',
                'report': report,
                'timestamp': datetime.utcnow().isoformat()
            })
        }
        
    except Exception as e:
        logger.error(f"Data quality check failed: {str(e)}")
        
        # Publish error metric
        cloudwatch.put_metric_data(
            Namespace='ClickstreamPipeline/DataQuality',
            MetricData=[
                {
                    'MetricName': 'DataQualityCheckErrors',
                    'Value': 1,
                    'Unit': 'Count',
                    'Timestamp': datetime.utcnow()
                }
            ]
        )
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'status': 'error',
                'error': str(e),
                'timestamp': datetime.utcnow().isoformat()
            })
        }

def check_data_freshness(raw_bucket, processed_bucket):
    """Check how fresh the data is in both buckets"""
    
    results = {
        'raw_data_age_minutes': None,
        'processed_data_age_minutes': None,
        'freshness_status': 'healthy'
    }
    
    try:
        # Check raw data freshness
        raw_objects = s3.list_objects_v2(
            Bucket=raw_bucket,
            Prefix='clickstream-data/',
            MaxKeys=10
        )
        
        if 'Contents' in raw_objects:
            latest_raw = max(raw_objects['Contents'], key=lambda x: x['LastModified'])
            raw_age_minutes = (datetime.now(latest_raw['LastModified'].tzinfo) - latest_raw['LastModified']).total_seconds() / 60
            results['raw_data_age_minutes'] = raw_age_minutes
            
            if raw_age_minutes > 120:  # Alert if data is older than 2 hours
                results['freshness_status'] = 'stale'
        
        # Check processed data freshness
        processed_objects = s3.list_objects_v2(
            Bucket=processed_bucket,
            Prefix='events/',
            MaxKeys=10
        )
        
        if 'Contents' in processed_objects:
            latest_processed = max(processed_objects['Contents'], key=lambda x: x['LastModified'])
            processed_age_minutes = (datetime.now(latest_processed['LastModified'].tzinfo) - latest_processed['LastModified']).total_seconds() / 60
            results['processed_data_age_minutes'] = processed_age_minutes
            
            if processed_age_minutes > 180:  # Alert if processed data is older than 3 hours
                results['freshness_status'] = 'stale'
                
    except Exception as e:
        logger.error(f"Error checking data freshness: {str(e)}")
        results['freshness_status'] = 'error'
    
    return results

def check_record_counts(database_name):
    """Check record counts and trends"""
    
    results = {
        'total_records': 0,
        'records_last_hour': 0,
        'records_last_24h': 0,
        'count_status': 'healthy'
    }
    
    try:
        # Query total records
        total_query = "SELECT COUNT(*) as total FROM events_processed"
        total_result = execute_athena_query(total_query, database_name)
        
        if total_result and len(total_result) > 0:
            results['total_records'] = int(total_result[0]['total'])
        
        # Query records from last hour
        hour_query = """
        SELECT COUNT(*) as hourly_count 
        FROM events_processed 
        WHERE processed_at >= current_timestamp - interval '1' hour
        """
        hour_result = execute_athena_query(hour_query, database_name)
        
        if hour_result and len(hour_result) > 0:
            results['records_last_hour'] = int(hour_result[0]['hourly_count'])
        
        # Query records from last 24 hours
        daily_query = """
        SELECT COUNT(*) as daily_count 
        FROM events_processed 
        WHERE processed_at >= current_timestamp - interval '24' hour
        """
        daily_result = execute_athena_query(daily_query, database_name)
        
        if daily_result and len(daily_result) > 0:
            results['records_last_24h'] = int(daily_result[0]['daily_count'])
        
        # Determine status based on trends
        if results['records_last_hour'] == 0:
            results['count_status'] = 'no_recent_data'
        elif results['records_last_24h'] < 100:  # Expect at least 100 records per day
            results['count_status'] = 'low_volume'
            
    except Exception as e:
        logger.error(f"Error checking record counts: {str(e)}")
        results['count_status'] = 'error'
    
    return results

def check_data_anomalies(database_name):
    """Check for data quality anomalies"""
    
    results = {
        'null_user_ids': 0,
        'null_timestamps': 0,
        'duplicate_events': 0,
        'anomaly_status': 'healthy'
    }
    
    try:
        # Check for null user IDs
        null_users_query = "SELECT COUNT(*) as null_count FROM events_processed WHERE user_id IS NULL"
        null_users_result = execute_athena_query(null_users_query, database_name)
        
        if null_users_result and len(null_users_result) > 0:
            results['null_user_ids'] = int(null_users_result[0]['null_count'])
        
        # Check for null timestamps
        null_timestamps_query = "SELECT COUNT(*) as null_count FROM events_processed WHERE processed_at IS NULL"
        null_timestamps_result = execute_athena_query(null_timestamps_query, database_name)
        
        if null_timestamps_result and len(null_timestamps_result) > 0:
            results['null_timestamps'] = int(null_timestamps_result[0]['null_count'])
        
        # Check for duplicate events (same event_id)
        duplicates_query = """
        SELECT COUNT(*) as duplicate_count 
        FROM (
            SELECT event_id, COUNT(*) as cnt 
            FROM events_processed 
            GROUP BY event_id 
            HAVING COUNT(*) > 1
        )
        """
        duplicates_result = execute_athena_query(duplicates_query, database_name)
        
        if duplicates_result and len(duplicates_result) > 0:
            results['duplicate_events'] = int(duplicates_result[0]['duplicate_count'])
        
        # Determine anomaly status
        total_anomalies = results['null_user_ids'] + results['null_timestamps'] + results['duplicate_events']
        if total_anomalies > 0:
            results['anomaly_status'] = 'anomalies_detected'
            
    except Exception as e:
        logger.error(f"Error checking data anomalies: {str(e)}")
        results['anomaly_status'] = 'error'
    
    return results

def execute_athena_query(query, database_name):
    """Execute Athena query and return results"""
    
    try:
        # Start query execution
        response = athena.start_query_execution(
            QueryString=query,
            QueryExecutionContext={'Database': database_name},
            ResultConfiguration={
                'OutputLocation': f's3://{os.environ.get("ATHENA_RESULTS_BUCKET")}/data-quality-queries/'
            }
        )
        
        query_execution_id = response['QueryExecutionId']
        
        # Wait for query to complete (with timeout)
        max_attempts = 30
        attempt = 0
        
        while attempt < max_attempts:
            result = athena.get_query_execution(QueryExecutionId=query_execution_id)
            status = result['QueryExecution']['Status']['State']
            
            if status == 'SUCCEEDED':
                break
            elif status in ['FAILED', 'CANCELLED']:
                logger.error(f"Query failed: {result['QueryExecution']['Status']}")
                return None
            
            attempt += 1
            time.sleep(2)
        
        if attempt >= max_attempts:
            logger.error("Query timed out")
            return None
        
        # Get query results
        results = athena.get_query_results(QueryExecutionId=query_execution_id)
        
        # Parse results
        rows = results['ResultSet']['Rows']
        if len(rows) < 2:  # Header + at least one data row
            return None
        
        headers = [col['VarCharValue'] for col in rows[0]['Data']]
        data_rows = []
        
        for row in rows[1:]:  # Skip header row
            row_data = {}
            for i, col in enumerate(row['Data']):
                row_data[headers[i]] = col.get('VarCharValue', '')
            data_rows.append(row_data)
        
        return data_rows
        
    except Exception as e:
        logger.error(f"Athena query execution failed: {str(e)}")
        return None

def publish_metrics(freshness_results, count_results, anomaly_results):
    """Publish metrics to CloudWatch"""
    
    metrics = []
    
    # Freshness metrics
    if freshness_results['raw_data_age_minutes'] is not None:
        metrics.append({
            'MetricName': 'RawDataAgeMinutes',
            'Value': freshness_results['raw_data_age_minutes'],
            'Unit': 'None',
            'Timestamp': datetime.utcnow()
        })
    
    if freshness_results['processed_data_age_minutes'] is not None:
        metrics.append({
            'MetricName': 'ProcessedDataAgeMinutes',
            'Value': freshness_results['processed_data_age_minutes'],
            'Unit': 'None',
            'Timestamp': datetime.utcnow()
        })
    
    # Count metrics
    metrics.extend([
        {
            'MetricName': 'TotalRecords',
            'Value': count_results['total_records'],
            'Unit': 'Count',
            'Timestamp': datetime.utcnow()
        },
        {
            'MetricName': 'RecordsLastHour',
            'Value': count_results['records_last_hour'],
            'Unit': 'Count',
            'Timestamp': datetime.utcnow()
        },
        {
            'MetricName': 'RecordsLast24Hours',
            'Value': count_results['records_last_24h'],
            'Unit': 'Count',
            'Timestamp': datetime.utcnow()
        }
    ])
    
    # Anomaly metrics
    metrics.extend([
        {
            'MetricName': 'NullUserIds',
            'Value': anomaly_results['null_user_ids'],
            'Unit': 'Count',
            'Timestamp': datetime.utcnow()
        },
        {
            'MetricName': 'NullTimestamps',
            'Value': anomaly_results['null_timestamps'],
            'Unit': 'Count',
            'Timestamp': datetime.utcnow()
        },
        {
            'MetricName': 'DuplicateEvents',
            'Value': anomaly_results['duplicate_events'],
            'Unit': 'Count',
            'Timestamp': datetime.utcnow()
        }
    ])
    
    # Publish metrics in batches (CloudWatch limit is 20 per call)
    batch_size = 20
    for i in range(0, len(metrics), batch_size):
        batch = metrics[i:i + batch_size]
        try:
            cloudwatch.put_metric_data(
                Namespace='ClickstreamPipeline/DataQuality',
                MetricData=batch
            )
        except Exception as e:
            logger.error(f"Failed to publish metrics batch: {str(e)}")

def generate_quality_report(freshness_results, count_results, anomaly_results):
    """Generate a summary report of data quality"""
    
    report = {
        'overall_status': 'healthy',
        'checks_performed': 3,
        'checks_passed': 0,
        'issues': [],
        'summary': {}
    }
    
    # Check freshness status
    if freshness_results['freshness_status'] == 'healthy':
        report['checks_passed'] += 1
    else:
        report['issues'].append(f"Data freshness issue: {freshness_results['freshness_status']}")
        report['overall_status'] = 'warning'
    
    # Check count status
    if count_results['count_status'] == 'healthy':
        report['checks_passed'] += 1
    else:
        report['issues'].append(f"Record count issue: {count_results['count_status']}")
        if count_results['count_status'] == 'no_recent_data':
            report['overall_status'] = 'critical'
        else:
            report['overall_status'] = 'warning'
    
    # Check anomaly status
    if anomaly_results['anomaly_status'] == 'healthy':
        report['checks_passed'] += 1
    else:
        report['issues'].append(f"Data anomaly detected: {anomaly_results['anomaly_status']}")
        report['overall_status'] = 'warning'
    
    # Add summary statistics
    report['summary'] = {
        'total_records': count_results['total_records'],
        'records_last_hour': count_results['records_last_hour'],
        'raw_data_age_minutes': freshness_results['raw_data_age_minutes'],
        'processed_data_age_minutes': freshness_results['processed_data_age_minutes'],
        'total_anomalies': (
            anomaly_results['null_user_ids'] + 
            anomaly_results['null_timestamps'] + 
            anomaly_results['duplicate_events']
        )
    }
    
    return report