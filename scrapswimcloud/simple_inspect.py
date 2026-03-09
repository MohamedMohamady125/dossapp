#!/usr/bin/env python3
import time
from selenium import webdriver
from selenium.webdriver.common.by import By

chrome_options = webdriver.ChromeOptions()
# chrome_options.add_argument('--headless')  # Run with browser visible for debugging
chrome_options.add_argument('--no-sandbox')
chrome_options.add_argument('--disable-dev-shm-usage')

driver = webdriver.Chrome(options=chrome_options)

try:
    url = "https://www.swimcloud.com/country/usa/teams/?eventCourse=Y&rankType=D&region=division_1&seasonId=29&sortBy=all&gender=M&page=1"
    print(f"Loading: {url}")

    driver.get(url)
    print("Page loaded, waiting 10 seconds for content...")
    time.sleep(10)

    # Save page source
    with open('rankings_debug.html', 'w', encoding='utf-8') as f:
        f.write(driver.page_source)
    print("✓ Saved to rankings_debug.html")

    # Try to find any data containers
    print("\nLooking for data containers...")

    # Check for common class names
    selectors = [
        '.c-table',
        '.table',
        'table',
        '[class*="table"]',
        '[class*="team"]',
        '[class*="rank"]',
        '.c-table__table',
        'tbody tr'
    ]

    for selector in selectors:
        try:
            elements = driver.find_elements(By.CSS_SELECTOR, selector)
            if elements:
                print(f"✓ Found {len(elements)} element(s) with selector: {selector}")
                if len(elements) <= 5:
                    for i, elem in enumerate(elements):
                        print(f"  Element {i+1} text preview: {elem.text[:100]}...")
        except Exception as e:
            print(f"✗ Error with selector {selector}: {e}")

finally:
    driver.quit()
