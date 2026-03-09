from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from bs4 import BeautifulSoup
import csv
import time
import os

BASE_URL = "https://www.swimcloud.com"

def setup_driver():
    """Setup Selenium Chrome driver with headless options"""
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument("--disable-blink-features=AutomationControlled")
    chrome_options.add_argument("user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
    return webdriver.Chrome(options=chrome_options)

def fetch_html(driver, url, wait_time=3):
    """Fetch HTML content from URL with retry logic"""
    max_retries = 3
    for attempt in range(max_retries):
        try:
            driver.get(url)
            time.sleep(wait_time)
            html = driver.page_source

            # Check if we got a 403 or other error
            if "403 Forbidden" in html or "Access Denied" in html:
                if attempt < max_retries - 1:
                    print(f"\n  Rate limited, waiting 10 seconds...", end="")
                    time.sleep(10)
                    continue
                else:
                    return None
            return html
        except Exception as e:
            if attempt < max_retries - 1:
                time.sleep(5)
                continue
            else:
                print(f"\n  Error: {e}")
                return None
    return None

def load_existing_data(filename):
    """Load existing data if file exists"""
    if not os.path.exists(filename):
        return []

    schools = []
    try:
        with open(filename, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            for row in reader:
                schools.append(row)
        print(f"✓ Loaded {len(schools)} existing schools from {filename}")
    except Exception as e:
        print(f"✗ Error loading existing data: {e}")

    return schools

def save_data(schools, filename):
    """Save data to CSV"""
    fieldnames = ["name", "team_id", "swimcloud_url", "website_url"]

    with open(filename, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for school in schools:
            writer.writerow(school)

def scrape_teams_list(driver, base_url, max_pages=None):
    """Scrape all teams from Division 1 listing pages"""
    teams = []
    page = 1

    print("\n" + "="*80)
    print("STEP 1: SCRAPING DIVISION 1 TEAMS LIST")
    print("="*80)

    while True:
        if max_pages and page > max_pages:
            break

        url = base_url.replace("page=1", f"page={page}")
        print(f"\nPage {page}: Loading...", end=" ", flush=True)

        html = fetch_html(driver, url, wait_time=3)

        if not html:
            print(f"Failed to load page, stopping.")
            break

        soup = BeautifulSoup(html, "html.parser")

        table = soup.find("table", class_="c-table-clean")
        if not table:
            print(f"No table found, stopping.")
            break

        tbody = table.find("tbody")
        if not tbody:
            print(f"No tbody found, stopping.")
            break

        rows = tbody.find_all("tr")
        if not rows:
            print(f"No rows found, stopping.")
            break

        for row in rows:
            cells = row.find_all("td")
            if len(cells) >= 1:
                team_cell = cells[0]
                team_link = team_cell.find("a")
                if team_link:
                    name = team_link.get_text(strip=True)
                    url = BASE_URL + team_link.get("href", "")
                    team_id = team_link.get("href", "").split("/")[-1] if team_link.get("href") else ""

                    teams.append({
                        "name": name,
                        "team_id": team_id,
                        "swimcloud_url": url,
                        "website_url": ""
                    })

        print(f"✓ Found {len(rows)} teams (Total: {len(teams)})")

        # Check for next page
        pagination = soup.find("ul", class_="c-pagination")
        if pagination:
            next_link = pagination.find("a", {"aria-label": "Next"})
            if next_link and "disabled" not in next_link.get("class", []):
                page += 1
                time.sleep(2)  # Longer delay between pages
            else:
                break
        else:
            break

    print(f"\n✓ Total teams scraped: {len(teams)}\n")
    return teams

def scrape_website_url(driver, team_url):
    """Scrape website URL from team's about page"""
    website_url = ""

    try:
        about_url = team_url.rstrip("/") + "/about/"
        html = fetch_html(driver, about_url, wait_time=2)

        if not html:
            return ""

        soup = BeautifulSoup(html, "html.parser")

        # Find website URL in dl elements
        dls = soup.find_all("dl", class_="c-dl")
        for dl in dls:
            dt = dl.find("dt")
            dd = dl.find("dd")
            if dt and dd:
                key = dt.get_text(strip=True).lower()
                if "website" in key:
                    link = dd.find("a")
                    if link:
                        website_url = link.get("href", "")
                        break
    except Exception as e:
        pass

    return website_url

def main():
    print("\n" + "="*80)
    print("SCHOOL WEBSITES SCRAPER - ALL DIVISION 1 SCHOOLS (ROBUST)")
    print("="*80)

    # CONFIGURATION
    TEAMS_URL = "https://www.swimcloud.com/country/usa/teams/?eventCourse=Y&gender=M&page=1&rankType=D&region=division_1&seasonId=29&sortBy=all"
    OUTPUT_FILE = "all_schools_websites.csv"

    # For testing: set MAX_PAGES to small number
    # For production: set to None to scrape everything
    MAX_PAGES = None  # Set to None to scrape all pages

    print(f"\nConfiguration:")
    print(f"  - Max pages: {MAX_PAGES if MAX_PAGES else 'ALL'}")
    print(f"  - Output file: {OUTPUT_FILE}")
    print(f"  - Region: Division 1")
    print()

    # Load existing data if available
    existing_schools = load_existing_data(OUTPUT_FILE)
    processed_ids = {s['team_id'] for s in existing_schools if s.get('website_url')}

    print(f"Already processed: {len(processed_ids)} schools\n")

    driver = setup_driver()

    try:
        # Step 1: Get all schools from listing
        schools = scrape_teams_list(driver, TEAMS_URL, max_pages=MAX_PAGES)

        if not schools:
            print("\n✗ No schools found. Exiting.")
            driver.quit()
            return

        print("="*80)
        print(f"STEP 2: SCRAPING WEBSITE URLs FOR {len(schools)} SCHOOLS")
        print("="*80)

        # Step 2: Scrape each school's website URL
        for i, school in enumerate(schools, 1):
            # Skip if already processed
            if school['team_id'] in processed_ids:
                # Find existing data
                for existing in existing_schools:
                    if existing['team_id'] == school['team_id']:
                        school['website_url'] = existing.get('website_url', '')
                        break
                print(f"\n[{i}/{len(schools)}] {school['name']} - Already processed ✓")
                continue

            print(f"\n[{i}/{len(schools)}] {school['name']}")
            print(f"  Getting website URL...", end=" ", flush=True)

            try:
                website_url = scrape_website_url(driver, school['swimcloud_url'])
                school['website_url'] = website_url

                if website_url:
                    print(f"✓")
                    print(f"  → {website_url}")
                else:
                    print(f"✗ Not found")

                # Save after each school (checkpoint)
                if i % 10 == 0:  # Save every 10 schools
                    save_data(schools, OUTPUT_FILE)
                    print(f"\n  [Checkpoint: Saved progress for {i} schools]")

            except Exception as e:
                print(f"✗ Error: {e}")
                school['website_url'] = ""

            time.sleep(1.5)  # Delay between schools to avoid rate limiting

        # Final save
        print(f"\n{'='*80}")
        print("SAVING DATA")
        print("="*80)

        save_data(schools, OUTPUT_FILE)
        print(f"\n✓ Saved {len(schools)} schools to {OUTPUT_FILE}")

        # Statistics
        schools_with_website = sum(1 for s in schools if s.get('website_url'))
        schools_without_website = len(schools) - schools_with_website

        print(f"\nStatistics:")
        print(f"  - Schools with website: {schools_with_website}")
        print(f"  - Schools without website: {schools_without_website}")
        print(f"  - Total schools: {len(schools)}")

    except KeyboardInterrupt:
        print("\n\n✗ Interrupted by user. Saving progress...")
        save_data(schools, OUTPUT_FILE)
        print(f"✓ Progress saved to {OUTPUT_FILE}")
    except Exception as e:
        print(f"\n✗ Fatal error: {e}")
        import traceback
        traceback.print_exc()
        # Try to save what we have
        try:
            save_data(schools, OUTPUT_FILE)
            print(f"✓ Partial data saved to {OUTPUT_FILE}")
        except:
            pass
    finally:
        driver.quit()

    print("\n" + "="*80)
    print("ALL DONE! 🏊‍♂️")
    print("="*80)
    print(f"\nYour data is ready in: {OUTPUT_FILE}")
    print("="*80 + "\n")

if __name__ == "__main__":
    main()
