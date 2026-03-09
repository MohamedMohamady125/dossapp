"""
Swimming & Diving Coach Email Scraper
Specifically scrapes coach emails from university swimming/diving team websites
Targets official swim and dive staff pages only
"""

import csv
import requests
from bs4 import BeautifulSoup
import time
from urllib.parse import urljoin, urlparse
import re
from typing import List, Dict, Optional

class SwimDiveCoachScraper:
    """Scrapes swimming & diving coach emails from university websites"""
    
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
        })
        self.email_pattern = re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b')
        
        # Swimming/Diving specific keywords
        self.swim_keywords = [
            'swimming', 'swim team', 'mswim', 'swimming and diving',
            'aquatics', 'pool', 'swimmer'
        ]
        self.dive_keywords = ['diving', 'dive team']
        self.staff_keywords = ['staff', 'coach', 'coaching staff', 'coaches']
        
    def scrape_school(self, school_name: str, main_website: str, swim_page: str = None, dive_page: str = None) -> Dict:
        """
        Scrape coach information from a school's swimming/diving pages
        
        Args:
            school_name: Name of the school
            main_website: Main athletic website URL
            swim_page: Specific URL to swimming team page (optional)
            dive_page: Specific URL to diving team page (optional)
            
        Returns:
            Dictionary with school info and coaches
        """
        print(f"\n{'='*70}")
        print(f"🏊 Scraping: {school_name}")
        print(f"{'='*70}")
        
        school_data = {
            'school_name': school_name,
            'main_website': main_website,
            'swim_page': swim_page,
            'dive_page': dive_page,
            'coaches': [],
            'status': 'pending'
        }
        
        all_coaches = []
        
        # Try swimming page first
        if swim_page:
            print(f"📍 Checking Swimming page: {swim_page}")
            swim_coaches = self._scrape_swim_page(swim_page)
            all_coaches.extend(swim_coaches)
            if swim_coaches:
                print(f"   ✅ Found {len(swim_coaches)} swimming coach(es)")
        
        # Try diving page
        if dive_page:
            print(f"📍 Checking Diving page: {dive_page}")
            dive_coaches = self._scrape_dive_page(dive_page)
            all_coaches.extend(dive_coaches)
            if dive_coaches:
                print(f"   ✅ Found {len(dive_coaches)} diving coach(es)")
        
        # If no specific pages provided, search main website
        if not swim_page and not dive_page:
            print(f"📍 Searching main website for swimming/diving pages...")
            discovered_coaches = self._find_swim_pages_on_website(main_website)
            all_coaches.extend(discovered_coaches)
            if discovered_coaches:
                print(f"   ✅ Found {len(discovered_coaches)} coach(es) from discovered pages")
        
        # Remove duplicates (same email)
        unique_coaches = {}
        for coach in all_coaches:
            email = coach.get('email', '').lower()
            if email and email not in unique_coaches:
                unique_coaches[email] = coach
        
        school_data['coaches'] = list(unique_coaches.values())
        school_data['status'] = 'success' if school_data['coaches'] else 'no_coaches_found'
        
        if not school_data['coaches']:
            print(f"   ⚠️  No coaches found")
        else:
            print(f"   ✅ Total coaches found: {len(school_data['coaches'])}")
        
        time.sleep(2)  # Be respectful with requests
        return school_data
    
    def _scrape_swim_page(self, url: str) -> List[Dict]:
        """Scrape swimming team staff page"""
        coaches = []
        
        try:
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')
            
            coaches = self._extract_coaches_from_page(soup, url, 'swimming')
            
        except requests.exceptions.RequestException as e:
            print(f"   ❌ Error accessing swimming page: {str(e)}")
        
        time.sleep(1)
        return coaches
    
    def _scrape_dive_page(self, url: str) -> List[Dict]:
        """Scrape diving team staff page"""
        coaches = []
        
        try:
            response = self.session.get(url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')
            
            coaches = self._extract_coaches_from_page(soup, url, 'diving')
            
        except requests.exceptions.RequestException as e:
            print(f"   ❌ Error accessing diving page: {str(e)}")
        
        time.sleep(1)
        return coaches
    
    def _find_swim_pages_on_website(self, base_url: str) -> List[Dict]:
        """Search website for swimming/diving team pages"""
        coaches = []
        swim_links = []
        
        try:
            response = self.session.get(base_url, timeout=10)
            response.raise_for_status()
            soup = BeautifulSoup(response.content, 'html.parser')
            
            # Find links related to swimming/diving
            for link in soup.find_all('a', href=True):
                href = link.get('href', '').lower()
                text = link.get_text().lower()
                
                # Check if link is related to swimming or diving
                is_swim = any(keyword in href or keyword in text for keyword in self.swim_keywords)
                is_dive = any(keyword in href or keyword in text for keyword in self.dive_keywords)
                
                if (is_swim or is_dive) and len(swim_links) < 5:
                    full_url = urljoin(base_url, link['href'])
                    
                    # Only follow links from the same domain
                    if urlparse(full_url).netloc == urlparse(base_url).netloc:
                        swim_links.append(full_url)
            
            # Scrape discovered links
            for swim_link in swim_links:
                try:
                    response = self.session.get(swim_link, timeout=10)
                    response.raise_for_status()
                    page_soup = BeautifulSoup(response.content, 'html.parser')
                    
                    page_coaches = self._extract_coaches_from_page(page_soup, swim_link, 'swimming/diving')
                    coaches.extend(page_coaches)
                    
                    time.sleep(1)
                except:
                    continue
        
        except requests.exceptions.RequestException as e:
            print(f"   ❌ Error searching website: {str(e)}")
        
        return coaches
    
    def _extract_coaches_from_page(self, soup: BeautifulSoup, url: str, team_type: str = 'swimming') -> List[Dict]:
        """Extract coach information from page content"""
        coaches = []
        
        # Strategy 1: Look for staff cards/sections
        staff_sections = soup.find_all(['div', 'section', 'article'], 
                                       class_=re.compile('staff|coach|person|profile|bio', re.I))
        
        for section in staff_sections:
            coach_info = self._parse_coach_section(section, url, team_type)
            if coach_info:
                coaches.append(coach_info)
        
        # Strategy 2: Look for contact information with emails
        if not coaches:
            coaches = self._extract_from_contact_info(soup, url, team_type)
        
        # Strategy 3: Look for specific patterns
        if not coaches:
            coaches = self._extract_from_text_patterns(soup, url, team_type)
        
        return coaches[:10]  # Limit to 10 coaches per page
    
    def _parse_coach_section(self, section, url: str, team_type: str) -> Optional[Dict]:
        """Parse individual coach entry from structured data"""
        try:
            text = section.get_text(separator=' | ', strip=True)
            
            # Look for email
            email_match = self.email_pattern.search(text)
            if not email_match:
                return None
            
            email = email_match.group(0)
            
            # Extract name - usually first line or in a heading
            name_elem = section.find(['h1', 'h2', 'h3', 'h4', 'strong', 'b'])
            name = name_elem.get_text(strip=True) if name_elem else 'Coach'
            
            # Extract title/position
            title_elem = section.find(text=re.compile('coach|head|assistant|diving', re.I))
            if title_elem:
                title = title_elem.strip()
            else:
                # Try to find title near email
                lines = text.split('|')
                title = lines[1].strip() if len(lines) > 1 else f'{team_type.title()} Coach'
            
            return {
                'name': name.strip() if name else 'Coach',
                'email': email,
                'title': title.strip() if title else f'{team_type.title()} Coach',
                'team_type': team_type,
                'url': url
            }
        except:
            return None
    
    def _extract_from_contact_info(self, soup: BeautifulSoup, url: str, team_type: str) -> List[Dict]:
        """Extract coaches from contact/staff sections"""
        coaches = []
        
        # Look for contact sections
        contact_headers = soup.find_all(text=re.compile('contact|staff|coaching', re.I))
        
        for header in contact_headers:
            parent = header.find_parent(['div', 'section', 'article'])
            if parent:
                text = parent.get_text()
                
                # Find all emails in this section
                emails = self.email_pattern.findall(text)
                
                # Look for names before/after emails
                lines = text.split('\n')
                
                for email in set(emails):
                    # Find name near email
                    name = 'Coach'
                    for i, line in enumerate(lines):
                        if email in line:
                            # Check lines above for name
                            if i > 0:
                                potential_name = lines[i-1].strip()
                                if potential_name and not any(c.isdigit() for c in potential_name):
                                    name = potential_name
                            break
                    
                    coaches.append({
                        'name': name,
                        'email': email,
                        'title': f'{team_type.title()} Coach',
                        'team_type': team_type,
                        'url': url
                    })
        
        return coaches
    
    def _extract_from_text_patterns(self, soup: BeautifulSoup, url: str, team_type: str) -> List[Dict]:
        """Extract coaches using text pattern matching"""
        coaches = []
        
        text = soup.get_text()
        emails = self.email_pattern.findall(text)
        
        for email in set(emails):
            # Only include emails that seem like they belong to the school
            if '@' in email:
                domain = email.split('@')[1]
                # Validate it's a university email
                coaches.append({
                    'name': email.split('@')[0].replace('.', ' ').title(),
                    'email': email,
                    'title': f'{team_type.title()} Coach',
                    'team_type': team_type,
                    'url': url
                })
        
        return coaches[:5]
    
    def scrape_all_schools(self, schools_csv: str) -> List[Dict]:
        """
        Scrape all schools from CSV file
        
        CSV format:
        school_name,main_website,swim_page,dive_page
        
        Example:
        University of Texas,https://texassports.com,https://texassports.com/sports/mswim,https://texassports.com/sports/diving
        
        Args:
            schools_csv: Path to CSV file with school data
            
        Returns:
            List of school data with coaches
        """
        all_results = []
        
        try:
            with open(schools_csv, 'r') as f:
                reader = csv.DictReader(f)
                schools = list(reader)
        except FileNotFoundError:
            print(f"❌ File not found: {schools_csv}")
            return []
        
        print(f"\n{'='*70}")
        print(f"🏊 Swimming & Diving Coach Email Scraper")
        print(f"{'='*70}")
        print(f"Starting to scrape {len(schools)} schools...")
        print(f"{'='*70}\n")
        
        for i, school in enumerate(schools, 1):
            school_name = school.get('school_name', 'Unknown')
            main_website = school.get('main_website', '')
            swim_page = school.get('swim_page', '')
            dive_page = school.get('dive_page', '')
            
            if main_website:
                result = self.scrape_school(school_name, main_website, swim_page, dive_page)
                all_results.append(result)
            
            print(f"\n📊 Progress: {i}/{len(schools)}")
        
        return all_results
    
    def save_results_to_csv(self, results: List[Dict], output_file: str = 'swim_dive_coaches.csv'):
        """Save scraping results to CSV file"""
        print(f"\n{'='*70}")
        print(f"💾 Saving results to {output_file}...")
        print(f"{'='*70}\n")
        
        with open(output_file, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            writer.writerow(['School', 'Coach Name', 'Email', 'Title', 'Team Type', 'Status'])
            
            for school_result in results:
                school_name = school_result['school_name']
                status = school_result['status']
                
                if school_result['coaches']:
                    for coach in school_result['coaches']:
                        writer.writerow([
                            school_name,
                            coach.get('name', 'N/A'),
                            coach.get('email', 'N/A'),
                            coach.get('title', 'N/A'),
                            coach.get('team_type', 'N/A'),
                            'success'
                        ])
                else:
                    writer.writerow([
                        school_name,
                        'N/A',
                        'N/A',
                        'N/A',
                        'N/A',
                        status
                    ])
        
        print(f"✅ Results saved to {output_file}\n")
        
        # Print summary
        total_coaches = sum(len(r['coaches']) for r in results)
        successful = sum(1 for r in results if r['status'] == 'success')
        
        print(f"{'='*70}")
        print(f"📊 Scraping Summary:")
        print(f"{'='*70}")
        print(f"   Total Schools: {len(results)}")
        print(f"   Successful: {successful}")
        print(f"   Total Coaches Found: {total_coaches}")
        print(f"   Average per School: {total_coaches / len(results) if results else 0:.1f}")
        print(f"{'='*70}\n")
    
    def print_sample_results(self, results: List[Dict], num_schools: int = 3):
        """Print sample results to console"""
        print(f"\n{'='*70}")
        print(f"📝 Sample Results (first {num_schools} schools):")
        print(f"{'='*70}\n")
        
        for result in results[:num_schools]:
            print(f"🏫 {result['school_name']}:")
            if result['coaches']:
                for coach in result['coaches'][:3]:
                    print(f"   • {coach['name']}")
                    print(f"     📧 {coach['email']}")
                    print(f"     🎯 {coach['title']}")
                    print()
            else:
                print(f"   ⚠️  No coaches found\n")

def main():
    """Main entry point"""
    import sys
    
    # Check command line arguments
    if len(sys.argv) > 1:
        csv_file = sys.argv[1]
    else:
        csv_file = 'schools_info.csv'
    
    print("\n🏊 Swimming & Diving Coach Email Scraper\n")
    
    # Create scraper
    scraper = SwimDiveCoachScraper()
    
    # Scrape all schools
    results = scraper.scrape_all_schools(csv_file)
    
    # Save results
    if results:
        scraper.save_results_to_csv(results, 'swim_dive_coaches.csv')
        scraper.print_sample_results(results)

if __name__ == '__main__':
    main()