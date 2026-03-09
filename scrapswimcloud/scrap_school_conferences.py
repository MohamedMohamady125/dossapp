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
    print("SCRAPING DIVISION 1 TEAMS LIST")
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
                        "url": url,
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

def scrape_conference(driver, team_url):
    """Scrape conference from main team page"""
    conference = ""

    try:
        html = fetch_html(driver, team_url, wait_time=1.5)
        soup = BeautifulSoup(html, "html.parser")

        meta = soup.find("div", class_="c-toolbar__meta")
        if meta:
            links = meta.find_all("a")
            for link in links:
                href = link.get("href", "")
                text = link.get_text(strip=True)
                if "/conference/" in href:
                    conference = text
                    break
    except Exception as e:
        pass

    return conference

def main():
    print("\n" + "="*80)
    print("SCHOOL CONFERENCES SCRAPER")
    print("="*80)

    # CONFIGURATION
    TEAMS_URL = "https://www.swimcloud.com/country/usa/teams/?eventCourse=Y&gender=M&page=1&rankType=D&region=division_1&seasonId=29&sortBy=all"

    # For testing: set MAX_PAGES to small number
    # For production: set to None to scrape everything
    MAX_PAGES = None  # Set to None to scrape all pages

    print(f"\nConfiguration:")
    print(f"  - Max pages: {MAX_PAGES if MAX_PAGES else 'ALL'}")
    print(f"  - Region: Division 1")
    print(f"  - Season: 2024-2025")

    driver = setup_driver()

    try:
        # Step 1: Get all schools from listing
        schools = scrape_teams_list(driver, TEAMS_URL, max_pages=MAX_PAGES)

        print("="*80)
        print(f"SCRAPING CONFERENCES FOR {len(schools)} SCHOOLS")
        print("="*80)

        # Step 2: Scrape each school's conference
        for i, school in enumerate(schools, 1):
            print(f"\n[{i}/{len(schools)}] {school['name']}")
            print(f"  Getting conference...", end=" ", flush=True)

            try:
                conference = scrape_conference(driver, school['url'])
                school['conference'] = conference

                if conference:
                    print(f"✓ {conference}")
                else:
                    print(f"✗ Not found")

            except Exception as e:
                print(f"✗ Error: {e}")
                school['conference'] = ""

            time.sleep(0.5)

        # Save data
        print(f"\n{'='*80}")
        print("SAVING DATA")
        print("="*80)

        output_file = "schools_conferences.csv"
        fieldnames = ["name", "conference"]

        with open(output_file, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for school in schools:
                writer.writerow({
                    "name": school["name"],
                    "conference": school["conference"]
                })

        print(f"\n✓ Saved {len(schools)} schools to {output_file}")

        # Statistics
        schools_with_conference = sum(1 for s in schools if s.get("conference"))
        schools_without_conference = len(schools) - schools_with_conference

        print(f"\nStatistics:")
        print(f"  - Schools with conference: {schools_with_conference}")
        print(f"  - Schools without conference: {schools_without_conference}")
        print(f"  - Total schools: {len(schools)}")

        # Count schools per conference
        conferences = {}
        for school in schools:
            conf = school.get("conference", "Unknown")
            if conf not in conferences:
                conferences[conf] = []
            conferences[conf].append(school["name"])

        print(f"\nConferences found: {len(conferences)}")
        for conf in sorted(conferences.keys()):
            if conf:
                print(f"  - {conf}: {len(conferences[conf])} schools")

    except Exception as e:
        print(f"\n✗ Fatal error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        driver.quit()

    print("\n" + "="*80)
    print("ALL DONE! 🏊‍♂️")
    print("="*80)
    print(f"\nYour data is ready in: schools_conferences.csv")
    print("="*80 + "\n")

if __name__ == "__main__":
    main()
