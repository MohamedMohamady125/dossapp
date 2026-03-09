from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import Select, WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from bs4 import BeautifulSoup
import csv
import time
import re
import json

BASE_URL = "https://www.swimcloud.com"

# Specific schools to scrape - add team_id when known for faster processing
TARGET_SCHOOLS = [
    {"name": "Bowling Green State University", "team_id": "32"},
    {"name": "Butler University", "team_id": "33"},
    {"name": "Campbell University", "team_id": "34"},
    {"name": "Eastern Michigan University", "team_id": "64"},
    {"name": "Florida Gulf Coast University", "team_id": "71"},
    {"name": "Florida International University", "team_id": "72"},
    {"name": "Fresno State University", "team_id": "78"},
    {"name": "Georgia Southern University", "team_id": "84"},
    {"name": "Illinois State University", "team_id": "99"},
    {"name": "Indiana State University", "team_id": "103"},
    {"name": "Iowa State University", "team_id": "106"},
    {"name": "James Madison University", "team_id": "107"},
    {"name": "Liberty University", "team_id": "120"},
    {"name": "Marquette University", "team_id": "131"},
    {"name": "Marshall University", "team_id": "132"},
    {"name": "Merrimack College", "team_id": "138"},
    {"name": "New Mexico State University", "team_id": "155"},
    {"name": "Northeastern University", "team_id": "159"},
    {"name": "Northern Arizona University", "team_id": "160"},
    {"name": "Ohio University", "team_id": "166"},
    {"name": "Pepperdine University", "team_id": "176"},
    {"name": "Rice University", "team_id": "188"},
    {"name": "Rutgers University", "team_id": "193"},
    {"name": "Sacred Heart University", "team_id": "194"},
    {"name": "Saint Francis University", "team_id": "197"},
    {"name": "San Diego State University", "team_id": "203"},
    {"name": "San Jose State University", "team_id": "204"},
    {"name": "Siena College", "team_id": "209"},
    {"name": "University of Toledo", "team_id": "227"},
    {"name": "Tulane University", "team_id": "229"},
    {"name": "University of California, Los Angeles", "team_id": "235"},
    {"name": "University at Buffalo", "team_id": "30"},
    {"name": "University of Akron", "team_id": "2"},
    {"name": "University of Arkansas at Little Rock", "team_id": "15"},
    {"name": "University of California, Davis", "team_id": "35"},
    {"name": "University of Houston", "team_id": "95"},
    {"name": "University of Idaho", "team_id": "97"},
    {"name": "University of Illinois", "team_id": "98"},
    {"name": "University of Iowa", "team_id": "105"},
    {"name": "University of Kansas", "team_id": "110"},
    {"name": "University of Miami", "team_id": "137"},
    {"name": "University of Nebraska", "team_id": "148"},
    {"name": "University of Nevada", "team_id": "149"},
    {"name": "University of New Hampshire", "team_id": "151"},
    {"name": "University of New Mexico", "team_id": "154"},
    {"name": "UNC Asheville", "team_id": "157"},
    {"name": "University of North Florida", "team_id": "470"},
    {"name": "University of North Texas", "team_id": "161"},
    {"name": "University of Northern Colorado", "team_id": "162"},
    {"name": "University of Northern Iowa", "team_id": "163"},
    {"name": "University of Rhode Island", "team_id": "187"},
    {"name": "University of Richmond", "team_id": "189"},
    {"name": "University of San Diego", "team_id": "202"},
    {"name": "University of Texas Rio Grande Valley", "team_id": "224"},
    {"name": "University of Vermont", "team_id": "242"},
    {"name": "Utah Tech University", "team_id": "240"},
    {"name": "Vanderbilt University", "team_id": "241"},
    {"name": "Washington State University", "team_id": "247"},
]

