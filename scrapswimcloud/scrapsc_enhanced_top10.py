from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from bs4 import BeautifulSoup
import csv
import time
import json
import re

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

def scrape_fastest_times_top10(driver, team_url, gender="M"):
    """Scrape TOP 10 fastest times for each event
    gender: M for Men, F for Women
    """
    times_data = {}

    try:
        # Build rankings URL with gender parameter
        rankings_url = team_url.rstrip("/") + f"/rankings/?gender={gender}&season=29&event_course=Y&rank_type=D"
        print(f"    Fetching top 10 {gender} times from: {rankings_url}")

        html = fetch_html(driver, rankings_url)
        soup = BeautifulSoup(html, "html.parser")

        # Find all event headers
        event_headers = soup.find_all("th", class_="c-table-clean__subheader")

        for header in event_headers:
            event_name = header.get_text(strip=True)
            event_key_base = event_name.replace(' ', '_').replace('/', '').lower()

            # Find the tbody that contains this event
            tbody = header.find_parent("tbody")
            if not tbody:
                continue

            # Get all rows in this tbody (excluding the header row)
            rows = tbody.find_all("tr")
            swimmer_rows = [r for r in rows if not r.find("th", class_="c-table-clean__subheader")]

            # Get top 10 times (or however many are available)
            top_10_rows = swimmer_rows[:10]

            for idx, row in enumerate(top_10_rows, 1):
                cells = row.find_all("td")
                if len(cells) >= 3:
                    # Extract swimmer, meet, time
                    swimmer_link = cells[0].find("a")
                    swimmer_name = swimmer_link.get_text(strip=True) if swimmer_link else ""

                    meet_link = cells[1].find("a")
                    meet_name = meet_link.get_text(strip=True) if meet_link else ""

                    time_link = cells[2].find("a")
                    time_value = time_link.get_text(strip=True) if time_link else ""

                    # Store with gender prefix and rank
                    gender_prefix = "mens" if gender == "M" else "womens"

                    times_data[f"{gender_prefix}_{event_key_base}_rank{idx}_time"] = time_value
                    times_data[f"{gender_prefix}_{event_key_base}_rank{idx}_swimmer"] = swimmer_name
                    times_data[f"{gender_prefix}_{event_key_base}_rank{idx}_meet"] = meet_name

        num_events = len(event_headers)
        total_times = len([k for k in times_data.keys() if k.endswith('_time')])
        print(f"    ✓ Collected {total_times} times across {num_events} {gender} events (up to 10 per event)")

    except Exception as e:
        print(f"    ✗ Error scraping {gender} times: {e}")

    return times_data

def scrape_coaches_with_emails(driver, team_url):
    """Scrape coaches with their emails if available"""
    coaches = []

    try:
        coaches_url = team_url.rstrip("/") + "/coaches/"
        html = fetch_html(driver, coaches_url)
        soup = BeautifulSoup(html, "html.parser")

        # Email regex pattern
        email_pattern = r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'

        coach_cards = soup.find_all("div", class_="c-card")

        for card in coach_cards:
            media_body = card.find("div", class_="o-media__body")
            if media_body:
                name_elem = media_body.find("h3")
                position_elem = media_body.find("p")

                if name_elem:
                    coach_name = name_elem.get_text(strip=True)
                    coach_position = position_elem.get_text(strip=True) if position_elem else ""

                    # Look for email in the card
                    card_html = str(card)

                    # Search for email in HTML
                    emails_in_card = re.findall(email_pattern, card_html)
                    # Filter out non-coach emails (like Sentry)
                    valid_emails = [e for e in emails_in_card if 'sentry' not in e.lower() and 'google' not in e.lower()]

                    coach_email = valid_emails[0] if valid_emails else ""

                    # Check if coach has a profile page link
                    coach_link = name_elem.find("a")
                    if coach_link and coach_link.get("href") and not coach_email:
                        # Try to get email from coach's individual page
                        coach_page_url = BASE_URL + coach_link.get("href")
                        try:
                            coach_html = fetch_html(driver, coach_page_url)
                            coach_emails = re.findall(email_pattern, coach_html)
                            valid_coach_emails = [e for e in coach_emails if 'sentry' not in e.lower() and 'google' not in e.lower()]
                            if valid_coach_emails:
                                coach_email = valid_coach_emails[0]
                        except:
                            pass

                    coaches.append({
                        "name": coach_name,
                        "position": coach_position,
                        "email": coach_email
                    })

        print(f"    ✓ Collected {len(coaches)} coaches")

    except Exception as e:
        print(f"    ✗ Error scraping coaches: {e}")

    return coaches

