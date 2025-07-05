#!/bin/bash

echo "🚀 Starting Clickstream Demo - Day 2"
echo "===================================="

# Function to kill all processes on exit
cleanup() {
    echo -e "\n\n🛑 Shutting down services..."
    kill $API_PID $DASHBOARD_PID 2>/dev/null
    echo "✅ All services stopped"
    exit 0
}

# Set up trap to catch Ctrl+C and other termination signals
trap cleanup INT TERM EXIT

# Activate virtual environment if not already activated
if [[ "$VIRTUAL_ENV" == "" ]]; then
    echo "Activating virtual environment..."
    source venv/bin/activate
fi

# Start API server
echo "Starting API server..."
python local_api.py &
API_PID=$!

# Wait for API to start
sleep 2

# Check if API is running
if ! kill -0 $API_PID 2>/dev/null; then
    echo "❌ Failed to start API server"
    exit 1
fi

# Start dashboard
echo "Starting dashboard..."
python dashboard.py &
DASHBOARD_PID=$!

# Wait for dashboard to start
sleep 2

# Check if dashboard is running
if ! kill -0 $DASHBOARD_PID 2>/dev/null; then
    echo "❌ Failed to start dashboard"
    exit 1
fi

# Open dashboard in browser
echo "Opening dashboard in browser..."
if [[ "$OSTYPE" == "darwin"* ]]; then
    open http://localhost:5000
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    xdg-open http://localhost:5000 2>/dev/null || echo "Please open http://localhost:5000 in your browser"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    start http://localhost:5000
fi

echo ""
echo "✅ Everything is running!"
echo "📊 Dashboard: http://localhost:5000"
echo "🔌 API: http://localhost:3000"
echo "📁 API Stats: http://localhost:3000/stats"
echo ""
echo "To generate data, run in another terminal:"
echo "  python advanced_generator.py --duration 60 --users 5"
echo ""
echo "Press Ctrl+C to stop all services"

# Wait for processes
wait $API_PID $DASHBOARD_PID