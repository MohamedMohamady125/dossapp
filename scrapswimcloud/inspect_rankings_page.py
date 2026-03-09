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

# Test with Auburn (team 127)
url = "https://www.swimcloud.com/team/127/rankings/?gender=M&season=29"

driver = setup_driver()
print(f"Fetching {url}...")
driver.get(url)
time.sleep(3)

html = driver.page_source
soup = BeautifulSoup(html, "html.parser")

# Save HTML for inspection
with open("rankings_page_debug.html", "w", encoding="utf-8") as f:
    f.write(soup.prettify())

print("HTML saved to rankings_page_debug.html")
print("\n=== Rankings Page Structure ===\n")

# Find all dl elements (definition lists)
dls = soup.find_all("dl", class_="c-dl")
print(f"Definition lists found: {len(dls)}\n")

for i, dl in enumerate(dls, 1):
    dt = dl.find("dt")
    dd = dl.find("dd")
    if dt and dd:
        print(f"  [{i}] {dt.get_text(strip=True)}: {dd.get_text(strip=True)}")

# Find any h2 or h3 headers
headers = soup.find_all(['h1', 'h2', 'h3'])
print(f"\nHeaders found: {len(headers)}")
for h in headers:
    print(f"  {h.name}: {h.get_text(strip=True)}")

# Look for any elements with "rank" in the text
print("\n=== Elements containing 'rank' ===")
rank_elements = soup.find_all(string=lambda text: text and 'rank' in text.lower())
for elem in rank_elements[:10]:  # Show first 10
    print(f"  {elem.strip()}")

driver.quit()
print("\nDone!")
