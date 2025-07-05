import random
import json
import time
import requests
from datetime import datetime
from faker import Faker

fake = Faker()

class ClickstreamGenerator:
    def __init__(self, endpoint="http://localhost:3000/events"):
        self.endpoint = endpoint
        self.user_sessions = {}
        print(f"🎯 Generator initialized. Sending to: {endpoint}")
        
    def generate_event(self):
        """Generate a single realistic clickstream event"""
        
        # 70% chance to use existing session, 30% new session
        if self.user_sessions and random.random() < 0.7:
            session_id = random.choice(list(self.user_sessions.keys()))
            user_id = self.user_sessions[session_id]
        else:
            # Create new session
            session_id = fake.uuid4()
            user_id = f"user_{random.randint(1000, 9999)}"
            self.user_sessions[session_id] = user_id
            print(f"👤 New user session: {user_id}")
        
        # Random event type with realistic distribution
        event_types = ['page_view', 'click', 'search', 'add_to_cart', 'remove_from_cart']
        weights = [0.4, 0.3, 0.15, 0.1, 0.05]  # Page views most common
        event_type = random.choices(event_types, weights=weights)[0]
        
        # Build event
        event = {
            'event_id': fake.uuid4(),
            'event_type': event_type,
            'user_id': user_id,
            'session_id': session_id,
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'properties': {}
        }
        
        # Add event-specific properties
        if event_type == 'page_view':
            pages = ['/', '/products', '/product/123', '/cart', '/checkout', '/about']
            event['properties'] = {
                'page': random.choice(pages),
                'referrer': random.choice(['google.com', 'facebook.com', 'direct', 'twitter.com']),
                'device_type': random.choice(['desktop', 'mobile', 'tablet'])
            }
        elif event_type == 'click':
            event['properties'] = {
                'element': random.choice(['button', 'link', 'image']),
                'element_id': f"elem_{random.randint(100, 999)}"
            }
        elif event_type == 'add_to_cart':
            event['properties'] = {
                'product_id': f'PROD-{random.randint(100, 999)}',
                'product_name': fake.catch_phrase(),
                'price': round(random.uniform(9.99, 299.99), 2),
                'quantity': random.randint(1, 3)
            }
        elif event_type == 'search':
            event['properties'] = {
                'query': fake.word(),
                'results_count': random.randint(0, 100)
            }
        
        return event
    
    def send_batch(self, batch_size=10):
        """Generate and send a batch of events"""
        events = [self.generate_event() for _ in range(batch_size)]
        
        try:
            response = requests.post(
                self.endpoint,
                json={'records': events},
                headers={'Content-Type': 'application/json'},
                timeout=5
            )
            
            if response.status_code == 202:
                print(f"✅ Sent {len(events)} events successfully")
            else:
                print(f"❌ Error {response.status_code}: {response.text}")
                
        except requests.exceptions.ConnectionError:
            print("❌ Cannot connect to API. Is local_api.py running?")
        except Exception as e:
            print(f"❌ Error sending events: {e}")
    
    def run_continuous(self, duration_seconds=60, events_per_second=5):
        """Run continuous event generation"""
        print(f"🚀 Starting generation for {duration_seconds} seconds")
        print(f"📊 Target rate: ~{events_per_second} events/second")
        
        start_time = time.time()
        total_events = 0
        
        while time.time() - start_time < duration_seconds:
            # Random batch size for more realistic traffic
            batch_size = random.randint(1, events_per_second * 2)
            self.send_batch(batch_size)
            total_events += batch_size
            
            # Sleep to control rate
            time.sleep(1)
            
            # Progress update every 10 seconds
            elapsed = int(time.time() - start_time)
            if elapsed % 10 == 0 and elapsed > 0:
                print(f"⏱️  {elapsed}s elapsed, ~{total_events} events sent")
        
        print(f"\n🎉 Generation complete!")
        print(f"📊 Total events sent: {total_events}")
        print(f"📈 Average rate: {total_events/duration_seconds:.1f} events/second")

if __name__ == "__main__":
    print("🔧 Clickstream Data Generator")
    print("=" * 50)
    
    # Create generator
    generator = ClickstreamGenerator()
    
    # Test with a small batch first
    print("\n📋 Sending test batch...")
    generator.send_batch(5)
    
    # Wait for user confirmation
    input("\n⏸️  Press Enter to start continuous generation...")
    
    # Run for 30 seconds
    generator.run_continuous(duration_seconds=30, events_per_second=5)