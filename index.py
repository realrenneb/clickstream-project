import json
import boto3
import os
from datetime import datetime

# Initialize Kinesis client
kinesis = boto3.client('kinesis')
stream_name = os.environ.get('KINESIS_STREAM_NAME', 'clickstream-demo-stream')

def lambda_handler(event, context):
    """Process clickstream events from API Gateway"""
    
    print(f"Received event: {json.dumps(event)}")
    
    try:
        # Parse the request body
        if 'body' not in event:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'No body in request'})
            }
        
        # Handle empty body
        body_str = event['body']
        if not body_str:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Empty request body'})
            }
        
        # Handle base64 encoding if needed (from API Gateway)
        if event.get('isBase64Encoded', False):
            import base64
            body_str = base64.b64decode(body_str).decode('utf-8')
        
        body = json.loads(body_str)
        records = body.get('records', [])
        
        if not records:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'No records provided'})
            }
        
        print(f"Processing {len(records)} records")
        
        # Prepare records for Kinesis
        kinesis_records = []
        for record in records:
            # Add server timestamp
            record['processed_at'] = datetime.utcnow().isoformat()
            record['lambda_request_id'] = context.aws_request_id
            
            # NO BASE64 ENCODING! Just send the JSON string
            record_json = json.dumps(record)
            
            kinesis_records.append({
                'Data': record_json,  # Plain JSON string - boto3 handles encoding
                'PartitionKey': record.get('user_id', 'anonymous')
            })
        
        print(f"Sending {len(kinesis_records)} records to Kinesis stream: {stream_name}")
        
        # Send to Kinesis
        response = kinesis.put_records(
            Records=kinesis_records,
            StreamName=stream_name
        )
        
        print(f"Kinesis response: {response}")
        
        failed = response.get('FailedRecordCount', 0)
        success = len(records) - failed
        
        print(f"Successfully sent {success} records, {failed} failed")
        
        # Log any failures
        if failed > 0:
            for i, result in enumerate(response['Records']):
                if 'ErrorCode' in result:
                    print(f"Failed record {i}: {result['ErrorCode']} - {result.get('ErrorMessage', 'No message')}")
        
        return {
            'statusCode': 202,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*'
            },
            'body': json.dumps({
                'status': 'accepted',
                'processed': success,
                'failed': failed,
                'request_id': context.aws_request_id
            })
        }
        
    except json.JSONDecodeError as e:
        print(f"JSON decode error: {str(e)}")
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': f'Invalid JSON: {str(e)}'})
        }
        
    except Exception as e:
        print(f"Error processing request: {str(e)}")
        import traceback
        print(f"Traceback: {traceback.format_exc()}")
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': 'Internal server error'})
        }