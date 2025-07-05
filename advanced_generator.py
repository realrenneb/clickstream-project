import random
import json
import time
import requests
import argparse
from datetime import datetime, timedelta
from faker import Faker
import threading
import queue

fake = Faker()

class UserSession:
    """Represents a single user's browsing session"""
    def __init__(self, user_id=None):
        self.session_id = fake.uuid4()
        self.user_id = user_id or f"user_{random.randint(1000, 9999)}"
        self.start_time = datetime.utcnow()
        self.page_views = 0
        self.cart_items = []
        self.total_value = 0
        self.device_type = random.choice(['desktop', 'mobile', 'tablet'])
        self.browser = random.choice(['Chrome', 'Firefox', 'Safari', 'Edge'])
        self.country = fake.country_code()
        self.referrer = self._get_referrer()
        
    def _get_referrer(self):
        """Get realistic referrer"""
        referrers = {
            'google.com': 0.4,
            'facebook.com': 0.2,
            'direct': 0.2,
            'twitter.com': 0.1,
            'instagram.com': 0.05,
            'reddit.com': 0.05
        }
        return random.choices(list(referrers.keys()), 
                            weights=list(referrers.values()))[0]
    
    def get_session_duration(self):
        """Calculate session duration"""
        return (datetime.utcnow() - self.start_time).total_seconds()

