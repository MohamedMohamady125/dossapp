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

def scrape_teams_list_with_gender(driver, base_url, gender="M", max_pages=None):
    """
    Scrape all teams from Division 1 listing pages for specific gender
    gender: "M" for men, "F" for women
    """
    teams = []
    page = 1

    print(f"\nScraping {'Men' if gender == 'M' else 'Women'}'s Teams:")
    print("-" * 80)

    while True:
        if max_pages and page > max_pages:
            break

        # Update URL with gender parameter
        url = base_url.replace("gender=M", f"gender={gender}").replace("page=1", f"page={page}")
        print(f"  Page {page}: Loading...", end=" ", flush=True)

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

                    # Calculate rank (position in listing)
                    rank = ((page - 1) * 50) + len(teams) + 1

                    teams.append({
                        "name": name,
                        "team_id": team_id,
                        "url": url,
                        "rank": rank
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

    print(f"  Total: {len(teams)} teams\n")
    return teams

def scrape_basic_info(driver, team_url):
    """Scrape division and conference from main team page"""
    data = {"division": "", "conference": "", "is_mid_major": False}

    try:
        html = fetch_html(driver, team_url, wait_time=1.5)
        soup = BeautifulSoup(html, "html.parser")

        meta = soup.find("div", class_="c-toolbar__meta")
        if meta:
            links = meta.find_all("a")
            for link in links:
                href = link.get("href", "")
                text = link.get_text(strip=True)
                if "/division/" in href:
                    data["division"] = text
                    if "mid-major" in text.lower() or "mid major" in text.lower():
                        data["is_mid_major"] = True
                elif "/conference/" in href:
                    data["conference"] = text
    except Exception as e:
        pass

    return data

def main():
    print("\n" + "="*80)
    print("MEN'S & WOMEN'S RANKINGS SCRAPER - CONFERENCE & DIVISION RANKINGS")
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
        print("\n" + "="*80)
        print("STEP 1: SCRAPING TEAMS LISTINGS BY GENDER")
        print("="*80)

        # Scrape men's teams
        mens_teams = scrape_teams_list_with_gender(driver, TEAMS_URL, gender="M", max_pages=MAX_PAGES)

        # Scrape women's teams
        womens_teams = scrape_teams_list_with_gender(driver, TEAMS_URL, gender="F", max_pages=MAX_PAGES)

        # Create team ID to rank mappings
        mens_rankings = {team['team_id']: team['rank'] for team in mens_teams}
        womens_rankings = {team['team_id']: team['rank'] for team in womens_teams}

        # Get all unique teams
        all_team_ids = set(mens_rankings.keys()) | set(womens_rankings.keys())

        print("="*80)
        print(f"STEP 2: GETTING SCHOOL INFO FOR {len(all_team_ids)} SCHOOLS")
        print("="*80)

        # Build complete dataset
        schools_data = []

        # Start with all teams from either list
        all_teams_dict = {}
        for team in mens_teams:
            all_teams_dict[team['team_id']] = team
        for team in womens_teams:
            if team['team_id'] not in all_teams_dict:
                all_teams_dict[team['team_id']] = team

        for i, (team_id, team) in enumerate(all_teams_dict.items(), 1):
            print(f"\n[{i}/{len(all_teams_dict)}] {team['name']}")

            # Get basic info
            basic_info = scrape_basic_info(driver, team['url'])

            school_data = {
                'name': team['name'],
                'team_id': team_id,
                'swimcloud_url': team['url'],
                'conference': basic_info['conference'],
                'division': basic_info['division'],
                'is_mid_major': basic_info['is_mid_major'],
                'mens_division_rank': mens_rankings.get(team_id, ''),
                'womens_division_rank': womens_rankings.get(team_id, ''),
                'mens_conference_rank': '',
                'womens_conference_rank': '',
                'mens_mid_major_rank': '',
                'womens_mid_major_rank': ''
            }

            schools_data.append(school_data)

            print(f"  Conference: {basic_info['conference']}")
            print(f"  Division: {basic_info['division']}")
            print(f"  Men's D1 Rank: #{mens_rankings.get(team_id, 'N/A')}")
            print(f"  Women's D1 Rank: #{womens_rankings.get(team_id, 'N/A')}")

            time.sleep(0.5)

        print("\n" + "="*80)
        print("STEP 3: CALCULATING CONFERENCE RANKINGS")
        print("="*80)

        # Calculate conference rankings for men
        conferences_men = {}
        for school in schools_data:
            if school['mens_division_rank']:
                conf = school['conference']
                if conf not in conferences_men:
                    conferences_men[conf] = []
                conferences_men[conf].append(school)

        for conf, schools in conferences_men.items():
            schools.sort(key=lambda x: int(x['mens_division_rank']))
            for i, school in enumerate(schools, 1):
                school['mens_conference_rank'] = i

        # Calculate conference rankings for women
        conferences_women = {}
        for school in schools_data:
            if school['womens_division_rank']:
                conf = school['conference']
                if conf not in conferences_women:
                    conferences_women[conf] = []
                conferences_women[conf].append(school)

        for conf, schools in conferences_women.items():
            schools.sort(key=lambda x: int(x['womens_division_rank']))
            for i, school in enumerate(schools, 1):
                school['womens_conference_rank'] = i

        print("\n  Calculated conference rankings for men and women")

        print("\n" + "="*80)
        print("STEP 4: CALCULATING MID-MAJOR RANKINGS")
        print("="*80)

        # Calculate mid-major rankings for men
        mid_major_men = [s for s in schools_data if s['is_mid_major'] and s['mens_division_rank']]
        mid_major_men.sort(key=lambda x: int(x['mens_division_rank']))
        for i, school in enumerate(mid_major_men, 1):
            school['mens_mid_major_rank'] = i

        # Calculate mid-major rankings for women
        mid_major_women = [s for s in schools_data if s['is_mid_major'] and s['womens_division_rank']]
        mid_major_women.sort(key=lambda x: int(x['womens_division_rank']))
        for i, school in enumerate(mid_major_women, 1):
            school['womens_mid_major_rank'] = i

        print(f"\n  Men's mid-major schools: {len(mid_major_men)}")
        print(f"  Women's mid-major schools: {len(mid_major_women)}")

        # Save data
        print("\n" + "="*80)
        print("SAVING DATA")
        print("="*80)

        output_file = "mens_womens_rankings.csv"
        fieldnames = [
            'name', 'team_id', 'swimcloud_url',
            'conference', 'division', 'is_mid_major',
            'mens_division_rank', 'mens_conference_rank', 'mens_mid_major_rank',
            'womens_division_rank', 'womens_conference_rank', 'womens_mid_major_rank'
        ]

        with open(output_file, 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for school in schools_data:
                writer.writerow(school)

        print(f"\n✓ Saved {len(schools_data)} schools to {output_file}")

        # Print statistics
        mens_teams_count = sum(1 for s in schools_data if s['mens_division_rank'])
        womens_teams_count = sum(1 for s in schools_data if s['womens_division_rank'])
        both_teams_count = sum(1 for s in schools_data if s['mens_division_rank'] and s['womens_division_rank'])

        print(f"\nStatistics:")
        print(f"  - Schools with men's teams: {mens_teams_count}")
        print(f"  - Schools with women's teams: {womens_teams_count}")
        print(f"  - Schools with both teams: {both_teams_count}")
        print(f"  - Total unique schools: {len(schools_data)}")

        # Show sample data
        print(f"\nSample data (first 5 schools):")
        for i, school in enumerate(schools_data[:5], 1):
            print(f"\n  [{i}] {school['name']}")
            print(f"      Conference: {school['conference']}")
            print(f"      Men's: D1 Rank #{school['mens_division_rank'] or 'N/A'}, Conf Rank #{school['mens_conference_rank'] or 'N/A'}")
            print(f"      Women's: D1 Rank #{school['womens_division_rank'] or 'N/A'}, Conf Rank #{school['womens_conference_rank'] or 'N/A'}")

    except Exception as e:
        print(f"\n✗ Fatal error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        driver.quit()

    print("\n" + "="*80)
    print("ALL DONE! 🏊‍♂️🏊‍♀️")
    print("="*80)
    print(f"\nYour data is ready in: mens_womens_rankings.csv")
    print("="*80 + "\n")

if __name__ == "__main__":
    main()
