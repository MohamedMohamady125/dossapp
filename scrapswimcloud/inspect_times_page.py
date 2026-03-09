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

driver = setup_driver()

try:
    # Check the /times/ page instead of /rankings/
    url = "https://www.swimcloud.com/team/105/times/?gender=M&season=29&event_course=Y"
    print(f"Fetching: {url}")

    driver.get(url)
    time.sleep(5)

    html = driver.page_source

    with open("team_times_page_debug.html", "w", encoding="utf-8") as f:
        f.write(html)

    print("Saved to team_times_page_debug.html")

    soup = BeautifulSoup(html, "html.parser")

    # Count table rows
    tables = soup.find_all("table")
    print(f"\nFound {len(tables)} table(s)")

    for i, table in enumerate(tables[:2]):
        rows = table.find_all("tr")
        print(f"  Table {i+1}: {len(rows)} rows")

        # Show first few rows
        print(f"\n  First 5 rows of table {i+1}:")
        for row in rows[:5]:
            cells = row.find_all(["th", "td"])
            row_text = " | ".join([c.get_text(strip=True)[:30] for c in cells[:5]])
            print(f"    {row_text}")

    # Check if there are swimmer rows
    if "50 Free" in html:
        print("\n✓ Found event data")

    # Count how many times we see specific swimmers
    import re
    gould_count = len(re.findall(r'Gould, Garrett', html))
    print(f"\nFound 'Gould, Garrett' {gould_count} times in the page")

finally:
    driver.quit()
