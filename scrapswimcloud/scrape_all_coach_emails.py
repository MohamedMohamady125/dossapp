"""
Comprehensive Swimming Coach Email Scraper
Reads all CSV files from data folder and scrapes coaching staff emails from school websites
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

class CoachEmailScraper:
    """Scrapes swimming & diving coach emails from university websites"""

    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        })
        self.session.timeout = 10

        # Email regex pattern
        self.email_pattern = re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b')

        # Keywords for finding coach/staff pages
        self.staff_keywords = [
            'staff', 'coach', 'coaching', 'coaches', 'roster',
            'swimming-and-diving/staff', 'swimming/coaches',
            'swimming/staff', 'swim/coaches', 'swim/staff',
            'mens-swimming', 'womens-swimming'
        ]

        # Results storage
        self.results = []
        self.errors = []

    def extract_emails_from_text(self, text: str) -> List[str]:
        """Extract all email addresses from text"""
        return list(set(self.email_pattern.findall(text)))

    def is_valid_email(self, email: str) -> bool:
        """Filter out common non-personal emails"""
        invalid_patterns = [
            'example.com', 'test.com', 'noreply', 'no-reply',
            'webmaster', 'postmaster', 'admin@', 'info@',
            'support@', 'help@', 'contact@', 'sales@'
        ]
        email_lower = email.lower()
        return not any(pattern in email_lower for pattern in invalid_patterns)

    def find_coach_pages(self, base_url: str) -> List[str]:
        """Find potential coach/staff pages on the website"""
        potential_pages = []

        try:
            response = self.session.get(base_url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')

            # Find all links
            for link in soup.find_all('a', href=True):
                href = link.get('href', '').lower()
                link_text = link.get_text().lower()

                # Check if link matches staff/coach keywords
                for keyword in self.staff_keywords:
                    if keyword in href or keyword in link_text:
                        full_url = urljoin(base_url, link['href'])
                        if full_url not in potential_pages:
                            potential_pages.append(full_url)
                        break

            # If no specific pages found, use base URL
            if not potential_pages:
                potential_pages.append(base_url)

        except Exception as e:
            print(f"  ⚠️  Error finding coach pages: {str(e)[:100]}")
            potential_pages.append(base_url)

        return potential_pages[:5]  # Limit to first 5 pages

    def scrape_emails_from_page(self, url: str) -> List[str]:
        """Scrape emails from a specific page"""
        emails = []

        try:
            response = self.session.get(url, timeout=10)
            response.raise_for_status()

            # Get page content
            soup = BeautifulSoup(response.content, 'html.parser')
            page_text = soup.get_text()

            # Extract emails from text
            found_emails = self.extract_emails_from_text(page_text)

            # Also check mailto links
            for link in soup.find_all('a', href=True):
                if link['href'].startswith('mailto:'):
                    email = link['href'].replace('mailto:', '').split('?')[0]
                    found_emails.append(email)

            # Filter valid emails
            emails = [e for e in found_emails if self.is_valid_email(e)]

        except Exception as e:
            print(f"  ⚠️  Error scraping page: {str(e)[:100]}")

        return list(set(emails))

    def scrape_school_website(self, school_name: str, website_url: str, team_id: str = "") -> Dict:
        """Scrape all coach emails from a school's website"""

        print(f"\n{'='*80}")
        print(f"🏊 Scraping: {school_name}")
        print(f"🌐 URL: {website_url}")
        print(f"{'='*80}")

        result = {
            'school_name': school_name,
            'team_id': team_id,
            'website_url': website_url,
            'emails_found': [],
            'pages_checked': [],
            'status': 'success',
            'error_message': '',
            'timestamp': datetime.now().isoformat()
        }

        if not website_url or website_url == '':
            result['status'] = 'skipped'
            result['error_message'] = 'No website URL provided'
            print("  ⏭️  Skipped: No URL")
            return result

        try:
            # Find coach/staff pages
            print("  🔍 Finding coach pages...")
            coach_pages = self.find_coach_pages(website_url)
            print(f"  📄 Found {len(coach_pages)} potential page(s)")

            all_emails = []

            # Scrape each page
            for i, page_url in enumerate(coach_pages, 1):
                print(f"  📖 Checking page {i}/{len(coach_pages)}...")
                emails = self.scrape_emails_from_page(page_url)

                if emails:
                    print(f"    ✅ Found {len(emails)} email(s)")
                    all_emails.extend(emails)
                    result['pages_checked'].append(page_url)

                time.sleep(1)  # Be respectful to servers

            # Remove duplicates
            result['emails_found'] = list(set(all_emails))

            if result['emails_found']:
                print(f"  🎉 Total emails found: {len(result['emails_found'])}")
                for email in result['emails_found']:
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
        """Process a single CSV file and scrape emails"""

        print(f"\n{'#'*80}")
        print(f"📁 Processing file: {os.path.basename(csv_path)}")
        print(f"{'#'*80}")

        results = []

        try:
            with open(csv_path, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                schools = list(reader)

            print(f"📊 Found {len(schools)} schools in file")

            for i, school in enumerate(schools, 1):
                school_name = school.get('name', f'Unknown School {i}')
                website_url = school.get('website_url', '')
                team_id = school.get('team_id', '')

                print(f"\n[{i}/{len(schools)}]")

                result = self.scrape_school_website(school_name, website_url, team_id)
                results.append(result)

                # Save progress every 10 schools
                if i % 10 == 0:
                    self.save_results(results, f"progress_{os.path.basename(csv_path)}")

                # Delay between requests
                time.sleep(2)

        except Exception as e:
            print(f"❌ Error processing file {csv_path}: {str(e)}")
            self.errors.append({
                'file': csv_path,
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            })

        return results

    def process_data_folder(self, folder_path: str = 'data') -> List[Dict]:
        """Process all CSV files in the data folder"""

        print(f"\n{'='*80}")
        print(f"🚀 Starting Coach Email Scraping Process")
        print(f"📂 Data folder: {folder_path}")
        print(f"{'='*80}")

        all_results = []

        # Find all CSV files in data folder
        csv_files = []
        for filename in os.listdir(folder_path):
            if filename.endswith('.csv') and 'schools_info' in filename:
                csv_files.append(os.path.join(folder_path, filename))

        print(f"\n📋 Found {len(csv_files)} CSV files to process:")
        for csv_file in csv_files:
            print(f"  • {os.path.basename(csv_file)}")

        # Process each file
        for csv_file in csv_files:
            results = self.process_csv_file(csv_file)
            all_results.extend(results)

        self.results = all_results
        return all_results

    def save_results(self, results: List[Dict], filename_suffix: str = ""):
        """Save results to CSV and JSON files"""

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        if filename_suffix:
            base_name = f"coach_emails_{filename_suffix}_{timestamp}"
        else:
            base_name = f"coach_emails_{timestamp}"

        # Save as CSV
        csv_filename = f"{base_name}.csv"
        try:
            with open(csv_filename, 'w', newline='', encoding='utf-8') as f:
                if results:
                    fieldnames = ['school_name', 'team_id', 'website_url', 'emails_found',
                                'pages_checked', 'status', 'error_message', 'timestamp']
                    writer = csv.DictWriter(f, fieldnames=fieldnames)
                    writer.writeheader()

                    for result in results:
                        row = result.copy()
                        # Convert lists to strings for CSV
                        row['emails_found'] = '; '.join(result['emails_found'])
                        row['pages_checked'] = '; '.join(result['pages_checked'])
                        writer.writerow(row)

            print(f"\n💾 Results saved to: {csv_filename}")
        except Exception as e:
            print(f"❌ Error saving CSV: {str(e)}")

        # Save as JSON
        json_filename = f"{base_name}.json"
        try:
            with open(json_filename, 'w', encoding='utf-8') as f:
                json.dump(results, f, indent=2)

            print(f"💾 Results saved to: {json_filename}")
        except Exception as e:
            print(f"❌ Error saving JSON: {str(e)}")

    def print_summary(self):
        """Print summary statistics"""

        print(f"\n{'='*80}")
        print(f"📊 SCRAPING SUMMARY")
        print(f"{'='*80}")

        total_schools = len(self.results)
        successful = len([r for r in self.results if r['status'] == 'success' and r['emails_found']])
        no_emails = len([r for r in self.results if r['status'] == 'no_emails'])
        errors = len([r for r in self.results if r['status'] == 'error'])
        skipped = len([r for r in self.results if r['status'] == 'skipped'])

        total_emails = sum(len(r['emails_found']) for r in self.results)

        print(f"\n🏫 Total Schools Processed: {total_schools}")
        print(f"✅ Successful (with emails): {successful}")
        print(f"⚠️  No emails found: {no_emails}")
        print(f"❌ Errors: {errors}")
        print(f"⏭️  Skipped: {skipped}")
        print(f"\n📧 Total Emails Found: {total_emails}")
        print(f"📈 Average emails per school: {total_emails/total_schools if total_schools > 0 else 0:.2f}")

        if self.errors:
            print(f"\n❌ Errors encountered:")
            for error in self.errors[:5]:  # Show first 5 errors
                print(f"  • {error.get('school_name', error.get('file', 'Unknown'))}: {error.get('error_message', error.get('error', ''))[:100]}")

def main():
    """Main execution function"""

    # Create scraper instance
    scraper = CoachEmailScraper()

    # Process all files in data folder
    results = scraper.process_data_folder('data')

    # Save final results
    scraper.save_results(results)

    # Print summary
    scraper.print_summary()

    print(f"\n{'='*80}")
    print(f"✨ Scraping completed!")
    print(f"{'='*80}\n")

if __name__ == "__main__":
    main()
