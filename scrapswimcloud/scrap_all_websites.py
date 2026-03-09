from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from bs4 import BeautifulSoup
import csv
import time

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

def fetch_html(driver, url, wait_time=2):
    """Fetch HTML content from URL"""
    driver.get(url)
    time.sleep(wait_time)
    return driver.page_source

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

        html = fetch_html(driver, url, wait_time=2)
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
                    })

        print(f"✓ Found {len(rows)} teams (Total: {len(teams)})")

        # Check for next page
        pagination = soup.find("ul", class_="c-pagination")
        if pagination:
            next_link = pagination.find("a", {"aria-label": "Next"})
            if next_link and "disabled" not in next_link.get("class", []):
                page += 1
                time.sleep(1)
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
        html = fetch_html(driver, about_url, wait_time=1.5)
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
        pass  # Return empty string if error

    return website_url

def main():
    print("\n" + "="*80)
    print("SCHOOL WEBSITES SCRAPER - ALL DIVISION 1 SCHOOLS")
    print("="*80)

    # CONFIGURATION
    TEAMS_URL = "https://www.swimcloud.com/country/usa/teams/?eventCourse=Y&gender=M&page=1&rankType=D&region=division_1&seasonId=29&sortBy=all"

    # For testing: set MAX_PAGES and MAX_SCHOOLS to small numbers
    # For production: set both to None to scrape everything
    MAX_PAGES = None       # Set to None to scrape all pages
    MAX_SCHOOLS = None     # Set to None to scrape all schools

    print(f"\nConfiguration:")
    print(f"  - Max pages: {MAX_PAGES if MAX_PAGES else 'ALL'}")
    print(f"  - Max schools: {MAX_SCHOOLS if MAX_SCHOOLS else 'ALL'}")
    print(f"  - Region: Division 1")
    print(f"  - Season: 2024-2025")
    print()

    driver = setup_driver()

    try:
        # Step 1: Get all schools from listing
        schools = scrape_teams_list(driver, TEAMS_URL, max_pages=MAX_PAGES)

        if MAX_SCHOOLS:
            schools = schools[:MAX_SCHOOLS]

        print("="*80)
        print(f"STEP 2: SCRAPING WEBSITE URLs FOR {len(schools)} SCHOOLS")
        print("="*80)

        # Step 2: Scrape each school's website URL
        for i, school in enumerate(schools, 1):
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

            except Exception as e:
                print(f"✗ Error: {e}")
                school['website_url'] = ""

            time.sleep(0.5)  # Small delay between schools

        # Save data
        print(f"\n{'='*80}")
        print("SAVING DATA")
        print("="*80)

        output_file = "all_schools_websites.csv"
        fieldnames = ["name", "team_id", "swimcloud_url", "website_url"]

        with open(output_file, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for school in schools:
                writer.writerow(school)

        print(f"\n✓ Saved {len(schools)} schools to {output_file}")

        # Statistics
        schools_with_website = sum(1 for s in schools if s.get("website_url"))
        schools_without_website = len(schools) - schools_with_website

        print(f"\nStatistics:")
        print(f"  - Schools with website: {schools_with_website}")
        print(f"  - Schools without website: {schools_without_website}")
        print(f"  - Total schools: {len(schools)}")

    except Exception as e:
        print(f"\n✗ Fatal error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        driver.quit()

    print("\n" + "="*80)
    print("ALL DONE! 🏊‍♂️")
    print("="*80)
    print(f"\nYour data is ready in: all_schools_websites.csv")
    print("="*80 + "\n")

if __name__ == "__main__":
    main()