def scrape_team_basic_info(driver, team_info):
    """Scrape basic team info"""
    data = {**team_info}

    try:
        html = fetch_html(driver, team_info['url'])
        soup = BeautifulSoup(html, "html.parser")

        # Get division and conference
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

        # Get address from about page
        about_url = team_info['url'].rstrip("/") + "/about/"
        about_html = fetch_html(driver, about_url)
        about_soup = BeautifulSoup(about_html, "html.parser")

        dls = about_soup.find_all("dl", class_="c-dl")
        for dl in dls:
            dt = dl.find("dt")
            dd = dl.find("dd")
            if dt and dd:
                key = dt.get_text(strip=True).lower()
                if "address" in key:
                    data["address"] = dd.get_text(strip=True)
                elif "website" in key:
                    link = dd.find("a")
                    if link:
                        data["website"] = link.get("href", "")

    except Exception as e:
        print(f"  ✗ Error scraping basic info: {e}")

    return data

def scrape_team_enhanced(driver, team_info):
    """Scrape all enhanced details for a single team"""
    print(f"\n{'='*60}")
    print(f"Scraping: {team_info['name']} (Rank {team_info['rank']})")
    print('='*60)

    all_data = {}

    # 1. Basic info
    print("  [1/4] Basic info...")
    basic_data = scrape_team_basic_info(driver, team_info)
    all_data.update(basic_data)

    # 2. Men's TOP 10 fastest times
    print("  [2/4] Men's TOP 10 fastest times...")
    mens_times = scrape_fastest_times_top10(driver, team_info['url'], gender="M")
    all_data.update(mens_times)

    # 3. Women's TOP 10 fastest times
    print("  [3/4] Women's TOP 10 fastest times...")
    womens_times = scrape_fastest_times_top10(driver, team_info['url'], gender="F")
    all_data.update(womens_times)

    # 4. Coaches with emails
    print("  [4/4] Coaches with emails...")
    coaches = scrape_coaches_with_emails(driver, team_info['url'])
    all_data["coaches"] = json.dumps(coaches) if coaches else ""
    all_data["num_coaches"] = len(coaches)

    # Add individual coach columns for first 5 coaches
    for i, coach in enumerate(coaches[:5], 1):
        all_data[f"coach_{i}_name"] = coach["name"]
        all_data[f"coach_{i}_position"] = coach["position"]
        all_data[f"coach_{i}_email"] = coach["email"]

    total_fields = len(all_data)
    print(f"\n  ✓ Total fields collected: {total_fields}")

    return all_data

def main():
    print("="*60)
    print("ENHANCED SCRAPER - TOP 10 TIMES - TEST ON 2 SCHOOLS")
    print("="*60)

    # Test teams: Texas (#1) and Arizona State (#2)
    test_teams = [
        {
            "rank": "1",
            "team_id": "105",
            "name": "Texas",
            "full_name": "University of Texas",
            "url": "https://www.swimcloud.com/team/105",
            "points": "897.25"
        },
        {
            "rank": "2",
            "team_id": "87",
            "name": "Arizona State",
            "full_name": "Arizona State University",
            "url": "https://www.swimcloud.com/team/87",
            "points": "885.25"
        }
    ]

    driver = setup_driver()
    all_team_data = []

    try:
        for team in test_teams:
            team_data = scrape_team_enhanced(driver, team)
            all_team_data.append(team_data)
            time.sleep(3)  # Be nice to the server
    finally:
        driver.quit()

    # Save to CSV
    print(f"\n{'='*60}")
    print("Saving to CSV...")
    print('='*60)

    if all_team_data:
        all_keys = set()
        for team in all_team_data:
            all_keys.update(team.keys())

        fieldnames = sorted(list(all_keys))

        with open("teams_enhanced_top10_test.csv", "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for team in all_team_data:
                writer.writerow(team)

        print(f"✓ Saved {len(all_team_data)} teams to teams_enhanced_top10_test.csv")
        print(f"✓ Total fields: {len(fieldnames)}\n")

        print("Sample fields (showing first 30):")
        for field in sorted(fieldnames)[:30]:
            print(f"  - {field}")

    print("\n" + "="*60)
    print("TEST COMPLETE!")
    print("="*60)

if __name__ == "__main__":
    main()