class RealisticClickstreamGenerator:
    def __init__(self, endpoint="http://localhost:3000/events"):
        self.endpoint = endpoint
        self.active_sessions = {}
        self.products = self._load_products()
        self.event_queue = queue.Queue()
        self.stats = {
            'total_events': 0,
            'total_sessions': 0,
            'total_revenue': 0,
            'events_by_type': {}
        }
        
    def _load_products(self):
        """Create realistic product catalog"""
        categories = {
            'Electronics': ['Laptop', 'Phone', 'Headphones', 'Tablet', 'Smart Watch'],
            'Clothing': ['T-Shirt', 'Jeans', 'Jacket', 'Shoes', 'Hat'],
            'Home': ['Coffee Maker', 'Blender', 'Vacuum', 'Lamp', 'Rug'],
            'Sports': ['Running Shoes', 'Yoga Mat', 'Weights', 'Bike', 'Ball'],
            'Books': ['Fiction', 'Non-Fiction', 'Textbook', 'Comic', 'Magazine']
        }
        
        products = []
        for category, items in categories.items():
            for item in items:
                products.append({
                    'id': f'PROD-{random.randint(1000, 9999)}',
                    'name': f"{fake.company()} {item}",
                    'category': category,
                    'price': round(random.uniform(9.99, 999.99), 2),
                    'rating': round(random.uniform(3.0, 5.0), 1),
                    'in_stock': random.choice([True, True, True, False])  # 75% in stock
                })
        return products
    
    def generate_user_journey(self, session):
        """Generate a realistic user journey"""
        journey_types = {
            'browser': {  # Just browsing, no purchase
                'weight': 0.6,
                'events': ['page_view', 'page_view', 'search', 'page_view', 'click']
            },
            'researcher': {  # Comparing products
                'weight': 0.2,
                'events': ['page_view', 'search', 'page_view', 'click', 'add_to_cart', 
                          'remove_from_cart', 'page_view', 'search']
            },
            'buyer': {  # Intent to purchase
                'weight': 0.15,
                'events': ['page_view', 'search', 'page_view', 'click', 'add_to_cart',
                          'page_view', 'add_to_cart', 'checkout', 'purchase']
            },
            'quick_buyer': {  # Direct purchase
                'weight': 0.05,
                'events': ['page_view', 'add_to_cart', 'checkout', 'purchase']
            }
        }
        
        # Select journey type
        journey_type = random.choices(
            list(journey_types.keys()),
            weights=[j['weight'] for j in journey_types.values()]
        )[0]
        
        return journey_types[journey_type]['events']
    
    def generate_event(self, session, event_type):
        """Generate a specific event type with realistic data"""
        base_event = {
            'event_id': fake.uuid4(),
            'event_type': event_type,
            'user_id': session.user_id,
            'session_id': session.session_id,
            'timestamp': datetime.utcnow().isoformat() + 'Z',
            'device_type': session.device_type,
            'browser': session.browser,
            'country': session.country,
            'properties': {}
        }
        
        # Event-specific properties
        if event_type == 'page_view':
            pages = {
                '/': 0.3,
                '/products': 0.2,
                f'/products/{random.choice(self.products)["id"]}': 0.2,
                '/cart': 0.1,
                '/checkout': 0.05,
                '/about': 0.05,
                '/contact': 0.05,
                '/search': 0.05
            }
            page = random.choices(list(pages.keys()), weights=list(pages.values()))[0]
            
            base_event['properties'] = {
                'page': page,
                'referrer': session.referrer if session.page_views == 0 else 'internal',
                'page_load_time_ms': random.randint(200, 2000),
                'session_page_views': session.page_views
            }
            session.page_views += 1
            
        elif event_type == 'click':
            base_event['properties'] = {
                'element_type': random.choice(['button', 'link', 'image', 'nav']),
                'element_id': f'elem_{random.randint(100, 999)}',
                'element_text': random.choice(['Buy Now', 'Learn More', 'Add to Cart', 'View Details']),
                'x_position': random.randint(0, 1920),
                'y_position': random.randint(0, 1080)
            }
            
        elif event_type == 'search':
            # Realistic search queries
            search_terms = ['laptop', 'shoes', 'phone case', 'coffee', 'book', 
                          'workout equipment', 'desk lamp', 'backpack']
            query = random.choice(search_terms) + ' ' + random.choice(['', 'best', 'cheap', 'review'])
            
            base_event['properties'] = {
                'query': query.strip(),
                'results_count': random.randint(0, 100),
                'filters_applied': random.choice([{}, {'category': 'Electronics'}, {'price_range': '0-100'}])
            }
            
        elif event_type == 'add_to_cart':
            product = random.choice(self.products)
            quantity = random.choices([1, 2, 3], weights=[0.7, 0.2, 0.1])[0]
            
            base_event['properties'] = {
                'product_id': product['id'],
                'product_name': product['name'],
                'category': product['category'],
                'price': product['price'],
                'quantity': quantity,
                'cart_value': session.total_value + (product['price'] * quantity)
            }
            
            session.cart_items.append(product)
            session.total_value += product['price'] * quantity
            
        elif event_type == 'remove_from_cart':
            if session.cart_items:
                product = random.choice(session.cart_items)
                base_event['properties'] = {
                    'product_id': product['id'],
                    'product_name': product['name'],
                    'reason': random.choice(['changed_mind', 'too_expensive', 'found_better'])
                }
                session.cart_items.remove(product)
                session.total_value -= product['price']
                
        elif event_type == 'checkout':
            base_event['properties'] = {
                'step': random.choice(['shipping', 'payment', 'review']),
                'cart_items': len(session.cart_items),
                'cart_value': session.total_value
            }
            
        elif event_type == 'purchase':
            base_event['properties'] = {
                'order_id': f'ORDER-{random.randint(10000, 99999)}',
                'items': len(session.cart_items),
                'total_amount': session.total_value,
                'payment_method': random.choice(['credit_card', 'paypal', 'apple_pay']),
                'shipping_method': random.choice(['standard', 'express', 'next_day'])
            }
            self.stats['total_revenue'] += session.total_value
        
        # Update stats
        self.stats['total_events'] += 1
        event_type_key = base_event['event_type']
        self.stats['events_by_type'][event_type_key] = self.stats['events_by_type'].get(event_type_key, 0) + 1
        
        return base_event
    
    def simulate_user_session(self):
        """Simulate a complete user session"""
        session = UserSession()
        self.stats['total_sessions'] += 1
        
        # Get user journey
        journey = self.generate_user_journey(session)
        
        # Generate events with realistic timing
        for i, event_type in enumerate(journey):
            event = self.generate_event(session, event_type)
            self.event_queue.put(event)
            
            # Wait between events (faster for returning users)
            if i < len(journey) - 1:
                wait_time = random.uniform(0.5, 5.0) if session.page_views < 3 else random.uniform(0.2, 2.0)
                time.sleep(wait_time)
        
        # Session ends
        session_duration = session.get_session_duration()
        print(f"👤 Session ended: {session.user_id} - Duration: {session_duration:.1f}s, Events: {len(journey)}")
    
    def send_batch(self):
        """Send events from queue to API"""
        events = []
        while not self.event_queue.empty() and len(events) < 20:
            try:
                events.append(self.event_queue.get_nowait())
            except queue.Empty:
                break
        
        if events:
            try:
                response = requests.post(
                    self.endpoint,
                    json={'records': events},
                    headers={'Content-Type': 'application/json'},
                    timeout=5
                )
                
                if response.status_code == 202:
                    print(f"✅ Sent {len(events)} events")
                else:
                    print(f"❌ Error {response.status_code}")
                    # Put events back in queue
                    for event in events:
                        self.event_queue.put(event)
                        
            except Exception as e:
                print(f"❌ Error sending events: {e}")
                # Put events back in queue
                for event in events:
                    self.event_queue.put(event)
    
    def run_simulation(self, duration_seconds=60, concurrent_users=5):
        """Run realistic traffic simulation"""
        print(f"🚀 Starting realistic simulation")
        print(f"⏱️  Duration: {duration_seconds} seconds")
        print(f"👥 Concurrent users: {concurrent_users}")
        print("=" * 50)
        
        start_time = time.time()
        
        # Start sender thread
        def sender_worker():
            while time.time() - start_time < duration_seconds:
                self.send_batch()
                time.sleep(1)
        
        sender_thread = threading.Thread(target=sender_worker)
        sender_thread.daemon = True
        sender_thread.start()
        
        # Simulate users
        threads = []
        while time.time() - start_time < duration_seconds:
            # Random number of concurrent users
            active_users = random.randint(1, concurrent_users)
            
            for _ in range(active_users):
                thread = threading.Thread(target=self.simulate_user_session)
                thread.daemon = True
                thread.start()
                threads.append(thread)
            
            # Wait before starting new sessions
            time.sleep(random.uniform(2, 5))
        
        # Wait for remaining events to be sent
        time.sleep(2)
        
        # Print summary
        print("\n" + "=" * 50)
        print("📊 Simulation Summary:")
        print(f"Total Events: {self.stats['total_events']}")
        print(f"Total Sessions: {self.stats['total_sessions']}")
        print(f"Total Revenue: ${self.stats['total_revenue']:.2f}")
        print("\nEvents by Type:")
        for event_type, count in sorted(self.stats['events_by_type'].items()):
            print(f"  {event_type}: {count}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description='Advanced Clickstream Generator')
    parser.add_argument('--endpoint', default='http://localhost:3000/events', help='API endpoint')
    parser.add_argument('--duration', type=int, default=60, help='Duration in seconds')
    parser.add_argument('--users', type=int, default=5, help='Max concurrent users')
    
    args = parser.parse_args()
    
    generator = RealisticClickstreamGenerator(args.endpoint)
    generator.run_simulation(duration_seconds=args.duration, concurrent_users=args.users)