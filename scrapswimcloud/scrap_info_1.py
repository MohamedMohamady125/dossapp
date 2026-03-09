from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from bs4 import BeautifulSoup
import csv
import time
import re

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
        print("✓")
        soup = BeautifulSoup(html, "html.parser")

        table = soup.find("table", class_="c-table-clean")
        if not table:
            print(f"  No table found, stopping.")
            break

        tbody = table.find("tbody")
        if not tbody:
            print(f"  No tbody found, stopping.")
            break

        rows = tbody.find_all("tr")
        if not rows:
            print(f"  No rows found, stopping.")
            break

        for idx, row in enumerate(rows, 1):
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

        print(f"  ✓ Found {len(rows)} teams")

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

def determine_school_type(description, school_name, website_url):
    """
    Determine if a school is public or private based on available information.
    Returns: 'Public', 'Private', or 'Unknown'
    """
    if not description:
        description = ""

    # Convert to lowercase for easier matching
    desc_lower = description.lower()
    name_lower = school_name.lower()

    # Known public universities (comprehensive list of common Division 1 public schools)
    public_schools = [
        'arizona state', 'auburn', 'ball state', 'binghamton', 'cal state',
        'california state', 'cleveland state', 'eastern illinois', 'florida atlantic',
        'florida state', 'george mason', 'georgia tech', 'howard', 'indiana',
        'louisiana state', 'lsu', 'miami-oh', 'michigan state', 'missouri state',
        'north carolina state', 'northern iowa', 'ohio state', 'penn state',
        'rutgers', 'san diego state', 'tennessee', 'texas', 'texas a&m',
        'uc berkeley', 'uc davis', 'uc irvine', 'uc san diego', 'uc santa barbara',
        'ucla', 'uconn', 'connecticut', 'florida', 'georgia', 'illinois',
        'iowa', 'iowa state', 'kansas', 'kentucky', 'maryland', 'michigan',
        'minnesota', 'missouri', 'nebraska', 'north carolina', 'oklahoma',
        'oregon', 'oregon state', 'purdue', 'south carolina', 'virginia',
        'virginia tech', 'washington', 'west virginia', 'wisconsin',
        'pittsburgh', 'cincinnati', 'houston', 'ucf', 'central florida',
        'memphis', 'temple', 'tulane', 'smu', 'akron', 'buffalo',
        'bowling green', 'kent state', 'miami (ohio)', 'ohio', 'toledo',
        'umass', 'massachusetts', 'rhode island', 'vermont', 'new hampshire',
        'maine', 'albany', 'stony brook', 'delaware', 'towson', 'william & mary',
        'old dominion', 'james madison', 'georgia southern', 'coastal carolina',
        'appalachian state', 'arkansas state', 'louisiana-lafayette', 'louisiana-monroe',
        'south alabama', 'texas state', 'troy', 'unt', 'north texas',
        'utsa', 'utep', 'fiu', 'fau', 'wyoming', 'new mexico', 'nevada',
        'unlv', 'fresno state', 'san jose state', 'colorado state', 'utah state',
        'boise state', 'hawaii', 'air force', 'army', 'navy', 'iupui', 'iu-indianapolis'
    ]

    # Known private universities (comprehensive list)
    private_schools = [
        'harvard', 'yale', 'princeton', 'brown', 'columbia', 'cornell',
        'dartmouth', 'penn', 'pennsylvania', 'notre dame', 'duke', 'stanford',
        'northwestern', 'vanderbilt', 'rice', 'emory', 'georgetown', 'boston college',
        'boston university', 'northeastern', 'brandeis', 'tufts', 'wake forest',
        'miami', 'syracuse', 'tulsa', 'loyola', 'fordham', 'drexel', 'hofstra',
        'st. john', 'seton hall', 'providence', 'villanova', 'marquette', 'depaul',
        'xavier', 'butler', 'creighton', 'belmont', 'lipscomb', 'campbell',
        'davidson', 'furman', 'wofford', 'charleston', 'presbyterian', 'high point',
        'bucknell', 'colgate', 'holy cross', 'lafayette', 'lehigh', 'american',
        'navy', 'army', 'air force', 'denver', 'baylor', 'tcu', 'smu',
        'pepperdine', 'brigham young', 'byu', 'gonzaga', 'saint mary',
        'loyola marymount', 'santa clara', 'san diego', 'pacific',
        'baptist', 'methodist', 'liberty', 'oral roberts', 'biola',
        'california baptist', 'grand canyon', 'seattle', 'chicago',
        'carnegie mellon', 'case western', 'johns hopkins', 'caltech', 'mit',
        'rensselaer', 'rochester', 'wash u', 'washington university',
        'iona', 'la salle', 'manhattan', 'marist', 'niagara', 'rider',
        'siena', 'canisius', 'fairfield', 'quinnipiac', 'sacred heart',
        'monmouth', 'wagner', 'liu', 'bryant', 'fairleigh dickinson',
        'merrimack', 'southern', 'bellarmine', 'le moyne', 'gardner-webb'
    ]

    # Check description first
    if desc_lower:
        public_indicators = [
            'state university', 'state college', 'public university',
            'public institution', 'state-supported', 'publicly funded',
            'public research university'
        ]
        private_indicators = [
            'private university', 'private college', 'private institution',
            'jesuit', 'catholic university', 'independent university'
        ]

        for indicator in public_indicators:
            if indicator in desc_lower:
                return "Public"
        for indicator in private_indicators:
            if indicator in desc_lower:
                return "Private"

    # Check against known schools lists
    for school in public_schools:
        if school in name_lower:
            return "Public"

    for school in private_schools:
        if school in name_lower:
            return "Private"

    # Check for "State" in name (usually indicates public)
    if ' state' in name_lower or name_lower.startswith('state '):
        return "Public"

    # Check for religious affiliations (usually private)
    religious_indicators = ['saint', 'st.', 'jesuit', 'catholic', 'christian',
                           'baptist', 'methodist', 'presbyterian', 'lutheran']
    for indicator in religious_indicators:
        if indicator in name_lower:
            return "Private"

    # Check for "University of [State]" pattern (usually public)
    if name_lower.startswith('university of ') or name_lower.startswith('college of '):
        return "Public"

    return "Unknown"

