from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from bs4 import BeautifulSoup
import csv
import time
import json
import re

BASE_URL = "https://www.swimcloud.com"

# Define events to scrape
EVENTS_TO_SCRAPE = [
    ("50_free", "50 Free"),
    ("100_free", "100 Free"),
    ("200_free", "200 Free"),
    ("500_free", "500 Free"),
    ("1000_free", "1000 Free"),
    ("100_back", "100 Back"),
    ("200_back", "200 Back"),
    ("100_breast", "100 Breast"),
    ("200_breast", "200 Breast"),
    ("100_fly", "100 Fly"),
    ("200_fly", "200 Fly"),
    ("200_im", "200 IM"),
    ("400_im", "400 IM"),
]

def setup_driver():
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument("user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
    return webdriver.Chrome(options=chrome_options)

def fetch_html(driver, url):
    driver.get(url)
    time.sleep(4)  # Wait for content to load
    return driver.page_source

def scrape_event_top10(driver, team_url, event_name, gender="M"):
    """Scrape top 10 times for a specific event"""
    times_data = {}

    try:
        # Build times URL - the times page shows one event at a time
        times_url = team_url.rstrip("/") + f"/times/?gender={gender}&season=29&event_course=Y"

        html = fetch_html(driver, times_url)
        soup = BeautifulSoup(html, "html.parser")

        # Check if this page has the event we're looking for
        page_title = soup.find("h2", class_="c-title--small")
        if not page_title or event_name not in page_title.get_text():
            # Event might not be on this default page, but we'll try to parse anyway
            pass

        # Find the table with times
        table = soup.find("table", class_="c-table-clean")
        if not table:
            return times_data

        tbody = table.find("tbody")
        if not tbody:
            return times_data

        rows = tbody.find_all("tr")

        # Get top 10 rows
        for idx, row in enumerate(rows[:10], 1):
            cells = row.find_all("td")
            if len(cells) >= 4:
                # Skip the rank column (first cell)
                # Columns: rank | swimmer | meet (hidden on xs) | time | flags

                swimmer_link = cells[1].find("a")
                swimmer_name = swimmer_link.get_text(strip=True) if swimmer_link else ""

                meet_link = cells[2].find("a") if len(cells) > 2 else None
                meet_name = meet_link.get_text(strip=True) if meet_link else ""

                time_link = cells[3].find("a") if len(cells) > 3 else None
                time_value = time_link.get_text(strip=True) if time_link else ""

                if time_value:  # Only add if we got a time
                    times_data[f"rank{idx}_time"] = time_value
                    times_data[f"rank{idx}_swimmer"] = swimmer_name
                    times_data[f"rank{idx}_meet"] = meet_name

    except Exception as e:
        print(f"      Error: {e}")

    return times_data

def scrape_all_events_top10(driver, team_url, gender="M"):
    """Scrape top 10 times for all events"""
    all_times = {}
    gender_prefix = "mens" if gender == "M" else "womens"

    print(f"    Scraping {gender} events...")

    for event_key, event_name in EVENTS_TO_SCRAPE:
        print(f"      {event_name}...", end=" ")

        event_times = scrape_event_top10(driver, team_url, event_name, gender)

        # Prefix with gender and event name
        for key, value in event_times.items():
            full_key = f"{gender_prefix}_{event_key}_{key}"
            all_times[full_key] = value

        print(f"✓ {len([k for k in event_times.keys() if k.endswith('_time')])} times")
        time.sleep(1)  # Small delay between events

    total_times = len([k for k in all_times.keys() if k.endswith('_time')])
    print(f"    Total {gender} times collected: {total_times}")

    return all_times

def scrape_coaches_with_emails(driver, team_url):
    """Scrape coaches with their emails if available"""
    coaches = []

    try:
        coaches_url = team_url.rstrip("/") + "/coaches/"
        html = fetch_html(driver, coaches_url)
        soup = BeautifulSoup(html, "html.parser")

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

                    card_html = str(card)
                    emails_in_card = re.findall(email_pattern, card_html)
                    valid_emails = [e for e in emails_in_card if 'sentry' not in e.lower() and 'google' not in e.lower()]
                    coach_email = valid_emails[0] if valid_emails else ""

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

    # 2. Men's TOP 10 fastest times for all events
    print("  [2/4] Men's TOP 10 times per event...")
    mens_times = scrape_all_events_top10(driver, team_info['url'], gender="M")
    all_data.update(mens_times)

    # 3. Women's TOP 10 fastest times for all events
    print("  [3/4] Women's TOP 10 times per event...")
    womens_times = scrape_all_events_top10(driver, team_info['url'], gender="F")
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
    print("FINAL ENHANCED SCRAPER - TOP 10 PER EVENT - TEST ON 2 SCHOOLS")
    print("="*60)

    # Test teams
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
            time.sleep(3)
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

        with open("teams_top10_final_test.csv", "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for team in all_team_data:
                writer.writerow(team)

        print(f"✓ Saved {len(all_team_data)} teams to teams_top10_final_test.csv")
        print(f"✓ Total fields: {len(fieldnames)}\n")

    print("\n" + "="*60)
    print("TEST COMPLETE!")
    print("="*60)

if __name__ == "__main__":
    main()
