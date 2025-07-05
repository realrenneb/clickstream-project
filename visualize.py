import requests
import json
from datetime import datetime

def display_stats():
    try:
        response = requests.get('http://localhost:3000/stats')
        data = response.json()
        
        print("\n📊 CLICKSTREAM ANALYTICS DASHBOARD")
        print("=" * 50)
        print(f"📈 Total Events: {data['total_events']}")
        print("\n🎯 Events by Type:")
        
        for event_type, count in data['events_by_type'].items():
            percentage = (count / data['total_events']) * 100 if data['total_events'] > 0 else 0
            bar = "█" * int(percentage / 2)
            print(f"  {event_type:<15} {count:>4} ({percentage:>5.1f}%) {bar}")
        
        print("\n🕐 Recent Events:")
        for event in data['recent_events'][-3:]:
            print(f"  • {event.get('event_type', 'unknown')} - User: {event.get('user_id', 'anonymous')}")
        
        print("\n✅ System is working correctly!")
        
    except Exception as e:
        print(f"❌ Error: {e}")
        print("Make sure local_api.py is running!")

if __name__ == "__main__":
    display_stats()