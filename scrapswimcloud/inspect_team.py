from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
from bs4 import BeautifulSoup
import time

def fetch_team_page(url):
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument("user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

    driver = webdriver.Chrome(options=chrome_options)

    try:
        driver.get(url)
        time.sleep(5)  # Wait for content to load
        html = driver.page_source
        return html
    finally:
        driver.quit()

# Inspect Texas team page
url = "https://www.swimcloud.com/team/105"
print(f"Fetching {url}...")
html = fetch_team_page(url)

# Save for inspection
with open("team_page_debug.html", "w", encoding="utf-8") as f:
    f.write(html)
print("HTML saved to team_page_debug.html")

# Parse and print structure
soup = BeautifulSoup(html, "html.parser")

# Look for common data elements
print("\n=== Team Page Structure ===")

# Look for team name/header
headers = soup.find_all(["h1", "h2", "h3"])
print(f"\nHeaders found: {len(headers)}")
for h in headers[:10]:
    print(f"  {h.name}: {h.get_text(strip=True)[:100]}")

# Look for data tables
tables = soup.find_all("table")
print(f"\nTables found: {len(tables)}")

# Look for divs with classes containing info/detail/stat
info_divs = soup.find_all("div", class_=lambda x: x and any(term in str(x).lower() for term in ["info", "detail", "stat", "data", "profile"]))
print(f"\nInfo divs found: {len(info_divs)}")
for div in info_divs[:5]:
    print(f"  Classes: {div.get('class')}")
    print(f"  Content: {div.get_text(strip=True)[:100]}")

# Look for dl (definition lists)
dls = soup.find_all("dl")
print(f"\nDefinition lists found: {len(dls)}")
for dl in dls[:3]:
    print(f"  {dl.get_text(strip=True)[:200]}")
