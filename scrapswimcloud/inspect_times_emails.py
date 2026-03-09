from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from bs4 import BeautifulSoup
import time

def setup_driver():
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument("user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
    return webdriver.Chrome(options=chrome_options)

def fetch_page(driver, url):
    driver.get(url)
    time.sleep(5)
    return driver.page_source

# Check Texas team for times and emails
driver = setup_driver()

try:
    # 1. Check main team page for times
    print("="*60)
    print("CHECKING MAIN TEAM PAGE")
    print("="*60)
    url = "https://www.swimcloud.com/team/105"
    html = fetch_page(driver, url)
    soup = BeautifulSoup(html, "html.parser")

    # Look for times/rankings sections
    print("\nLooking for 'Times' or 'Rankings' links...")
    nav_items = soup.find_all("a", class_="c-nav__item")
    for item in nav_items:
        text = item.get_text(strip=True)
        href = item.get("href", "")
        print(f"  - {text}: {href}")

    # 2. Check rankings/times page
    print("\n" + "="*60)
    print("CHECKING RANKINGS PAGE")
    print("="*60)
    rankings_url = "https://www.swimcloud.com/team/105/rankings/"
    html = fetch_page(driver, rankings_url)

    with open("team_rankings_debug.html", "w", encoding="utf-8") as f:
        f.write(html)
    print("Saved to team_rankings_debug.html")

    soup = BeautifulSoup(html, "html.parser")

    # Look for event times
    tables = soup.find_all("table")
    print(f"\nFound {len(tables)} tables")

    # Look for specific patterns
    if "100" in html and "Free" in html:
        print("✓ Found event data (e.g., '100 Free')")

    # 3. Check coaches page for emails
    print("\n" + "="*60)
    print("CHECKING COACHES PAGE FOR EMAILS")
    print("="*60)
    coaches_url = "https://www.swimcloud.com/team/105/coaches/"
    html = fetch_page(driver, coaches_url)

    with open("team_coaches_emails_debug.html", "w", encoding="utf-8") as f:
        f.write(html)
    print("Saved to team_coaches_emails_debug.html")

    soup = BeautifulSoup(html, "html.parser")

    # Search for email patterns
    import re
    email_pattern = r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'
    emails_found = re.findall(email_pattern, html)

    if emails_found:
        print(f"\n✓ Found {len(emails_found)} email(s):")
        for email in set(emails_found):
            print(f"  - {email}")
    else:
        print("\n✗ No emails found on coaches page")

    # Look for mailto links
    mailto_links = soup.find_all("a", href=lambda x: x and "mailto:" in str(x))
    print(f"\nFound {len(mailto_links)} mailto links")
    for link in mailto_links:
        print(f"  - {link.get('href', '')}")

    # 4. Check individual coach page
    print("\n" + "="*60)
    print("CHECKING INDIVIDUAL COACH PAGE")
    print("="*60)

    # Find first coach link
    coach_cards = soup.find_all("div", class_="c-card")
    for card in coach_cards:
        media_body = card.find("div", class_="o-media__body")
        if media_body:
            name_elem = media_body.find("h3")
            if name_elem:
                coach_link = name_elem.find("a")
                if coach_link and coach_link.get("href"):
                    coach_url = "https://www.swimcloud.com" + coach_link.get("href")
                    print(f"\nChecking coach page: {coach_url}")

                    coach_html = fetch_page(driver, coach_url)
                    with open("individual_coach_debug.html", "w", encoding="utf-8") as f:
                        f.write(coach_html)
                    print("Saved to individual_coach_debug.html")

                    # Check for email
                    coach_emails = re.findall(email_pattern, coach_html)
                    if coach_emails:
                        print(f"✓ Found email(s) on coach page:")
                        for email in set(coach_emails):
                            print(f"  - {email}")

                    break

finally:
    driver.quit()

print("\n" + "="*60)
print("INSPECTION COMPLETE")
print("="*60)
