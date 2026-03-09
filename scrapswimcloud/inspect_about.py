from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
from bs4 import BeautifulSoup
import time

def fetch_page(url):
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

# Fetch About, Coaches, and Roster pages
urls = {
    "about": "https://www.swimcloud.com/team/105/about/",
    "coaches": "https://www.swimcloud.com/team/105/coaches/",
    "roster": "https://www.swimcloud.com/team/105/roster/"
}

for page_name, url in urls.items():
    print(f"\n\n{'='*60}")
    print(f"Fetching {page_name.upper()}: {url}")
    print('='*60)

    html = fetch_page(url)

    # Save for inspection
    with open(f"team_{page_name}_debug.html", "w", encoding="utf-8") as f:
        f.write(html)
    print(f"Saved to team_{page_name}_debug.html")

    # Parse and print key info
    soup = BeautifulSoup(html, "html.parser")

    # Look for definition lists (dl/dt/dd) - common for team info
    dls = soup.find_all("dl")
    if dls:
        print(f"\nFound {len(dls)} definition lists:")
        for i, dl in enumerate(dls[:3]):
            print(f"\n  List {i+1}:")
            dts = dl.find_all("dt")
            dds = dl.find_all("dd")
            for dt, dd in zip(dts, dds):
                print(f"    {dt.get_text(strip=True)}: {dd.get_text(strip=True)[:100]}")

    # Look for tables
    tables = soup.find_all("table")
    if tables:
        print(f"\nFound {len(tables)} tables")
        for i, table in enumerate(tables[:1]):
            print(f"\n  Table {i+1} rows: {len(table.find_all('tr'))}")

    # Look for specific data fields
    text = soup.get_text()
    keywords = ["City:", "State:", "Address:", "Location:", "Phone:", "Enrollment:", "Founded:", "Mascot:", "Colors:", "Athletic Director:"]
    print("\nKeyword search:")
    for keyword in keywords:
        if keyword in text:
            print(f"  ✓ Found: {keyword}")
