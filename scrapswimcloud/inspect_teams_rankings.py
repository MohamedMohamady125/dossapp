from selenium import webdriver
from selenium.webdriver.chrome.options import Options
from bs4 import BeautifulSoup
import time

def setup_driver():
    chrome_options = Options()
    chrome_options.add_argument("--headless")
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    return webdriver.Chrome(options=chrome_options)

# Check the teams listing page
url = "https://www.swimcloud.com/country/usa/teams/?eventCourse=Y&gender=M&page=1&rankType=D&region=division_1&seasonId=29&sortBy=all"

driver = setup_driver()
print(f"Fetching {url}...")
driver.get(url)
time.sleep(3)

html = driver.page_source
soup = BeautifulSoup(html, "html.parser")

# Save HTML for inspection
with open("teams_listing_debug.html", "w", encoding="utf-8") as f:
    f.write(soup.prettify())

print("HTML saved to teams_listing_debug.html")
print("\n=== Teams Listing Page Structure ===\n")

# Find the table
table = soup.find("table", class_="c-table-clean")
if table:
    print("Table found!")

    # Get headers
    thead = table.find("thead")
    if thead:
        headers = thead.find_all("th")
        print(f"\nTable headers ({len(headers)}):")
        for i, h in enumerate(headers):
            print(f"  [{i}] {h.get_text(strip=True)}")

    # Get first few rows
    tbody = table.find("tbody")
    if tbody:
        rows = tbody.find_all("tr")[:5]
        print(f"\nFirst 5 teams:")
        for i, row in enumerate(rows, 1):
            cells = row.find_all("td")
            print(f"\n  Team {i} - {len(cells)} cells:")
            for j, cell in enumerate(cells):
                text = cell.get_text(strip=True)
                if len(text) > 50:
                    text = text[:50] + "..."
                print(f"    Cell {j}: {text}")
else:
    print("No table found!")

driver.quit()
print("\nDone!")
