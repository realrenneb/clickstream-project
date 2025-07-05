import os
from datetime import datetime

class Config:
    """Configuration for both local and AWS deployment"""
    
    # Environment
    ENV = os.environ.get('ENV', 'local')
    
    # API Configuration
    API_PORT = int(os.environ.get('API_PORT', 3000))
    DASHBOARD_PORT = int(os.environ.get('DASHBOARD_PORT', 5000))
    
    # AWS Configuration (for tomorrow)
    AWS_REGION = os.environ.get('AWS_REGION', 'us-east-1')
    KINESIS_STREAM_NAME = os.environ.get('KINESIS_STREAM_NAME', 'clickstream-demo-stream')
    S3_BUCKET_NAME = os.environ.get('S3_BUCKET_NAME', f'clickstream-demo-{datetime.now().strftime("%Y%m%d")}')
    
    # Local storage
    DATA_DIR = os.environ.get('DATA_DIR', './data')
    
    @classmethod
    def is_aws(cls):
        return cls.ENV == 'aws'
    
    @classmethod
    def get_endpoint(cls):
        if cls.is_aws():
            # Will be set tomorrow with actual AWS endpoint
            return os.environ.get('API_GATEWAY_URL', 'http://localhost:3000/events')
        return f'http://localhost:{cls.API_PORT}/events'

# Create data directory if it doesn't exist
os.makedirs(Config.DATA_DIR, exist_ok=True)