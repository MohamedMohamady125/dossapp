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

                    # Calculate overall rank (page position)
                    overall_rank = ((page - 1) * 50) + len(teams) + 1

                    teams.append({
                        "name": name,
                        "team_id": team_id,
                        "url": url,
                        "overall_division1_rank": overall_rank
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

def scrape_basic_info(driver, team_url):
    """Scrape division and conference from main team page"""
    data = {
        "division": "",
        "conference": "",
        "is_mid_major": False
    }

    try:
        html = fetch_html(driver, team_url)
        soup = BeautifulSoup(html, "html.parser")

        meta = soup.find("div", class_="c-toolbar__meta")
        if meta:
            links = meta.find_all("a")
            for link in links:
                href = link.get("href", "")
                text = link.get_text(strip=True)
                if "/division/" in href:
                    data["division"] = text
                    # Check if it's a mid-major division
                    if "mid-major" in text.lower() or "mid major" in text.lower():
                        data["is_mid_major"] = True
                elif "/conference/" in href:
                    data["conference"] = text
    except Exception as e:
        print(f"      Error: {e}")

    return data

def scrape_rankings(driver, team_url):
    """Scrape all rankings for a school (national, conference, mid-major)"""
    data = {
        "mens_national_ranking": "",
        "mens_conference_ranking": "",
        "mens_mid_major_ranking": "",
        "womens_national_ranking": "",
        "womens_conference_ranking": "",
        "womens_mid_major_ranking": ""
    }

    try:
        # Scrape men's rankings
        mens_rankings_url = team_url.rstrip("/") + "/rankings/?gender=M&season=29"
        html = fetch_html(driver, mens_rankings_url, wait_time=1.5)
        soup = BeautifulSoup(html, "html.parser")

        # Look for rankings in dl elements
        dls = soup.find_all("dl", class_="c-dl")
        for dl in dls:
            dt = dl.find("dt")
            dd = dl.find("dd")
            if dt and dd:
                key = dt.get_text(strip=True).lower()
                value = dd.get_text(strip=True)

                # Extract ranking number
                rank_match = re.search(r'#?(\d+)', value)
                rank_value = rank_match.group(1) if rank_match else ""

                if "national" in key and "rank" in key:
                    # Check if it specifies Division 1 or Mid-Major
                    if "mid-major" in value.lower() or "mid major" in value.lower():
                        data["mens_mid_major_ranking"] = rank_value
                    else:
                        data["mens_national_ranking"] = rank_value
                elif "conference" in key and "rank" in key:
                    data["mens_conference_ranking"] = rank_value
                elif "mid-major" in key or "mid major" in key:
                    data["mens_mid_major_ranking"] = rank_value

        # Scrape women's rankings
        womens_rankings_url = team_url.rstrip("/") + "/rankings/?gender=F&season=29"
        html = fetch_html(driver, womens_rankings_url, wait_time=1.5)
        soup = BeautifulSoup(html, "html.parser")

        dls = soup.find_all("dl", class_="c-dl")
        for dl in dls:
            dt = dl.find("dt")
            dd = dl.find("dd")
            if dt and dd:
                key = dt.get_text(strip=True).lower()
                value = dd.get_text(strip=True)

                # Extract ranking number
                rank_match = re.search(r'#?(\d+)', value)
                rank_value = rank_match.group(1) if rank_match else ""

                if "national" in key and "rank" in key:
                    # Check if it specifies Division 1 or Mid-Major
                    if "mid-major" in value.lower() or "mid major" in value.lower():
                        data["womens_mid_major_ranking"] = rank_value
                    else:
                        data["womens_national_ranking"] = rank_value
                elif "conference" in key and "rank" in key:
                    data["womens_conference_ranking"] = rank_value
                elif "mid-major" in key or "mid major" in key:
                    data["womens_mid_major_ranking"] = rank_value

    except Exception as e:
        print(f"      Error: {e}")

    return data

def scrape_school_rankings(driver, school):
    """Scrape complete ranking info for a single school"""
    data = {
        "name": school["name"],
        "team_id": school["team_id"],
        "swimcloud_url": school["url"],
        "overall_division1_rank": school.get("overall_division1_rank", "")
    }

    try:
        # Get basic info (division and conference)
        basic_info = scrape_basic_info(driver, school["url"])
        data.update(basic_info)

        # Calculate mid-major rank if applicable
        if basic_info.get("is_mid_major"):
            # We'll need to track mid-major schools separately
            data["mid_major_rank"] = ""  # Will be calculated later
        else:
            data["mid_major_rank"] = "N/A"

        # Get rankings from rankings page (though these might be empty)
        rankings = scrape_rankings(driver, school["url"])
        data.update(rankings)

    except Exception as e:
        print(f"    Error: {e}")

    return data

def main():
    print("\n" + "="*80)
    print("SCHOOL RANKINGS SCRAPER - DIVISION, CONFERENCE & MID-MAJOR RANKINGS")
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
    print(f"  - Season: 2024-2025 (ID: 29)")
    print(f"  - Source: {TEAMS_URL}\n")

    driver = setup_driver()

    try:
        # Step 1: Get all schools from listing
        schools = scrape_teams_list(driver, TEAMS_URL, max_pages=MAX_PAGES)

        if MAX_SCHOOLS:
            schools = schools[:MAX_SCHOOLS]

        print("="*80)
        print(f"STEP 2: SCRAPING RANKINGS FOR {len(schools)} SCHOOLS")
        print("="*80)

        # Step 2: Scrape each school's rankings
        all_data = []
        for i, school in enumerate(schools, 1):
            print(f"\n[{i}/{len(schools)}] {school['name']}")

            try:
                school_data = scrape_school_rankings(driver, school)
                all_data.append(school_data)

                # Display what we found
                print(f"  Overall D1 Rank: #{school_data.get('overall_division1_rank', 'N/A')}")
                print(f"  Conference: {school_data.get('conference', 'N/A')}")
                print(f"  Division: {school_data.get('division', 'N/A')}")
                print(f"  Mid-Major: {school_data.get('is_mid_major', False)}")

                # Men's rankings
                mens_rankings = []
                if school_data.get('mens_national_ranking'):
                    mens_rankings.append(f"National: #{school_data['mens_national_ranking']}")
                if school_data.get('mens_conference_ranking'):
                    mens_rankings.append(f"Conference: #{school_data['mens_conference_ranking']}")
                if school_data.get('mens_mid_major_ranking'):
                    mens_rankings.append(f"Mid-Major: #{school_data['mens_mid_major_ranking']}")

                if mens_rankings:
                    print(f"  Men's Rankings: {', '.join(mens_rankings)}")
                else:
                    print(f"  Men's Rankings: No data")

                # Women's rankings
                womens_rankings = []
                if school_data.get('womens_national_ranking'):
                    womens_rankings.append(f"National: #{school_data['womens_national_ranking']}")
                if school_data.get('womens_conference_ranking'):
                    womens_rankings.append(f"Conference: #{school_data['womens_conference_ranking']}")
                if school_data.get('womens_mid_major_ranking'):
                    womens_rankings.append(f"Mid-Major: #{school_data['womens_mid_major_ranking']}")

                if womens_rankings:
                    print(f"  Women's Rankings: {', '.join(womens_rankings)}")
                else:
                    print(f"  Women's Rankings: No data")

            except Exception as e:
                print(f"\n  ✗ Error: {e}")
                all_data.append({
                    "name": school["name"],
                    "team_id": school["team_id"],
                    "swimcloud_url": school["url"],
                    "overall_division1_rank": school.get("overall_division1_rank", ""),
                    "conference": "",
                    "conference_rank": "",
                    "division": "",
                    "is_mid_major": False,
                    "mid_major_rank": "",
                    "mens_national_ranking": "",
                    "mens_conference_ranking": "",
                    "mens_mid_major_ranking": "",
                    "womens_national_ranking": "",
                    "womens_conference_ranking": "",
                    "womens_mid_major_ranking": ""
                })
                continue

            time.sleep(1)  # Delay between schools

        # Calculate mid-major rankings
        print(f"\n{'='*80}")
        print("CALCULATING MID-MAJOR RANKINGS")
        print("="*80)

        mid_major_schools = [s for s in all_data if s.get("is_mid_major")]
        mid_major_schools.sort(key=lambda x: x.get("overall_division1_rank", 999))

        for i, school in enumerate(mid_major_schools, 1):
            school["mid_major_rank"] = i
            print(f"  [{i}] {school['name']}")

        # Calculate conference rankings
        print(f"\n{'='*80}")
        print("CALCULATING CONFERENCE RANKINGS")
        print("="*80)

        # Group by conference
        conferences = {}
        for school in all_data:
            conf = school.get("conference", "Unknown")
            if conf not in conferences:
                conferences[conf] = []
            conferences[conf].append(school)

        # Rank within each conference
        for conf, schools in conferences.items():
            schools.sort(key=lambda x: x.get("overall_division1_rank", 999))
            print(f"\n  {conf} Conference:")
            for i, school in enumerate(schools, 1):
                school["conference_rank"] = i
                print(f"    [{i}] {school['name']}")

        # Save data
        print(f"\n{'='*80}")
        print("SAVING DATA")
        print("="*80)

        output_file = "schools_rankings.csv"
        fieldnames = [
            "name", "team_id", "swimcloud_url",
            "overall_division1_rank", "conference", "conference_rank",
            "division", "is_mid_major", "mid_major_rank",
            "mens_national_ranking", "mens_conference_ranking", "mens_mid_major_ranking",
            "womens_national_ranking", "womens_conference_ranking", "womens_mid_major_ranking"
        ]

        with open(output_file, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for school in all_data:
                writer.writerow(school)

        print(f"\n✓ Saved {len(all_data)} schools to {output_file}")

        # Print statistics
        mid_major_count = sum(1 for s in all_data if s.get("is_mid_major"))
        division1_count = len(all_data) - mid_major_count

        mens_ranked = sum(1 for s in all_data if s.get("mens_national_ranking") or s.get("mens_mid_major_ranking"))
        womens_ranked = sum(1 for s in all_data if s.get("womens_national_ranking") or s.get("womens_mid_major_ranking"))

        print(f"\nStatistics:")
        print(f"  - Division 1 schools: {division1_count}")
        print(f"  - Division 1 Mid-Major schools: {mid_major_count}")
        print(f"  - Schools with men's rankings: {mens_ranked}")
        print(f"  - Schools with women's rankings: {womens_ranked}")
        print(f"  - Total schools: {len(all_data)}")

    except Exception as e:
        print(f"\n✗ Fatal error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        driver.quit()

    print("\n" + "="*80)
    print("ALL DONE! 🏊‍♂️")
    print("="*80)
    print(f"\nYour data is ready in: schools_rankings.csv")
    print("="*80 + "\n")

if __name__ == "__main__":
    main()
