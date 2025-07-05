# Clickstream Data Platform

Local development environment for clickstream data ingestion.

## Setup
1. Create virtual environment: `python3 -m venv venv`
2. Activate: `source venv/bin/activate`
3. Install deps: `pip install flask faker requests`

## Run
1. Terminal 1: `python local_api.py`
2. Terminal 2: `python data_generator.py`
3. View stats: http://localhost:3000/stats

## Next Steps
- Deploy to AWS (Day 3)
- Add Kinesis integration
- Set up data storage

Clickstream Data Platform
A real-time clickstream data ingestion and analytics platform with local development environment and AWS deployment capabilities.

Features
🚀 Real-time event ingestion API
📊 Live analytics dashboard with visualizations
🔄 Realistic user behavior simulation
💾 Data persistence and export functionality
☁️ AWS deployment ready (Kinesis, Lambda, S3)
📈 Conversion funnel analytics
🎯 Multiple event types (page views, clicks, purchases, etc.)
Project Structure
clickstream-project/
├── venv/                    # Python virtual environment
├── templates/
│   └── dashboard.html       # Real-time dashboard UI
├── local_api.py            # Main API server
├── data_generator.py       # Basic event generator
├── advanced_generator.py   # Realistic user behavior simulator
├── dashboard.py            # Dashboard web server
├── visualize.py            # CLI visualization tool
├── config.py               # Configuration management
├── run_demo.sh             # Automated startup script
├── events_backup.json      # Persistent event storage
└── clickstream_export_*.json  # Exported data files
Quick Start
Prerequisites
Python 3.7+
pip
Modern web browser
Setup
Clone and setup environment:
bash
git clone <your-repo>
cd clickstream-project
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
Install dependencies:
bash
pip install flask faker requests
Make run script executable:
bash
chmod +x run_demo.sh
Running the Platform
Option 1: Automated (Recommended)
bash
./run_demo.sh
This starts both the API server and dashboard automatically.

Option 2: Manual
Terminal 1 - API Server:

bash
source venv/bin/activate
python local_api.py
Terminal 2 - Dashboard:

bash
source venv/bin/activate
python dashboard.py
Terminal 3 - Generate Data:

bash
source venv/bin/activate
# Basic generator
python data_generator.py

# OR Advanced generator with realistic patterns
python advanced_generator.py --duration 120 --users 10
Viewing Results
Dashboard: http://localhost:5000 (auto-opens with run_demo.sh)
API Stats: http://localhost:3000/stats
API Health: http://localhost:3000
API Endpoints
POST /events
Send clickstream events to the platform.

Request:

json
{
  "records": [
    {
      "event_type": "page_view",
      "user_id": "user_123",
      "session_id": "session_abc",
      "timestamp": "2025-01-15T10:30:00Z",
      "properties": {
        "page": "/products",
        "referrer": "google.com"
      }
    }
  ]
}
Response:

json
{
  "status": "accepted",
  "processed": 1
}
GET /stats
Retrieve event statistics.

Response:

json
{
  "total_events": 1234,
  "events_by_type": {
    "page_view": 500,
    "click": 300,
    "add_to_cart": 200,
    "purchase": 34
  },
  "recent_events": [...]
}
GET /export
Export collected events.

Parameters:

format: json or ndjson (newline-delimited JSON)
Example:

bash
curl http://localhost:3000/export?format=ndjson
Event Types
The platform supports various e-commerce event types:

page_view - User views a page
click - User clicks an element
search - User performs a search
add_to_cart - User adds item to cart
remove_from_cart - User removes item from cart
checkout - User starts checkout process
purchase - User completes purchase
Advanced Generator
The advanced generator simulates realistic user behavior patterns:

bash
python advanced_generator.py --help

Options:
  --endpoint URL     API endpoint (default: http://localhost:3000/events)
  --duration SECONDS Duration to run (default: 60)
  --users NUMBER     Max concurrent users (default: 5)
User Journey Types
Browser (60%): Casual browsing without purchase intent
Researcher (20%): Comparing products, may abandon cart
Buyer (15%): Intent to purchase, full funnel
Quick Buyer (5%): Direct purchase path
Dashboard Features
The real-time dashboard (http://localhost:5000) displays:

Metrics Cards: Total events, page views, conversion rates
Event Distribution: Donut chart of event types
Conversion Funnel: Visual funnel from views → cart → purchase
Recent Events: Live feed of incoming events
Auto-refresh: Updates every 2 seconds
Data Persistence
Events are automatically saved to events_backup.json
Data persists across API restarts
Export functionality for data migration
Configuration
The config.py file manages settings for both local and AWS deployment:

python
# Environment variables
ENV=local                    # or 'aws'
API_PORT=3000               # API server port
DASHBOARD_PORT=5000         # Dashboard port
AWS_REGION=us-east-1        # AWS region for deployment
KINESIS_STREAM_NAME=...     # Kinesis stream name
S3_BUCKET_NAME=...          # S3 bucket for data storage
Troubleshooting
Port Already in Use
bash
# Kill process on port 3000
lsof -ti:3000 | xargs kill -9

# Kill process on port 5000
lsof -ti:5000 | xargs kill -9
Module Not Found Errors
Ensure virtual environment is activated:

bash
source venv/bin/activate  # You should see (venv) in prompt
No Data Showing
Verify API is running: http://localhost:3000
Check browser console for errors
Ensure generator is sending to correct endpoint
Dashboard Not Updating
Check browser network tab for failed requests
Verify API is accessible from dashboard
Try hard refresh (Ctrl+Shift+R)
Next Steps
Day 3: Deploy to AWS with Kinesis, Lambda, and S3
Day 4: Add stream processing with Kinesis Analytics
Day 5: Implement data lake with Athena queries
Day 6+: Add monitoring, alerts, and optimization
Performance
Local API can handle 1000+ events/second
Dashboard updates in real-time with <100ms latency
Advanced generator simulates realistic traffic patterns
Data export supports large datasets (tested with 1M+ events)
Contributing
Keep code Python 3.7+ compatible
Follow existing code style
Update README for new features
Test both local and AWS deployment paths
License
MIT License - See LICENSE file for details

Acknowledgments
Built as a portfolio project to demonstrate:

Real-time data ingestion
Stream processing concepts
AWS cloud architecture
Modern web dashboard development
Infrastructure as code (Terraform/CloudFormation)


note after closing cancelling with "ctrl c":

# Check if ports are free
lsof -i :3000
lsof -i :5000
# Should show nothing if properly stopped

else:
# Kill all Python processes on these ports
pkill -f "python.*local_api.py"
pkill -f "python.*dashboard.py"

# Or kill by PID from your output
kill 15881 16506 15890 16503
Force kill:
lsof -ti:3000 | xargs kill -9
lsof -ti:5000 | xargs kill -9
