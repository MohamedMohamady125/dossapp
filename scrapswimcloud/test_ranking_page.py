#!/usr/bin/env python3
import time
from selenium import webdriver
from bs4 import BeautifulSoup

chrome_options = webdriver.ChromeOptions()
chrome_options.add_argument('--no-sandbox')
chrome_options.add_argument('--disable-dev-shm-usage')

driver = webdriver.Chrome(options=chrome_options)

try:
    # Test with Auburn (team 127)
    url = "https://www.swimcloud.com/team/127/rankings/?season=29"
    print(f"Loading: {url}\n")

    driver.get(url)
    time.sleep(3)

    # Save HTML
    with open('team_rankings_test.html', 'w', encoding='utf-8') as f:
        f.write(driver.page_source)
    print("✓ Saved to team_rankings_test.html\n")

    # Parse and show structure
    soup = BeautifulSoup(driver.page_source, 'html.parser')

    # Look for cards
    cards = soup.find_all("div", class_="c-card")
    print(f"Found {len(cards)} cards\n")

    for i, card in enumerate(cards[:3]):
        print(f"=== CARD {i+1} ===")

        # Get header
        header = card.find("h3") or card.find("h2") or card.find("div", class_="c-card__item")
        if header:
            print(f"Header: {header.get_text(strip=True)}")

        # Get dl elements
        dls = card.find_all("dl", class_="c-dl")
        print(f"DL elements: {len(dls)}")

        for j, dl in enumerate(dls[:5]):
            dt = dl.find("dt")
            dd = dl.find("dd")
            if dt and dd:
                print(f"  {dt.get_text(strip=True)}: {dd.get_text(strip=True)}")

        print()

finally:
    driver.quit()