# All swimming events to scrape (NCAA Championship events)
EVENTS_TO_SCRAPE = [
    ("50_free", "50 Free"),
    ("100_free", "100 Free"),
    ("200_free", "200 Free"),
    ("500_free", "500 Free"),
    ("1000_free", "1000 Free"),
    ("1650_free", "1650 Free"),
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

def parse_address(address_text):
    """Parse address into city, state, zip"""
    city, state, zip_code = "", "", ""
    if address_text:
        parts = address_text.split(",")
        if len(parts) >= 2:
            city = parts[0].strip()
            state_zip = parts[-1].strip().split()
            if len(state_zip) >= 1:
                state = state_zip[0]
            if len(state_zip) >= 2:
                zip_code = state_zip[-1]
    return city, state, zip_code

def scrape_basic_info(driver, team_url):
    """Scrape division, conference from main team page"""
    data = {"division": "", "conference": ""}

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
                elif "/conference/" in href:
                    data["conference"] = text
    except Exception as e:
        print(f"      Error: {e}")

    return data

def scrape_about_page(driver, team_url):
    """Scrape about page for detailed school information"""
    data = {
        "abbreviation": "",
        "website_url": "",
        "address": "",
        "city": "",
        "state": "",
        "zip_code": "",
        "founded_year": "",
        "ncaa_id": "",
        "description": "",
        "facilities_description": ""
    }

    try:
        about_url = team_url.rstrip("/") + "/about/"
        html = fetch_html(driver, about_url)
        soup = BeautifulSoup(html, "html.parser")

        # Parse dl elements
        dls = soup.find_all("dl", class_="c-dl")
        for dl in dls:
            dt = dl.find("dt")
            dd = dl.find("dd")
            if dt and dd:
                key = dt.get_text(strip=True).lower()
                value = dd.get_text(strip=True)

                if "address" in key:
                    data["address"] = value
                    city, state, zip_code = parse_address(value)
                    data["city"] = city
                    data["state"] = state
                    data["zip_code"] = zip_code
                elif "website" in key:
                    link = dd.find("a")
                    if link:
                        data["website_url"] = link.get("href", "")
                elif "founded" in key or "established" in key:
                    year_match = re.search(r'\b(19|20)\d{2}\b', value)
                    if year_match:
                        data["founded_year"] = year_match.group()
                elif "ncaa" in key:
                    data["ncaa_id"] = value

        # Description
        desc_elem = soup.find("div", class_="c-wysiwyg")
        if desc_elem:
            first_p = desc_elem.find("p")
            if first_p:
                data["description"] = first_p.get_text(strip=True)

        # Facilities
        facilities = soup.find("h3", string=re.compile(r'facilities', re.I))
        if facilities:
            facilities_content = facilities.find_next(["p", "div"])
            if facilities_content:
                data["facilities_description"] = facilities_content.get_text(strip=True)

        # Abbreviation
        h1 = soup.find("h1")
        if h1:
            text = h1.get_text(strip=True)
            if " - " in text:
                data["abbreviation"] = text.split(" - ")[0].strip()

    except Exception as e:
        print(f"      Error: {e}")

    return data

def scrape_coaches(driver, team_url):
    """Scrape swimming coaches' names, positions, and emails"""
    coaches_data = {
        "head_coach_name": "",
        "head_coach_email": "",
        "all_coaches_json": ""
    }

    try:
        coaches_url = team_url.rstrip("/") + "/coaches/"
        html = fetch_html(driver, coaches_url)
        soup = BeautifulSoup(html, "html.parser")

        email_pattern = r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
        coaches = []

        coach_cards = soup.find_all("div", class_="c-card")

        for card in coach_cards:
            media_body = card.find("div", class_="o-media__body")
            if media_body:
                name_elem = media_body.find("h3")
                position_elem = media_body.find("p")

                if name_elem:
                    coach_name = name_elem.get_text(strip=True)
                    coach_position = position_elem.get_text(strip=True) if position_elem else ""

                    # Filter out non-swimming coaches
                    position_lower = coach_position.lower()
                    if any(skip in position_lower for skip in ['diving', 'strength', 'conditioning', 'athletic trainer', 'director of operations']):
                        continue

                    # Only include swimming coaches
                    if not any(term in position_lower for term in ['swim', 'coach', 'head', 'assistant', 'associate']):
                        continue

                    # Extract email
                    card_html = str(card)
                    emails_in_card = re.findall(email_pattern, card_html)
                    valid_emails = [e for e in emails_in_card
                                  if not any(x in e.lower() for x in ['sentry', 'google', 'facebook', 'twitter', 'instagram'])]
                    coach_email = valid_emails[0] if valid_emails else ""

                    coach_info = {
                        "name": coach_name,
                        "position": coach_position,
                        "email": coach_email
                    }
                    coaches.append(coach_info)

                    # Identify head coach
                    if 'head' in position_lower and 'swimming' in position_lower:
                        coaches_data["head_coach_name"] = coach_name
                        coaches_data["head_coach_email"] = coach_email

        coaches_data["all_coaches_json"] = json.dumps(coaches) if coaches else ""

        # Add first 3 assistant coaches
        assistant_coaches = [c for c in coaches if 'assistant' in c['position'].lower()][:3]
        for i, coach in enumerate(assistant_coaches, 1):
            coaches_data[f"assistant_coach_{i}_name"] = coach["name"]
            coaches_data[f"assistant_coach_{i}_email"] = coach["email"]
            coaches_data[f"assistant_coach_{i}_position"] = coach["position"]

    except Exception as e:
        print(f"      Error scraping coaches: {e}")

    return coaches_data

def scrape_roster(driver, team_url):
    """Check which teams exist and get rankings"""
    data = {
        "has_mens_team": False,
        "has_womens_team": False,
        "total_athletes": 0,
        "conference_ranking": "",
        "national_ranking": ""
    }

    try:
        # Check men's roster
        mens_roster_url = team_url.rstrip("/") + "/roster/?gender=M&season=29"
        html = fetch_html(driver, mens_roster_url, wait_time=1.5)
        soup = BeautifulSoup(html, "html.parser")

        table = soup.find("table", class_="c-table-clean")
        if table:
            tbody = table.find("tbody")
            if tbody:
                mens_rows = tbody.find_all("tr")
                if mens_rows:
                    data["has_mens_team"] = True
                    data["total_athletes"] += len(mens_rows)

        # Check women's roster
        womens_roster_url = team_url.rstrip("/") + "/roster/?gender=F&season=29"
        html = fetch_html(driver, womens_roster_url, wait_time=1.5)
        soup = BeautifulSoup(html, "html.parser")

        table = soup.find("table", class_="c-table-clean")
        if table:
            tbody = table.find("tbody")
            if tbody:
                womens_rows = tbody.find_all("tr")
                if womens_rows:
                    data["has_womens_team"] = True
                    data["total_athletes"] += len(womens_rows)

        # Get rankings
        rankings_url = team_url.rstrip("/") + "/rankings/?season=29"
        html = fetch_html(driver, rankings_url, wait_time=1.5)
        soup = BeautifulSoup(html, "html.parser")

        # Look for rankings
        dls = soup.find_all("dl", class_="c-dl")
        for dl in dls:
            dt = dl.find("dt")
            dd = dl.find("dd")
            if dt and dd:
                key = dt.get_text(strip=True).lower()
                value = dd.get_text(strip=True)
                if "national" in key and "rank" in key:
                    rank_match = re.search(r'#?(\d+)', value)
                    if rank_match:
                        data["national_ranking"] = rank_match.group(1)
                elif "conference" in key and "rank" in key:
                    rank_match = re.search(r'#?(\d+)', value)
                    if rank_match:
                        data["conference_ranking"] = rank_match.group(1)

    except Exception as e:
        print(f"      Error: {e}")

    return data

def scrape_event_top10(driver, team_url, event_key, event_name, gender="M"):
    """Scrape top 10 times for a specific event"""
    times_data = {}

    try:
        times_url = team_url.rstrip("/") + f"/times/?gender={gender}&season=29&event_course=Y"

        # Navigate to times page
        driver.get(times_url)
        time.sleep(2)

        # Map event names to dropdown values
        event_map = {
            "50 Free": "1|50|1",
            "100 Free": "1|100|1",
            "200 Free": "1|200|1",
            "500 Free": "1|500|1",
            "1000 Free": "1|1000|1",
            "1650 Free": "1|1650|1",
            "100 Back": "2|100|1",
            "200 Back": "2|200|1",
            "100 Breast": "3|100|1",
            "200 Breast": "3|200|1",
            "100 Fly": "4|100|1",
            "200 Fly": "4|200|1",
            "200 IM": "5|200|1",
            "400 IM": "5|400|1",
        }

        event_value = event_map.get(event_name)
        if not event_value:
            return times_data

        # Find and select the event from dropdown
        try:
            wait = WebDriverWait(driver, 10)
            event_select = wait.until(EC.presence_of_element_located((By.ID, "select_1")))
            select = Select(event_select)
            select.select_by_value(event_value)
            time.sleep(2)  # Wait for page to update
        except Exception as e:
            # If dropdown not found, skip this event
            return times_data

        # Scrape the times for this event
        html = driver.page_source
        soup = BeautifulSoup(html, "html.parser")

        table = soup.find("table", class_="c-table-clean")
        if not table:
            return times_data

        tbody = table.find("tbody")
        if not tbody:
            return times_data

        rows = tbody.find_all("tr")

        for idx, row in enumerate(rows[:10], 1):
            cells = row.find_all("td")
            if len(cells) >= 4:
                # Swimmer name
                swimmer_link = cells[1].find("a")
                swimmer_name = swimmer_link.get_text(strip=True) if swimmer_link else ""

                # Meet name
                meet_link = cells[2].find("a")
                meet_name = meet_link.get_text(strip=True) if meet_link else ""

                # Time
                time_link = cells[3].find("a")
                time_value = time_link.get_text(strip=True) if time_link else ""

                # Year (class year)
                year = cells[1].get_text(strip=True).split()[-1] if cells[1] else ""
                if year and year.startswith('(') and year.endswith(')'):
                    year = year[1:-1]
                else:
                    year = ""

                if time_value:
                    times_data[f"rank{idx}_time"] = time_value
                    times_data[f"rank{idx}_swimmer"] = swimmer_name
                    times_data[f"rank{idx}_meet"] = meet_name
                    times_data[f"rank{idx}_year"] = year

    except Exception as e:
        print(f"        Error: {e}")

    return times_data

def scrape_all_events(driver, team_url, gender="M"):
    """Scrape top 10 for all events for given gender"""
    all_times = {}
    gender_prefix = "mens" if gender == "M" else "womens"
    gender_name = "Men" if gender == "M" else "Women"

    print(f"    [{gender_name}] Scraping events...")

    for event_key, event_name in EVENTS_TO_SCRAPE:
        print(f"      • {event_name}...", end=" ", flush=True)

        event_times = scrape_event_top10(driver, team_url, event_key, event_name, gender)

        for key, value in event_times.items():
            full_key = f"{gender_prefix}_{event_key}_{key}"
            all_times[full_key] = value

        times_count = len([k for k in event_times.keys() if k.endswith('_time')])
        print(f"✓ {times_count}")

    return all_times

def scrape_school_complete(driver, school_info, index, total):
    """Scrape complete data for one school"""
    print(f"\n{'='*80}")
    print(f"[{index}/{total}] {school_info['name']}")
    print('='*80)

    data = {**school_info}

    # 1. Basic info (division, conference)
    print("  [1/6] Basic info...")
    basic = scrape_basic_info(driver, school_info['url'])
    data.update(basic)

    # 2. About page (website, address, description, etc.)
    print("  [2/6] About page...")
    about = scrape_about_page(driver, school_info['url'])
    data.update(about)

    # 3. Roster (athletes, team availability, rankings)
    print("  [3/6] Roster & Rankings...")
    roster = scrape_roster(driver, school_info['url'])
    data.update(roster)

    if roster.get("national_ranking"):
        print(f"      National ranking: #{roster['national_ranking']}")

    # 4. Swimming coaches (with emails)
    print("  [4/6] Swimming coaches...")
    coaches = scrape_coaches(driver, school_info['url'])
    data.update(coaches)
    coach_count = len([k for k in coaches.keys() if 'name' in k and coaches[k]])
    if coach_count > 0:
        print(f"      Found {coach_count} coaches")

    # 5. Men's times (if team exists)
    if data.get("has_mens_team", False):
        print("  [5/6] Men's top 10 times per event...")
        mens_times = scrape_all_events(driver, school_info['url'], gender="M")
        data.update(mens_times)
    else:
        print("  [5/6] No men's team, skipping...")

    # 6. Women's times (if team exists)
    if data.get("has_womens_team", False):
        print("  [6/6] Women's top 10 times per event...")
        womens_times = scrape_all_events(driver, school_info['url'], gender="F")
        data.update(womens_times)
    else:
        print("  [6/6] No women's team, skipping...")

    print(f"\n  ✓ Collected {len(data)} fields for {school_info['name']}")

    return data

def organize_data(input_file):
    """Reorganize scraped data into clean, separate CSV files"""
    print(f"\n{'='*80}")
    print("STEP 2: ORGANIZING DATA INTO CLEAN FILES")
    print("="*80)

    # Read the complete data
    with open(input_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        all_data = list(reader)

    print(f"\nOrganizing {len(all_data)} schools...")

    # 1. Create schools_info.csv
    print("\n  [1/3] Creating missing_schools_info.csv...")
    info_fields = [
        'name', 'abbreviation', 'team_id', 'url', 'logo_url', 'website_url',
        'city', 'state', 'zip_code', 'address', 'division', 'conference',
        'national_ranking', 'conference_ranking', 'has_mens_team', 'has_womens_team',
        'total_athletes', 'founded_year', 'ncaa_id', 'description', 'facilities_description',
        'head_coach_name', 'head_coach_email',
        'assistant_coach_1_name', 'assistant_coach_1_email', 'assistant_coach_1_position',
        'assistant_coach_2_name', 'assistant_coach_2_email', 'assistant_coach_2_position',
        'assistant_coach_3_name', 'assistant_coach_3_email', 'assistant_coach_3_position',
        'all_coaches_json'
    ]

    with open('missing_schools_info.csv', 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=info_fields, extrasaction='ignore')
        writer.writeheader()
        for school in all_data:
            row = {k: school.get(k, '') for k in info_fields}
            writer.writerow(row)

    print(f"      ✓ {len(all_data)} schools × {len(info_fields)} columns")

    # 2. Create schools_mens_times.csv
    print("  [2/3] Creating missing_schools_mens_times.csv...")
    mens_times_data = []

    for school in all_data:
        school_name = school.get('name', '')
        team_id = school.get('team_id', '')

        for key, value in school.items():
            if key.startswith('mens_') and '_rank' in key and value:
                parts = key.replace('mens_', '').split('_')

                rank_idx = None
                for i, part in enumerate(parts):
                    if part.startswith('rank'):
                        rank_idx = i
                        break

                if rank_idx:
                    event = '_'.join(parts[:rank_idx])
                    rank_num = parts[rank_idx].replace('rank', '')
                    field_type = '_'.join(parts[rank_idx+1:])

                    existing = None
                    for t in mens_times_data:
                        if (t['school_name'] == school_name and
                            t['event'] == event.replace('_', ' ').title() and
                            t['rank'] == int(rank_num)):
                            existing = t
                            break

                    if existing:
                        existing[field_type] = value
                    else:
                        new_entry = {
                            'school_name': school_name,
                            'team_id': team_id,
                            'event': event.replace('_', ' ').title(),
                            'rank': int(rank_num),
                            'time': '',
                            'swimmer': '',
                            'meet': '',
                            'year': ''
                        }
                        new_entry[field_type] = value
                        mens_times_data.append(new_entry)

    if mens_times_data:
        mens_times_data.sort(key=lambda x: (x['school_name'], x['event'], x['rank']))
        mens_fields = ['school_name', 'team_id', 'event', 'rank', 'time', 'swimmer', 'year', 'meet']
        with open('missing_schools_mens_times.csv', 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=mens_fields, extrasaction='ignore')
            writer.writeheader()
            for entry in mens_times_data:
                writer.writerow(entry)
        print(f"      ✓ {len(mens_times_data)} time entries")

    # 3. Create schools_womens_times.csv
    print("  [3/3] Creating missing_schools_womens_times.csv...")
    womens_times_data = []

    for school in all_data:
        school_name = school.get('name', '')
        team_id = school.get('team_id', '')

        for key, value in school.items():
            if key.startswith('womens_') and '_rank' in key and value:
                parts = key.replace('womens_', '').split('_')

                rank_idx = None
                for i, part in enumerate(parts):
                    if part.startswith('rank'):
                        rank_idx = i
                        break

                if rank_idx:
                    event = '_'.join(parts[:rank_idx])
                    rank_num = parts[rank_idx].replace('rank', '')
                    field_type = '_'.join(parts[rank_idx+1:])

                    existing = None
                    for t in womens_times_data:
                        if (t['school_name'] == school_name and
                            t['event'] == event.replace('_', ' ').title() and
                            t['rank'] == int(rank_num)):
                            existing = t
                            break

                    if existing:
                        existing[field_type] = value
                    else:
                        new_entry = {
                            'school_name': school_name,
                            'team_id': team_id,
                            'event': event.replace('_', ' ').title(),
                            'rank': int(rank_num),
                            'time': '',
                            'swimmer': '',
                            'meet': '',
                            'year': ''
                        }
                        new_entry[field_type] = value
                        womens_times_data.append(new_entry)

    if womens_times_data:
        womens_times_data.sort(key=lambda x: (x['school_name'], x['event'], x['rank']))
        womens_fields = ['school_name', 'team_id', 'event', 'rank', 'time', 'swimmer', 'year', 'meet']
        with open('missing_schools_womens_times.csv', 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=womens_fields, extrasaction='ignore')
            writer.writeheader()
            for entry in womens_times_data:
                writer.writerow(entry)
        print(f"      ✓ {len(womens_times_data)} time entries")

    print(f"\n✓ Data organized into 3 clean CSV files!")
    print(f"  • missing_schools_info.csv - School information")
    print(f"  • missing_schools_mens_times.csv - Men's top 10 times per event")
    print(f"  • missing_schools_womens_times.csv - Women's top 10 times per event")

def main():
    print("\n" + "="*80)
    print("MISSING SCHOOLS SWIMCLOUD COMPREHENSIVE SCRAPER")
    print("="*80)

    print(f"\nTarget schools to scrape: {len(TARGET_SCHOOLS)}")
    print(f"Season: 2024-2025 (ID: 29)")
    print(f"Course: Yards (Y)")

    # Prepare schools list with URLs
    schools = []
    for school_config in TARGET_SCHOOLS:
        name = school_config['name']
        team_id = school_config['team_id']
        url = f"{BASE_URL}/team/{team_id}/"

        schools.append({
            "name": name,
            "team_id": team_id,
            "url": url,
            "logo_url": ""  # Will be scraped if needed
        })

    print("\n" + "="*80)
    print(f"STEP 1: SCRAPING {len(schools)} SCHOOLS IN DETAIL")
    print("="*80)

    driver = setup_driver()

    try:
        # Scrape each school
        all_data = []
        for i, school in enumerate(schools, 1):
            try:
                school_data = scrape_school_complete(driver, school, i, len(schools))
                all_data.append(school_data)
            except Exception as e:
                print(f"\n  ✗ Error scraping {school['name']}: {e}")
                # Continue with next school
                continue

            time.sleep(1)  # Delay between schools

        # Save intermediate raw data
        print(f"\n{'='*80}")
        print("SAVING RAW DATA")
        print("="*80)

        if all_data:
            # Get all unique fields
            all_fields = set()
            for school in all_data:
                all_fields.update(school.keys())

            fieldnames = sorted(list(all_fields))

            output_file = "missing_schools_complete.csv"
            with open(output_file, "w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(f, fieldnames=fieldnames)
                writer.writeheader()
                for school in all_data:
                    writer.writerow(school)

            print(f"\n✓ Saved {len(all_data)} schools to {output_file}")
            print(f"✓ Total fields per school: {len(fieldnames)}")

            # Step 2: Organize data into clean files
            organize_data(output_file)

    except Exception as e:
        print(f"\n✗ Fatal error: {e}")
        import traceback
        traceback.print_exc()
    finally:
        driver.quit()

    print("\n" + "="*80)
    print("ALL DONE! 🏊‍♂️🏊‍♀️")
    print("="*80)
    print("\nYour missing schools data is ready in 4 files:")
    print("  1. missing_schools_complete.csv - Complete raw data")
    print("  2. missing_schools_info.csv - School information (easy to read)")
    print("  3. missing_schools_mens_times.csv - Men's top 10 times organized by event")
    print("  4. missing_schools_womens_times.csv - Women's top 10 times organized by event")
    print("="*80 + "\n")

if __name__ == "__main__":
    main()
