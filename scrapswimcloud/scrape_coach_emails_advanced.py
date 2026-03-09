"""
Advanced Swimming Coach Email Scraper with Selenium Support
Handles JavaScript-loaded content and complex web pages
"""

import csv
import requests
from bs4 import BeautifulSoup
import time
import json
import os
from urllib.parse import urljoin, urlparse
import re
from typing import List, Dict, Optional
from datetime import datetime

# Try to import Selenium for JavaScript handling
try:
    from selenium import webdriver
    from selenium.webdriver.chrome.service import Service
    from selenium.webdriver.chrome.options import Options
    from selenium.webdriver.common.by import By
    from selenium.webdriver.support.ui import WebDriverWait
    from selenium.webdriver.support import expected_conditions as EC
    SELENIUM_AVAILABLE = True
except ImportError:
    SELENIUM_AVAILABLE = False
    print("⚠️  Selenium not available. Install with: pip install selenium")

class AdvancedCoachEmailScraper:
    """Advanced scraper with Selenium support for JavaScript-heavy sites"""

    def __init__(self, use_selenium: bool = False):
        # Basic requests session
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        })

        # Selenium setup
        self.use_selenium = use_selenium and SELENIUM_AVAILABLE
        self.driver = None

        if self.use_selenium:
            self.setup_selenium()

        # Email regex pattern
        self.email_pattern = re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b')

        # Coach/staff related keywords
        self.coach_keywords = [
            'staff', 'coach', 'coaching', 'coaches', 'roster',
            'swimming-and-diving', 'swim-dive', 'aquatics',
            'mens-swimming', 'womens-swimming', 'swim-staff'
        ]

        # Title keywords to identify coaches
        self.coach_titles = [
            'head coach', 'assistant coach', 'associate coach',
            'diving coach', 'swimming coach', 'coach',
            'director', 'coordinator'
        ]

        # Results storage
        self.results = []
        self.errors = []

    def setup_selenium(self):
        """Setup Selenium WebDriver"""
        try:
            options = Options()
            options.add_argument('--headless')
            options.add_argument('--no-sandbox')
            options.add_argument('--disable-dev-shm-usage')
            options.add_argument('--disable-blink-features=AutomationControlled')
            options.add_argument(f'user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36')

            self.driver = webdriver.Chrome(options=options)
            print("✅ Selenium WebDriver initialized")
        except Exception as e:
            print(f"⚠️  Could not initialize Selenium: {str(e)}")
            self.use_selenium = False

    def cleanup(self):
        """Cleanup resources"""
        if self.driver:
            self.driver.quit()

    def extract_emails(self, text: str) -> List[str]:
        """Extract all email addresses from text"""
        return list(set(self.email_pattern.findall(text)))

    def is_valid_coach_email(self, email: str, context: str = "") -> bool:
        """Validate if email is likely a coach's email"""
        email_lower = email.lower()

        # Filter out generic emails
        invalid_patterns = [
            'example.com', 'test.com', 'noreply', 'no-reply',
            'webmaster', 'postmaster', 'admin@', 'info@',
            'support@', 'help@', 'contact@', 'sales@',
            'marketing@', 'press@', 'media@', 'tickets@',
            'compliance@', 'legal@', 'privacy@'
        ]

        if any(pattern in email_lower for pattern in invalid_patterns):
            return False

        # Boost if email contains coach-related keywords
        if any(keyword in email_lower for keyword in ['coach', 'swim', 'dive', 'aqua']):
            return True

        # Check context for coach titles
        if context:
            context_lower = context.lower()
            if any(title in context_lower for title in self.coach_titles):
                return True

        # Accept university/college emails
        edu_domains = ['.edu', 'university', 'college', 'athletics']
        if any(domain in email_lower for domain in edu_domains):
            return True

        return False

    def find_staff_pages(self, base_url: str) -> List[str]:
        """Find coach/staff pages on website"""
        staff_pages = set()

        try:
            if self.use_selenium and self.driver:
                self.driver.get(base_url)
                time.sleep(2)  # Wait for page to load
                page_source = self.driver.page_source
            else:
                response = self.session.get(base_url, timeout=10)
                response.raise_for_status()
                page_source = response.content

            soup = BeautifulSoup(page_source, 'html.parser')

            # Find links matching coach/staff keywords
            for link in soup.find_all('a', href=True):
                href = link.get('href', '').lower()
                link_text = link.get_text().strip().lower()

                # Check if link matches keywords
                if any(keyword in href or keyword in link_text for keyword in self.coach_keywords):
                    full_url = urljoin(base_url, link['href'])
                    staff_pages.add(full_url)

            # If no pages found, use base URL
            if not staff_pages:
                staff_pages.add(base_url)

        except Exception as e:
            print(f"  ⚠️  Error finding staff pages: {str(e)[:80]}")
            staff_pages.add(base_url)

        return list(staff_pages)[:7]  # Limit to 7 pages

    def scrape_page_with_context(self, url: str) -> List[Dict[str, str]]:
        """Scrape emails with surrounding context"""
        email_data = []

        try:
            if self.use_selenium and self.driver:
                self.driver.get(url)
                WebDriverWait(self.driver, 5).until(
                    EC.presence_of_element_located((By.TAG_NAME, "body"))
                )
                page_source = self.driver.page_source
            else:
                response = self.session.get(url, timeout=10)
                response.raise_for_status()
                page_source = response.content

            soup = BeautifulSoup(page_source, 'html.parser')

            # Method 1: Look for staff/coach sections
            for section in soup.find_all(['div', 'section', 'article'], class_=re.compile(r'(staff|coach|roster)', re.I)):
                section_text = section.get_text()
                emails = self.extract_emails(section_text)

                for email in emails:
                    if self.is_valid_coach_email(email, section_text):
                        email_data.append({
                            'email': email,
                            'context': section_text[:200],
                            'found_on': url
                        })

            # Method 2: Look for mailto links
            for link in soup.find_all('a', href=re.compile(r'mailto:', re.I)):
                email = link['href'].replace('mailto:', '').split('?')[0].strip()
                context = link.get_text() + ' ' + str(link.parent.get_text()[:200] if link.parent else '')

                if self.is_valid_coach_email(email, context):
                    email_data.append({
                        'email': email,
                        'context': context[:200],
                        'found_on': url
                    })

            # Method 3: Look for text with coach titles near emails
            page_text = soup.get_text()
            emails_in_text = self.extract_emails(page_text)

            for email in emails_in_text:
                # Find context around email
                email_pos = page_text.lower().find(email.lower())
                if email_pos > 0:
                    context_start = max(0, email_pos - 150)
                    context_end = min(len(page_text), email_pos + 150)
                    context = page_text[context_start:context_end]

                    if self.is_valid_coach_email(email, context):
                        email_data.append({
                            'email': email,
                            'context': context,
                            'found_on': url
                        })

        except Exception as e:
            print(f"  ⚠️  Error scraping page: {str(e)[:80]}")

        # Remove duplicates based on email
        unique_emails = {}
        for item in email_data:
            email = item['email'].lower()
            if email not in unique_emails:
                unique_emails[email] = item

        return list(unique_emails.values())

    def scrape_school(self, school_name: str, website_url: str, team_id: str = "") -> Dict:
        """Scrape coach emails from school website"""

        print(f"\n{'='*80}")
        print(f"🏊 Scraping: {school_name}")
        print(f"🌐 URL: {website_url}")
        print(f"{'='*80}")

        result = {
            'school_name': school_name,
            'team_id': team_id,
            'website_url': website_url,
            'coaches': [],
            'all_emails': [],
            'pages_checked': [],
            'status': 'success',
            'error_message': '',
            'timestamp': datetime.now().isoformat()
        }

        if not website_url or website_url.strip() == '':
            result['status'] = 'skipped'
            result['error_message'] = 'No website URL'
            print("  ⏭️  Skipped: No URL")
            return result

        try:
            # Find staff pages
            print("  🔍 Finding staff pages...")
            staff_pages = self.find_staff_pages(website_url)
            print(f"  📄 Found {len(staff_pages)} page(s) to check")

            all_email_data = []

            # Scrape each page
            for i, page_url in enumerate(staff_pages, 1):
                print(f"  📖 Checking page {i}/{len(staff_pages)}...")
                email_data = self.scrape_page_with_context(page_url)

                if email_data:
                    print(f"    ✅ Found {len(email_data)} email(s)")
                    all_email_data.extend(email_data)
                    result['pages_checked'].append(page_url)

                time.sleep(1.5)  # Be respectful

            # Process results
            result['coaches'] = all_email_data
            result['all_emails'] = list(set([item['email'] for item in all_email_data]))

            if result['all_emails']:
                print(f"  🎉 Total unique emails: {len(result['all_emails'])}")
                for email in result['all_emails']:
                    print(f"    📧 {email}")
            else:
                print("  ⚠️  No emails found")
                result['status'] = 'no_emails'

        except Exception as e:
            result['status'] = 'error'
            result['error_message'] = str(e)
            print(f"  ❌ Error: {str(e)[:100]}")
            self.errors.append(result)

        return result

    def process_csv_file(self, csv_path: str) -> List[Dict]:
        """Process schools from CSV file"""

        print(f"\n{'#'*80}")
        print(f"📁 Processing: {os.path.basename(csv_path)}")
        print(f"{'#'*80}")

        results = []

        try:
            with open(csv_path, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                schools = list(reader)

            print(f"📊 Found {len(schools)} schools")

            for i, school in enumerate(schools, 1):
                school_name = school.get('name', f'Unknown {i}')
                website_url = school.get('website_url', '').strip()
                team_id = school.get('team_id', '')

                print(f"\n[{i}/{len(schools)}]")

                result = self.scrape_school(school_name, website_url, team_id)
                results.append(result)

                # Save progress periodically
                if i % 5 == 0:
                    self.save_results(results, f"progress_{os.path.basename(csv_path).replace('.csv', '')}")

                time.sleep(2)  # Delay between schools

        except Exception as e:
            print(f"❌ Error processing file: {str(e)}")
            self.errors.append({'file': csv_path, 'error': str(e)})

        return results

    def process_all_files(self, data_folder: str = 'data') -> List[Dict]:
        """Process all CSV files in data folder"""

        print(f"\n{'='*80}")
        print(f"🚀 Advanced Coach Email Scraper")
        print(f"📂 Folder: {data_folder}")
        print(f"🤖 Selenium: {'Enabled' if self.use_selenium else 'Disabled'}")
        print(f"{'='*80}")

        all_results = []

        # Find CSV files
        csv_files = [
            os.path.join(data_folder, f)
            for f in os.listdir(data_folder)
            if f.endswith('.csv') and 'schools_info' in f
        ]

        print(f"\n📋 Found {len(csv_files)} file(s):")
        for f in csv_files:
            print(f"  • {os.path.basename(f)}")

        # Process each file
        for csv_file in csv_files:
            results = self.process_csv_file(csv_file)
            all_results.extend(results)

        self.results = all_results
        return all_results

    def save_results(self, results: List[Dict], suffix: str = ""):
        """Save results to files"""

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        base_name = f"coach_emails_advanced_{suffix}_{timestamp}" if suffix else f"coach_emails_advanced_{timestamp}"

        # Save CSV
        csv_file = f"{base_name}.csv"
        try:
            with open(csv_file, 'w', newline='', encoding='utf-8') as f:
                fieldnames = ['school_name', 'team_id', 'website_url', 'email',
                            'context', 'found_on', 'status', 'total_emails', 'timestamp']
                writer = csv.DictWriter(f, fieldnames=fieldnames)
                writer.writeheader()

                for result in results:
                    if result.get('coaches'):
                        for coach_data in result['coaches']:
                            writer.writerow({
                                'school_name': result['school_name'],
                                'team_id': result['team_id'],
                                'website_url': result['website_url'],
                                'email': coach_data['email'],
                                'context': coach_data['context'].strip().replace('\n', ' ')[:200],
                                'found_on': coach_data['found_on'],
                                'status': result['status'],
                                'total_emails': len(result['all_emails']),
                                'timestamp': result['timestamp']
                            })
                    else:
                        writer.writerow({
                            'school_name': result['school_name'],
                            'team_id': result['team_id'],
                            'website_url': result['website_url'],
                            'email': '',
                            'context': result.get('error_message', 'No emails found'),
                            'found_on': '',
                            'status': result['status'],
                            'total_emails': 0,
                            'timestamp': result['timestamp']
                        })

            print(f"\n💾 Saved: {csv_file}")
        except Exception as e:
            print(f"❌ Error saving CSV: {str(e)}")

        # Save JSON
        json_file = f"{base_name}.json"
        try:
            with open(json_file, 'w', encoding='utf-8') as f:
                json.dump(results, f, indent=2)
            print(f"💾 Saved: {json_file}")
        except Exception as e:
            print(f"❌ Error saving JSON: {str(e)}")

    def print_summary(self):
        """Print summary statistics"""

        print(f"\n{'='*80}")
        print(f"📊 SCRAPING SUMMARY")
        print(f"{'='*80}")

        total = len(self.results)
        with_emails = len([r for r in self.results if r.get('all_emails')])
        no_emails = len([r for r in self.results if r['status'] == 'no_emails'])
        errors = len([r for r in self.results if r['status'] == 'error'])
        skipped = len([r for r in self.results if r['status'] == 'skipped'])

        total_emails = sum(len(r.get('all_emails', [])) for r in self.results)
        total_coaches = sum(len(r.get('coaches', [])) for r in self.results)

        print(f"\n🏫 Total Schools: {total}")
        print(f"✅ With Emails: {with_emails}")
        print(f"⚠️  No Emails: {no_emails}")
        print(f"❌ Errors: {errors}")
        print(f"⏭️  Skipped: {skipped}")
        print(f"\n📧 Total Emails: {total_emails}")
        print(f"👤 Total Coach Records: {total_coaches}")
        print(f"📈 Avg per school: {total_emails/total if total > 0 else 0:.2f}")

def main():
    """Main execution"""

    # Ask user if they want to use Selenium
    use_selenium = False
    if SELENIUM_AVAILABLE:
        print("\n🤖 Selenium is available for JavaScript-heavy sites")
        print("⚠️  Note: Selenium is slower but handles dynamic content better")
        response = input("Use Selenium? (y/n): ").strip().lower()
        use_selenium = response == 'y'

    # Create scraper
    scraper = AdvancedCoachEmailScraper(use_selenium=use_selenium)

    try:
        # Process all files
        results = scraper.process_all_files('data')

        # Save results
        scraper.save_results(results)

        # Print summary
        scraper.print_summary()

    finally:
        # Cleanup
        scraper.cleanup()

    print(f"\n{'='*80}")
    print(f"✨ Scraping Complete!")
    print(f"{'='*80}\n")

if __name__ == "__main__":
    main()
