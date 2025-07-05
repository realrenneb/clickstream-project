from flask import Flask, request, jsonify
from datetime import datetime
import json
import os

app = Flask(__name__)

# Store events in memory for testing
events_buffer = []

@app.route('/')
def home():
    return jsonify({
        "status": "running",
        "message": "Clickstream API is ready!",
        "endpoints": {
            "POST /events": "Send clickstream events",
            "GET /stats": "View statistics"
        }
    })

@app.route('/events', methods=['POST'])
def receive_events():
    try:
        # Get JSON data from request
        data = request.get_json()
        
        if not data:
            return jsonify({"error": "No data provided"}), 400
        
        events = data.get('records', [])
        
        # Process each event
        for event in events:
            event['received_at'] = datetime.utcnow().isoformat()
            events_buffer.append(event)
        
        # Save after receiving new events
        save_events()  # <-- This is where save_events() should be called
        
        print(f"✅ Received {len(events)} events. Total stored: {len(events_buffer)}")
        
        return jsonify({
            'status': 'accepted',
            'processed': len(events)
        }), 202
        
    except Exception as e:
        print(f"❌ Error: {str(e)}")
        return jsonify({"error": str(e)}), 500

@app.route('/stats', methods=['GET'])
def get_stats():
    # Calculate some basic statistics
    event_types = {}
    for event in events_buffer:
        event_type = event.get('event_type', 'unknown')
        event_types[event_type] = event_types.get(event_type, 0) + 1
    
    return jsonify({
        'total_events': len(events_buffer),
        'events_by_type': event_types,
        'recent_events': events_buffer[-5:] if events_buffer else []
    })

@app.route('/export', methods=['GET'])
def export_data():
    """Export events in different formats"""
    format_type = request.args.get('format', 'json')
    
    if format_type == 'json':
        # Create formatted JSON for S3
        export_data = {
            'export_timestamp': datetime.utcnow().isoformat(),
            'total_events': len(events_buffer),
            'events': events_buffer
        }
        
        # Save to file
        filename = f'clickstream_export_{datetime.now().strftime("%Y%m%d_%H%M%S")}.json'
        with open(filename, 'w') as f:
            json.dump(export_data, f, indent=2)
        
        return jsonify({
            'status': 'exported',
            'filename': filename,
            'events_count': len(events_buffer)
        })
    
    elif format_type == 'ndjson':
        # Newline-delimited JSON (better for streaming)
        filename = f'clickstream_export_{datetime.now().strftime("%Y%m%d_%H%M%S")}.ndjson'
        with open(filename, 'w') as f:
            for event in events_buffer:
                f.write(json.dumps(event) + '\n')
        
        return jsonify({
            'status': 'exported',
            'filename': filename,
            'events_count': len(events_buffer)
        })

def save_events():
    """Save events to file"""
    with open('events_backup.json', 'w') as f:
        json.dump(events_buffer, f)
    # Don't call save_events() here - that would be infinite recursion!

def load_events():
    """Load events from file"""
    global events_buffer
    if os.path.exists('events_backup.json'):
        with open('events_backup.json', 'r') as f:
            events_buffer = json.load(f)
            print(f"📥 Loaded {len(events_buffer)} events from backup")

if __name__ == '__main__':
    print("🚀 Starting Clickstream API on http://localhost:3000")
    print("📊 View stats at http://localhost:3000/stats")
    load_events()  # Load previous events when starting
    app.run(debug=True, port=3000)