from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
from bs4 import BeautifulSoup
import csv
import time

BASE_URL = "https://www.swimcloud.com"
TEAMS_URL = "https://www.swimcloud.com/country/usa/teams/?eventCourse=Y&gender=M&page=1&rankType=D&region=division_1&seasonId=29&sortBy=top50"

def fetch_html_with_selenium(url):
    # Set up Chrome options
    chrome_options = Options()
    chrome_options.add_argument("--headless")  # Run in background
    chrome_options.add_argument("--no-sandbox")
    chrome_options.add_argument("--disable-dev-shm-usage")
    chrome_options.add_argument("user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")

    driver = webdriver.Chrome(options=chrome_options)

    try:
        driver.get(url)
        # Wait for the rankings div to load
        wait = WebDriverWait(driver, 20)
        wait.until(EC.presence_of_element_located((By.ID, "rankings")))

        # Wait a bit more for dynamic content to load
        time.sleep(5)

        html = driver.page_source
        return html
    finally:
        driver.quit()

def parse_teams(html):
    soup = BeautifulSoup(html, "html.parser")
    teams = []

    # Find the table
    table = soup.find("table", class_="c-table-clean")
    if not table:
        print("Table not found!")
        return teams

    # Find all rows in tbody
    tbody = table.find("tbody")
    if not tbody:
        print("tbody not found!")
        return teams

    rows = tbody.find_all("tr")
    print(f"Found {len(rows)} team rows")

    for row in rows:
        try:
            cells = row.find_all("td")
            if len(cells) < 3:
                continue

            # Extract rank
            rank = cells[0].get_text(strip=True)

            # Extract team info from second cell
            team_link = cells[1].find("a", href=lambda x: x and x.startswith("/team/"))
            if not team_link:
                continue

            team_url = BASE_URL + team_link.get("href", "")
            full_name = team_link.get("title", "")
            short_name = team_link.find("strong")
            team_name = short_name.get_text(strip=True) if short_name else full_name

            # Extract points from third cell
            points_link = cells[2].find("a")
            points = points_link.get_text(strip=True) if points_link else ""

            teams.append({
                "rank": rank,
                "name": team_name,
                "full_name": full_name,
                "url": team_url,
                "points": points
            })

        except Exception as e:
            print(f"Error parsing row: {e}")
            continue

    return teams

def save_to_csv(teams):
    with open("teams.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["rank", "name", "full_name", "url", "points"])
        writer.writeheader()
        for t in teams:
            writer.writerow(t)

def main():
    print("Fetching page with Selenium...")
    html = fetch_html_with_selenium(TEAMS_URL)

    # Save for inspection
    with open("debug_selenium.html", "w", encoding="utf-8") as f:
        f.write(html)
    print("HTML saved to debug_selenium.html")

    teams = parse_teams(html)
    save_to_csv(teams)
    print(f"\nSaved {len(teams)} teams to teams.csv")

if __name__ == "__main__":
    main()
