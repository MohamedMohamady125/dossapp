"""
School Logo Downloader
Downloads all school logos from CSV files and saves them locally
"""

import csv
import requests
import os
from pathlib import Path
import time
from urllib.parse import urlparse
import re
from datetime import datetime

class LogoDownloader:
    """Downloads school logos from CSV files"""

    def __init__(self, output_folder='logos'):
        self.output_folder = output_folder
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
        })

        # Create output folder
        Path(self.output_folder).mkdir(parents=True, exist_ok=True)

        self.stats = {
            'total': 0,
            'downloaded': 0,
            'skipped': 0,
            'failed': 0
        }

    def sanitize_filename(self, name):
        """Convert school name to safe filename"""
        # Remove special characters, keep alphanumeric and spaces
        safe_name = re.sub(r'[^\w\s-]', '', name)
        # Replace spaces with underscores
        safe_name = re.sub(r'\s+', '_', safe_name)
        # Remove multiple underscores
        safe_name = re.sub(r'_+', '_', safe_name)
        return safe_name.strip('_')

    def get_file_extension(self, url):
        """Extract file extension from URL"""
        parsed = urlparse(url)
        path = parsed.path

        # Common image extensions
        for ext in ['.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp']:
            if ext in path.lower():
                return ext

        # Default to .jpg if no extension found
        return '.jpg'

    def download_logo(self, school_name, logo_url, team_id=''):
        """Download a single logo"""

        if not logo_url or logo_url.strip() == '':
            print(f"  ⏭️  Skipped: No logo URL")
            self.stats['skipped'] += 1
            return None

        try:
            # Create filename
            safe_name = self.sanitize_filename(school_name)
            extension = self.get_file_extension(logo_url)

            # Use team_id if available for uniqueness
            if team_id:
                filename = f"{safe_name}_{team_id}{extension}"
            else:
                filename = f"{safe_name}{extension}"

            filepath = os.path.join(self.output_folder, filename)

            # Check if already downloaded
            if os.path.exists(filepath):
                print(f"  ✓  Already exists: {filename}")
                self.stats['skipped'] += 1
                return filepath

            # Download logo
            print(f"  📥 Downloading: {logo_url}")
            response = self.session.get(logo_url, timeout=15)
            response.raise_for_status()

            # Check if it's actually an image
            content_type = response.headers.get('content-type', '')
            if 'image' not in content_type.lower():
                print(f"  ⚠️  Not an image: {content_type}")
                self.stats['failed'] += 1
                return None

            # Save logo
            with open(filepath, 'wb') as f:
                f.write(response.content)

            file_size = len(response.content) / 1024  # KB
            print(f"  ✅ Downloaded: {filename} ({file_size:.1f} KB)")
            self.stats['downloaded'] += 1
            return filepath

        except requests.exceptions.RequestException as e:
            print(f"  ❌ Error downloading: {str(e)[:80]}")
            self.stats['failed'] += 1
            return None
        except Exception as e:
            print(f"  ❌ Error: {str(e)[:80]}")
            self.stats['failed'] += 1
            return None

    def process_csv_file(self, csv_path):
        """Process a single CSV file and download all logos"""

        print(f"\n{'='*80}")
        print(f"📁 Processing: {os.path.basename(csv_path)}")
        print(f"{'='*80}")

        downloaded_logos = []

        try:
            with open(csv_path, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f)
                schools = list(reader)

            print(f"📊 Found {len(schools)} schools\n")

            for i, school in enumerate(schools, 1):
                school_name = school.get('name', f'Unknown_{i}')
                logo_url = school.get('logo_url', '').strip()
                team_id = school.get('team_id', '')

                print(f"[{i}/{len(schools)}] {school_name}")

                self.stats['total'] += 1

                filepath = self.download_logo(school_name, logo_url, team_id)

                if filepath:
                    downloaded_logos.append({
                        'school_name': school_name,
                        'team_id': team_id,
                        'logo_url': logo_url,
                        'local_path': filepath,
                        'filename': os.path.basename(filepath)
                    })

                # Small delay to be respectful
                time.sleep(0.5)

        except Exception as e:
            print(f"❌ Error processing file: {str(e)}")

        return downloaded_logos

    def process_all_csv_files(self, data_folder='data'):
        """Process all schools_info CSV files in the data folder"""

        print(f"\n{'#'*80}")
        print(f"🚀 School Logo Downloader")
        print(f"📂 Data folder: {data_folder}")
        print(f"💾 Output folder: {self.output_folder}")
        print(f"{'#'*80}")

        all_logos = []

        # Find all schools_info CSV files
        csv_files = []
        if os.path.exists(data_folder):
            for filename in os.listdir(data_folder):
                if filename.endswith('.csv') and 'schools_info' in filename:
                    csv_files.append(os.path.join(data_folder, filename))

        if not csv_files:
            print(f"\n⚠️  No schools_info CSV files found in {data_folder}")
            return []

        print(f"\n📋 Found {len(csv_files)} CSV file(s) to process:")
        for csv_file in csv_files:
            print(f"  • {os.path.basename(csv_file)}")

        # Process each file
        for csv_file in csv_files:
            logos = self.process_csv_file(csv_file)
            all_logos.extend(logos)

        return all_logos

    def save_manifest(self, logos):
        """Save a manifest file with all downloaded logos"""

        manifest_file = os.path.join(self.output_folder, 'logos_manifest.csv')

        try:
            with open(manifest_file, 'w', newline='', encoding='utf-8') as f:
                if logos:
                    fieldnames = ['school_name', 'team_id', 'logo_url', 'local_path', 'filename']
                    writer = csv.DictWriter(f, fieldnames=fieldnames)
                    writer.writeheader()
                    writer.writerows(logos)

            print(f"\n💾 Manifest saved: {manifest_file}")
        except Exception as e:
            print(f"\n❌ Error saving manifest: {str(e)}")

    def print_summary(self):
        """Print download summary"""

        print(f"\n{'='*80}")
        print(f"📊 DOWNLOAD SUMMARY")
        print(f"{'='*80}")
        print(f"\n🏫 Total schools: {self.stats['total']}")
        print(f"✅ Downloaded: {self.stats['downloaded']}")
        print(f"⏭️  Skipped (already exist/no URL): {self.stats['skipped']}")
        print(f"❌ Failed: {self.stats['failed']}")
        print(f"\n📁 Logos saved to: {os.path.abspath(self.output_folder)}")

        if self.stats['downloaded'] > 0:
            print(f"\n✨ Successfully downloaded {self.stats['downloaded']} logo(s)!")

def main():
    """Main execution function"""

    # Create downloader
    downloader = LogoDownloader(output_folder='school_logos')

    # Process all CSV files
    logos = downloader.process_all_csv_files('data')

    # Save manifest
    if logos:
        downloader.save_manifest(logos)

    # Print summary
    downloader.print_summary()

    print(f"\n{'='*80}")
    print(f"✨ Logo download complete!")
    print(f"{'='*80}\n")

if __name__ == "__main__":
    main()
