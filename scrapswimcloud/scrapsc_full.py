from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from bs4 import BeautifulSoup
import csv
import time
import json

BASE_URL = "https://www.swimcloud.com"

def setup_driver():
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument("user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
    return webdriver.Chrome(options=chrome_options)

def fetch_html(driver, url):
    driver.get(url)
    time.sleep(5)  # Wait for content to load
    return driver.page_source

def get_rankings_page():
    """Get the main rankings page with all teams"""
    url = "https://www.swimcloud.com/country/usa/teams/?eventCourse=Y&gender=M&page=1&rankType=D&region=division_1&seasonId=29&sortBy=top50"
    driver = setup_driver()
    try:
        html = fetch_html(driver, url)
        return html
    finally:
        driver.quit()

def parse_rankings(html):
    """Extract team list from rankings page"""
    soup = BeautifulSoup(html, "html.parser")
    teams = []

    table = soup.find("table", class_="c-table-clean")
    if not table:
        return teams

    tbody = table.find("tbody")
    if not tbody:
        return teams

    rows = tbody.find_all("tr")

    for row in rows:
        try:
            cells = row.find_all("td")
            if len(cells) < 3:
                continue

            rank = cells[0].get_text(strip=True)
            team_link = cells[1].find("a", href=lambda x: x and x.startswith("/team/"))
            if not team_link:
                continue

            team_url = BASE_URL + team_link.get("href", "")
            full_name = team_link.get("title", "")
            short_name = team_link.find("strong")
            team_name = short_name.get_text(strip=True) if short_name else full_name
            points_link = cells[2].find("a")
            points = points_link.get_text(strip=True) if points_link else ""

            # Extract team ID from URL
            team_id = team_link.get("href", "").split("/")[2] if "/" in team_link.get("href", "") else ""

            teams.append({
                "rank": rank,
                "team_id": team_id,
                "name": team_name,
                "full_name": full_name,
                "url": team_url,
                "points": points
            })
        except Exception as e:
            print(f"Error parsing row: {e}")
            continue

    return teams

def scrape_team_main_page(driver, team_url):
    """Scrape main team page for basic info"""
    data = {}

    try:
        html = fetch_html(driver, team_url)
        soup = BeautifulSoup(html, "html.parser")

        # Get team logo
        toolbar = soup.find("div", class_="c-toolbar")
        if toolbar:
            img = toolbar.find("img", class_="c-toolbar__img")
            data["logo_url"] = img.get("src", "") if img else ""

        # Get division and conference from toolbar meta
        meta = soup.find("div", class_="c-toolbar__meta")
        if meta:
            links = meta.find_all("a")
            for link in links:
                href = link.get("href", "")
                text = link.get_text(strip=True)
                if "/division/" in href:
                    data["division"] = text
                elif "/conference/" in href:
                    data["conference"] = text
                    data["conference_full"] = link.get("title", text)

        # Get social media links
        twitter_link = soup.find("a", href=lambda x: x and "twitter.com" in str(x))
        instagram_link = soup.find("a", href=lambda x: x and "instagram.com" in str(x))
        website_link = soup.find("a", class_="btn-icon-plain", href=lambda x: x and x not in [None, ""] and "twitter" not in str(x) and "instagram" not in str(x))

        data["twitter"] = twitter_link.get("href", "") if twitter_link else ""
        data["instagram"] = instagram_link.get("href", "") if instagram_link else ""
        data["website"] = website_link.get("href", "") if website_link else ""

    except Exception as e:
        print(f"  Error scraping main page: {e}")

    return data

def scrape_team_about_page(driver, team_url):
    """Scrape team about page for detailed info"""
    data = {}

    try:
        about_url = team_url.rstrip("/") + "/about/"
        html = fetch_html(driver, about_url)
        soup = BeautifulSoup(html, "html.parser")

        # School meta information
        meta_items = soup.find_all("li", class_="c-school-meta__item")
        for item in meta_items:
            title_div = item.find("div", class_="c-school-meta__title")
            label_span = item.find("span", class_="u-color-mute")
            if title_div and label_span:
                label = label_span.get_text(strip=True).lower().replace(" ", "_")
                value = title_div.get_text(strip=True)
                data[f"school_{label}"] = value

        # Definition lists (division, conference, address, etc.)
        dls = soup.find_all("dl", class_="c-dl")
        for dl in dls:
            dt = dl.find("dt")
            dd = dl.find("dd")
            if dt and dd:
                key = dt.get_text(strip=True).lower().replace(":", "").replace(" ", "_").replace("'", "")
                value = dd.get_text(strip=True)
                # For links, get href too
                link = dd.find("a")
                if link and link.get("href"):
                    data[f"{key}_url"] = link.get("href", "")
                data[key] = value

        # Average annual cost
        cost_div = soup.find("div", class_="c-display2")
        if cost_div:
            data["average_annual_cost"] = cost_div.get_text(strip=True)

        # Graduation rate
        grad_section = soup.find("h2", string=lambda x: x and "Graduation" in str(x))
        if grad_section:
            parent = grad_section.find_parent("section")
            if parent:
                display = parent.find("div", class_="c-display2")
                if display:
                    data["graduation_rate"] = display.get_text(strip=True)

        # Test scores (ACT/SAT)
        act_section = soup.find("h4", string=lambda x: x and "ACT" in str(x))
        if act_section:
            parent = act_section.find_parent()
            if parent:
                display = parent.find("div", class_="c-display2")
                if display:
                    data["act_score"] = display.get_text(strip=True)

        sat_section = soup.find("h4", string=lambda x: x and "SAT" in str(x))
        if sat_section:
            parent = sat_section.find_parent()
            if parent:
                display = parent.find("div", class_="c-display2")
                if display:
                    data["sat_score"] = display.get_text(strip=True)

    except Exception as e:
        print(f"  Error scraping about page: {e}")

    return data

def scrape_team_coaches(driver, team_url):
    """Scrape team coaches page"""
    coaches = []

    try:
        coaches_url = team_url.rstrip("/") + "/coaches/"
        html = fetch_html(driver, coaches_url)
        soup = BeautifulSoup(html, "html.parser")

        coach_cards = soup.find_all("div", class_="c-card")
        for card in coach_cards:
            media_body = card.find("div", class_="o-media__body")
            if media_body:
                name_elem = media_body.find("h3")
                position_elem = media_body.find("p")

                if name_elem:
                    coach_name = name_elem.get_text(strip=True)
                    coach_position = position_elem.get_text(strip=True) if position_elem else ""
                    coaches.append({
                        "name": coach_name,
                        "position": coach_position
                    })
    except Exception as e:
        print(f"  Error scraping coaches page: {e}")

    return coaches

def scrape_team_details(driver, team_info):
    """Scrape all details for a single team"""
    print(f"\nScraping: {team_info['name']} (Rank {team_info['rank']})")

    all_data = {**team_info}

    # Scrape main page
    print(f"  - Main page...")
    main_data = scrape_team_main_page(driver, team_info['url'])
    all_data.update(main_data)

    # Scrape about page
    print(f"  - About page...")
    about_data = scrape_team_about_page(driver, team_info['url'])
    all_data.update(about_data)

    # Scrape coaches
    print(f"  - Coaches page...")
    coaches = scrape_team_coaches(driver, team_info['url'])
    all_data["coaches"] = json.dumps(coaches) if coaches else ""
    all_data["num_coaches"] = len(coaches)

    # Add head coach info separately
    if coaches:
        head_coach = next((c for c in coaches if "head" in c['position'].lower()), coaches[0] if coaches else None)
        if head_coach:
            all_data["head_coach_name"] = head_coach["name"]
            all_data["head_coach_position"] = head_coach["position"]

    return all_data

def main():
    print("="*60)
    print("SWIMCLOUD D1 MEN'S SWIMMING COMPREHENSIVE SCRAPER")
    print("="*60)

    # Step 1: Get rankings page
    print("\n[1/3] Fetching rankings page...")
    rankings_html = get_rankings_page()
    teams = parse_rankings(rankings_html)
    print(f"Found {len(teams)} teams")

    # Step 2: Scrape each team
    print(f"\n[2/3] Scraping details for {len(teams)} teams...")
    driver = setup_driver()
    all_team_data = []

    try:
        for i, team in enumerate(teams, 1):
            print(f"\n[{i}/{len(teams)}]", end=" ")
            team_data = scrape_team_details(driver, team)
            all_team_data.append(team_data)
            time.sleep(2)  # Be nice to the server
    finally:
        driver.quit()

    # Step 3: Save to CSV
    print(f"\n\n[3/3] Saving data to CSV...")
    if all_team_data:
        # Get all possible keys from all teams
        all_keys = set()
        for team in all_team_data:
            all_keys.update(team.keys())

        fieldnames = sorted(list(all_keys))

        with open("teams_full_data.csv", "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for team in all_team_data:
                writer.writerow(team)

        print(f"✓ Saved {len(all_team_data)} teams to teams_full_data.csv")
        print(f"✓ Total fields captured: {len(fieldnames)}")
    else:
        print("✗ No data to save")

    print("\n" + "="*60)
    print("SCRAPING COMPLETE!")
    print("="*60)

if __name__ == "__main__":
    main()
