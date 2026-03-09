# Test version - only scrape first 3 teams
import sys
sys.path.insert(0, '.')

from scrapsc_full import *

def main():
    print("="*60)
    print("TESTING SCRAPER ON 3 TEAMS")
    print("="*60)

    # Step 1: Get rankings page
    print("\n[1/3] Fetching rankings page...")
    rankings_html = get_rankings_page()
    teams = parse_rankings(rankings_html)
    print(f"Found {len(teams)} teams total")

    # Only test on first 3 teams
    teams = teams[:3]
    print(f"Testing on first {len(teams)} teams")

    # Step 2: Scrape each team
    print(f"\n[2/3] Scraping details for {len(teams)} teams...")
    driver = setup_driver()
    all_team_data = []

    try:
        for i, team in enumerate(teams, 1):
            print(f"\n[{i}/{len(teams)}]", end=" ")
            team_data = scrape_team_details(driver, team)
            all_team_data.append(team_data)
            print(f"  ✓ Collected {len(team_data)} fields")
            time.sleep(2)
    finally:
        driver.quit()

    # Step 3: Save to CSV
    print(f"\n\n[3/3] Saving data to CSV...")
    if all_team_data:
        all_keys = set()
        for team in all_team_data:
            all_keys.update(team.keys())

        fieldnames = sorted(list(all_keys))

        with open("teams_test_data.csv", "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for team in all_team_data:
                writer.writerow(team)

        print(f"✓ Saved {len(all_team_data)} teams to teams_test_data.csv")
        print(f"✓ Total fields captured: {len(fieldnames)}")
        print(f"\nFields captured:")
        for field in sorted(fieldnames):
            print(f"  - {field}")
    else:
        print("✗ No data to save")

    print("\n" + "="*60)
    print("TEST COMPLETE!")
    print("="*60)

if __name__ == "__main__":
    main()