def scrape_school_info(driver, school):
    """Scrape website URL and school type for a single school"""
    data = {
        "name": school["name"],
        "team_id": school["team_id"],
        "swimcloud_url": school["url"],
        "website_url": "",
        "school_type": "Unknown",
        "description": ""
    }

    try:
        # Visit the about page
        about_url = school["url"].rstrip("/") + "/about/"
        html = fetch_html(driver, about_url)
        soup = BeautifulSoup(html, "html.parser")

        # Get website URL
        dls = soup.find_all("dl", class_="c-dl")
        for dl in dls:
            dt = dl.find("dt")
            dd = dl.find("dd")
            if dt and dd:
                key = dt.get_text(strip=True).lower()
                if "website" in key:
                    link = dd.find("a")
                    if link:
                        data["website_url"] = link.get("href", "")

        # Get description for school type determination
        desc_elem = soup.find("div", class_="c-wysiwyg")
        if desc_elem:
            # Get first paragraph as description
            first_p = desc_elem.find("p")
            if first_p:
                data["description"] = first_p.get_text(strip=True)

        # Determine school type
        data["school_type"] = determine_school_type(
            data["description"],
            school["name"],
            data["website_url"]
        )

    except Exception as e:
        print(f"    Error: {e}")

    return data

def main():
    print("\n" + "="*80)
    print("SCHOOL INFO SCRAPER - WEBSITE & SCHOOL TYPE")
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
    print(f"  - Source: {TEAMS_URL}\n")

    driver = setup_driver()

    try:
        # Step 1: Get all schools from listing
        schools = scrape_teams_list(driver, TEAMS_URL, max_pages=MAX_PAGES)

        if MAX_SCHOOLS:
            schools = schools[:MAX_SCHOOLS]

        print("="*80)
        print(f"STEP 2: SCRAPING SCHOOL INFO FOR {len(schools)} SCHOOLS")
        print("="*80)

        # Step 2: Scrape each school's info
        all_data = []
        for i, school in enumerate(schools, 1):
            print(f"\n[{i}/{len(schools)}] {school['name']}")
            print(f"  Fetching website and school type...", end=" ", flush=True)

            try:
                school_data = scrape_school_info(driver, school)
                all_data.append(school_data)
                print("✓")
                print(f"    Website: {school_data['website_url'] or 'Not found'}")
                print(f"    Type: {school_data['school_type']}")
            except Exception as e:
                print(f"\n  ✗ Error: {e}")
                all_data.append({
                    "name": school["name"],
                    "team_id": school["team_id"],
                    "swimcloud_url": school["url"],
                    "website_url": "",
                    "school_type": "Unknown",
                    "description": ""
                })
                continue

            time.sleep(1)  # Delay between schools

        # Save data
        print(f"\n{'='*80}")
        print("SAVING DATA")
        print("="*80)

        output_file = "schools_website_and_type.csv"
        fieldnames = ["name", "team_id", "swimcloud_url", "website_url", "school_type", "description"]

        with open(output_file, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for school in all_data:
                writer.writerow(school)

        print(f"\n✓ Saved {len(all_data)} schools to {output_file}")

        # Print statistics
        public_count = sum(1 for s in all_data if s["school_type"] == "Public")
        private_count = sum(1 for s in all_data if s["school_type"] == "Private")
        unknown_count = sum(1 for s in all_data if s["school_type"] == "Unknown")

        print(f"\nStatistics:")
        print(f"  - Public schools: {public_count}")
        print(f"  - Private schools: {private_count}")
        print(f"  - Unknown: {unknown_count}")
        print(f"  - Total: {len(all_data)}")

    except Exception as e:
        print(f"\n✗ Fatal error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        driver.quit()

    print("\n" + "="*80)
    print("ALL DONE! 🏊‍♂️")
    print("="*80)
    print(f"\nYour data is ready in: schools_website_and_type.csv")
    print("="*80 + "\n")

if __name__ == "__main__":
    main()
