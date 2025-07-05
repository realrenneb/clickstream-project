from flask import Flask, render_template, jsonify
import requests
import json
from datetime import datetime, timedelta

app = Flask(__name__)

API_URL = "http://localhost:3000/stats"

@app.route('/')
def dashboard():
    return render_template('dashboard.html')

@app.route('/api/stats')
def get_stats():
    """Proxy stats from main API"""
    try:
        response = requests.get(API_URL)
        data = response.json()
        
        # Add calculated metrics
        if data['total_events'] > 0:
            # Calculate conversion funnel
            events = data.get('events_by_type', {})
            data['conversion_metrics'] = {
                'view_to_cart': (events.get('add_to_cart', 0) / events.get('page_view', 1)) * 100,
                'cart_to_purchase': (events.get('purchase', 0) / events.get('add_to_cart', 1)) * 100 if events.get('add_to_cart', 0) > 0 else 0
            }
        
        return jsonify(data)
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(debug=True, port=5000)