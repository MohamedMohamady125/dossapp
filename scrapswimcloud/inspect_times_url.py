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

driver = setup_driver()

# Test different event URLs
base_url = "https://www.swimcloud.com/team/214/times/?gender=M&season=29&event_course=Y"

print("Testing times URL structure...\n")

# Try to find event selector
driver.get(base_url)
time.sleep(3)

html = driver.page_source
soup = BeautifulSoup(html, "html.parser")

# Save the HTML
with open("times_page_structure.html", "w", encoding="utf-8") as f:
    f.write(html)

# Look for event selector/dropdown
print("Looking for event selectors...")
selects = soup.find_all("select")
for select in selects:
    print(f"\nSelect element: {select.get('name', 'no-name')} / {select.get('id', 'no-id')}")
    options = select.find_all("option")
    for opt in options[:5]:  # Show first 5 options
        print(f"  - {opt.get('value', 'no-value')}: {opt.get_text(strip=True)}")
    if len(options) > 5:
        print(f"  ... and {len(options) - 5} more options")

# Look for links with event filters
print("\n\nLooking for event filter links...")
links = soup.find_all("a", href=True)
event_links = [l for l in links if 'event' in l.get('href', '').lower()]
for link in event_links[:10]:
    print(f"  {link.get('href')}")

# Check the current page title
title = soup.find("h2", class_="c-title--small")
if title:
    print(f"\n\nCurrent page title: {title.get_text(strip=True)}")

driver.quit()

print("\n✓ HTML saved to times_page_structure.html")
