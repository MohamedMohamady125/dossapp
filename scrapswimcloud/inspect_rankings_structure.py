#!/usr/bin/env python3
"""
Inspect the structure of the rankings page to understand the HTML
"""

import time
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC

def inspect_page():
    chrome_options = webdriver.ChromeOptions()
    chrome_options.add_argument('--headless')
    chrome_options.add_argument('--no-sandbox')
    chrome_options.add_argument('--disable-dev-shm-usage')

    driver = webdriver.Chrome(options=chrome_options)

    try:
        url = "https://www.swimcloud.com/country/usa/teams/?eventCourse=Y&rankType=D&region=division_1&seasonId=29&sortBy=all&gender=M&page=1"
        print(f"Loading: {url}\n")

        driver.get(url)
        wait = WebDriverWait(driver, 15)
        wait.until(EC.presence_of_element_located((By.CSS_SELECTOR, "table")))
        time.sleep(3)

        # Save full page HTML
        with open('rankings_page_full.html', 'w', encoding='utf-8') as f:
            f.write(driver.page_source)
        print("✓ Saved full page HTML to: rankings_page_full.html\n")

        # Find all tables
        tables = driver.find_elements(By.TAG_NAME, "table")
        print(f"Found {len(tables)} table(s)\n")

        for i, table in enumerate(tables):
            print(f"=== TABLE {i+1} ===")
            print(f"Classes: {table.get_attribute('class')}")

            # Get first few rows
            rows = table.find_elements(By.TAG_NAME, "tr")
            print(f"Total rows: {len(rows)}\n")

            print("First 3 rows:")
            for j, row in enumerate(rows[:3]):
                cells = row.find_elements(By.TAG_NAME, "td")
                if not cells:
                    cells = row.find_elements(By.TAG_NAME, "th")

                print(f"  Row {j+1}: {len(cells)} cells")
                for k, cell in enumerate(cells):
                    print(f"    Cell {k+1}: '{cell.text[:50]}...' " if len(cell.text) > 50 else f"    Cell {k+1}: '{cell.text}'")
                    # Check for links
                    links = cell.find_elements(By.TAG_NAME, "a")
                    if links:
                        print(f"      → Has {len(links)} link(s)")
                        for link in links:
                            print(f"         href: {link.get_attribute('href')}")
                print()

            print("-" * 70)
            print()

    finally:
        driver.quit()

if __name__ == "__main__":
    inspect_page()
