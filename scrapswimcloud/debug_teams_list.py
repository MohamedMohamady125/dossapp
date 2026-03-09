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

url = "https://www.swimcloud.com/country/usa/teams/?eventCourse=Y&gender=M&page=1&rankType=D&region=division_1&seasonId=29&sortBy=all"

driver = setup_driver()
driver.get(url)
time.sleep(4)

html = driver.page_source
soup = BeautifulSoup(html, "html.parser")

# Save HTML for inspection
with open("debug_teams_list_page.html", "w", encoding="utf-8") as f:
    f.write(html)

print("HTML saved to debug_teams_list_page.html")

# Find table
table = soup.find("table", class_="c-table-clean")
print(f"\nTable found: {table is not None}")

if table:
    tbody = table.find("tbody")
    print(f"Tbody found: {tbody is not None}")

    if tbody:
        rows = tbody.find_all("tr")
        print(f"Rows found: {len(rows)}")

        if rows:
            # Check first row
            first_row = rows[0]
            cells = first_row.find_all("td")
            print(f"\nFirst row cells: {len(cells)}")

            for i, cell in enumerate(cells[:5]):
                print(f"\nCell {i}:")
                print(f"  Text: {cell.get_text(strip=True)[:100]}")
                link = cell.find("a")
                if link:
                    print(f"  Link href: {link.get('href', 'N/A')}")
                img = cell.find("img")
                if img:
                    print(f"  Image src: {img.get('src', 'N/A')}")

driver.quit()
