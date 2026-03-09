#!/usr/bin/env python3
"""
SwimCloud School Rankings Scraper
Scrapes rankings, conference, and points for both men's and women's teams
by visiting each team's individual rankings page.
"""

import time
import json
from datetime import datetime
from selenium import webdriver
from bs4 import BeautifulSoup
import pandas as pd
import re

class SchoolRankingsScraper:
    def __init__(self, season_id="29"):
        """Initialize the scraper with Chrome options"""
        self.chrome_options = webdriver.ChromeOptions()
        self.chrome_options.add_argument('--headless')  # Run in background
        self.chrome_options.add_argument('--no-sandbox')
        self.chrome_options.add_argument('--disable-dev-shm-usage')
        self.chrome_options.add_argument('--disable-blink-features=AutomationControlled')
        self.chrome_options.add_argument('user-agent=Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36')

        self.base_url = "https://www.swimcloud.com"
        self.season_id = season_id
        self.teams_list_url = f"https://www.swimcloud.com/country/usa/teams/?eventCourse=Y&rankType=D&region=division_1&seasonId={season_id}&sortBy=all&gender=M&page="

    def get_teams_list(self, driver, max_pages=3):
        """Get list of all teams"""
        print("\n" + "="*70)
        print("GETTING TEAMS LIST")
        print("="*70)

        teams = []
        page = 1

        while page <= max_pages:
            url = self.teams_list_url + str(page)
            print(f"\nPage {page}: {url}")

            try:
                driver.get(url)
                time.sleep(2)

                html = driver.page_source
                soup = BeautifulSoup(html, "html.parser")

                table = soup.find("table", class_="c-table-clean")
                if not table:
                    print(f"  No table found on page {page}")
                    break

                tbody = table.find("tbody")
                if not tbody:
                    print(f"  No tbody found on page {page}")
                    break

                rows = tbody.find_all("tr")
                if not rows:
                    print(f"  No rows found on page {page}")
                    break

                for row in rows:
                    cells = row.find_all("td")
                    if len(cells) >= 1:
                        team_cell = cells[0]
                        team_link = team_cell.find("a")
                        if team_link:
                            name = team_link.get_text(strip=True)
                            href = team_link.get("href", "")
                            team_id = href.split("/")[-1] if href else ""
                            url = self.base_url + href

                            teams.append({
                                "name": name,
                                "team_id": team_id,
                                "url": url
                            })

                print(f"  ✓ Found {len(rows)} teams (Total so far: {len(teams)})")
                page += 1
                time.sleep(1)

            except Exception as e:
                print(f"  ✗ Error on page {page}: {e}")
                break

        print(f"\n✓ Total teams collected: {len(teams)}\n")
        return teams

    def _extract_rankings(self, soup, team_data, is_mens=True):
        """Helper method to extract rankings from parsed HTML"""
        # Find ranking cards
        ranking_cards = soup.find_all("div", class_="c-card")

        for card in ranking_cards:
            # Check for "Region Rankings" header
            header = card.find("h2", class_="c-title")
            if not header or "region" not in header.get_text(strip=True).lower():
                continue

            # Find all ranking links (o-media elements)
            media_elements = card.find_all("a", class_="o-media")

            for media in media_elements:
                # Get the label (Division 1, SEC, etc.)
                label_div = media.find("div", class_="u-color-mute")
                if not label_div:
                    continue

                label = label_div.get_text(strip=True).lower()

                # Get the ranking
                rank_div = media.find("div", class_="c-title")
                if not rank_div:
                    continue

                rank_text = rank_div.get_text(strip=True)
                # Extract number from "13th", "1st", etc.
                rank_match = re.search(r'(\d+)', rank_text)
                rank_num = rank_match.group(1) if rank_match else ""

                if not rank_num:
                    continue

                # Categorize the ranking
                if "division" in label:
                    if is_mens:
                        team_data["mens_national_rank"] = rank_num
                    else:
                        team_data["womens_national_rank"] = rank_num
                elif team_data["conference"] and team_data["conference"].lower() in label:
                    # This is a conference ranking
                    if is_mens:
                        team_data["mens_conference_rank"] = rank_num
                    else:
                        team_data["womens_conference_rank"] = rank_num

    def scrape_team_rankings(self, driver, team):
        """Scrape rankings for a specific team (both men and women)"""
        team_data = {
            "name": team["name"],
            "team_id": team["team_id"],
            "url": team["url"],
            "conference": "",
            "division": "",
            # Men's data
            "mens_national_rank": "",
            "mens_conference_rank": "",
            "mens_points": "",
            # Women's data
            "womens_national_rank": "",
            "womens_conference_rank": "",
            "womens_points": ""
        }

        try:
            # Get main team page for conference/division
            driver.get(team["url"])
            time.sleep(1)
            html = driver.page_source
            soup = BeautifulSoup(html, "html.parser")

            # Extract conference and division
            meta = soup.find("div", class_="c-toolbar__meta")
            if meta:
                links = meta.find_all("a")
                for link in links:
                    href = link.get("href", "")
                    text = link.get_text(strip=True)
                    if "/division/" in href:
                        team_data["division"] = text
                    elif "/conference/" in href:
                        team_data["conference"] = text

            # Get rankings page
            rankings_url = team["url"].rstrip("/") + f"/rankings/?season={self.season_id}"

            # Scrape Men's rankings first
            driver.get(rankings_url + "&gender=M")
            time.sleep(1.5)

            html = driver.page_source
            soup = BeautifulSoup(html, "html.parser")

            # Extract men's rankings
            self._extract_rankings(soup, team_data, is_mens=True)

            # Now get Women's rankings
            driver.get(rankings_url + "&gender=F")
            time.sleep(1.5)

            html = driver.page_source
            soup = BeautifulSoup(html, "html.parser")

            # Extract women's rankings
            self._extract_rankings(soup, team_data, is_mens=False)

        except Exception as e:
            print(f"    ✗ Error scraping {team['name']}: {e}")

        return team_data

    def scrape_all_teams(self, max_teams=None, max_pages=3):
        """Scrape rankings for all teams"""
        print("="*70)
        print("SwimCloud School Rankings Scraper")
        print("="*70)

        driver = webdriver.Chrome(options=self.chrome_options)
        all_data = []

        try:
            # Get list of teams
            teams = self.get_teams_list(driver, max_pages=max_pages)

            if max_teams:
                teams = teams[:max_teams]

            # Scrape each team
            print("="*70)
            print(f"SCRAPING RANKINGS FOR {len(teams)} TEAMS")
            print("="*70)

            for idx, team in enumerate(teams, 1):
                print(f"\n[{idx}/{len(teams)}] {team['name']}...", end=" ")

                team_data = self.scrape_team_rankings(driver, team)
                all_data.append(team_data)

                # Print summary
                mens_rank = team_data['mens_national_rank'] or 'N/A'
                womens_rank = team_data['womens_national_rank'] or 'N/A'
                conf = team_data['conference'] or 'N/A'
                print(f"✓ Men: #{mens_rank}, Women: #{womens_rank}, Conf: {conf}")

                time.sleep(0.5)  # Be respectful to the server

        finally:
            driver.quit()

        return all_data

    def save_to_csv(self, data, filename_prefix="school_rankings"):
        """Save data to CSV files"""
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

        if not data:
            print("\n✗ No data to save")
            return

        # Save combined data
        combined_filename = f"{filename_prefix}_combined_{timestamp}.csv"
        df_combined = pd.DataFrame(data)
        df_combined.to_csv(combined_filename, index=False)
        print(f"\n✓ Saved combined rankings to: {combined_filename}")

        # Save men's rankings (only teams with men's data)
        mens_data = [row for row in data if row['mens_national_rank'] or row['mens_conference_rank']]
        if mens_data:
            mens_filename = f"{filename_prefix}_mens_{timestamp}.csv"
            df_mens = pd.DataFrame(mens_data)
            # Select relevant columns
            mens_cols = ['name', 'team_id', 'url', 'conference', 'division',
                        'mens_national_rank', 'mens_conference_rank', 'mens_points']
            df_mens = df_mens[mens_cols]
            df_mens.to_csv(mens_filename, index=False)
            print(f"✓ Saved men's rankings to: {mens_filename}")

        # Save women's rankings (only teams with women's data)
        womens_data = [row for row in data if row['womens_national_rank'] or row['womens_conference_rank']]
        if womens_data:
            womens_filename = f"{filename_prefix}_womens_{timestamp}.csv"
            df_womens = pd.DataFrame(womens_data)
            # Select relevant columns
            womens_cols = ['name', 'team_id', 'url', 'conference', 'division',
                          'womens_national_rank', 'womens_conference_rank', 'womens_points']
            df_womens = df_womens[womens_cols]
            df_womens.to_csv(womens_filename, index=False)
            print(f"✓ Saved women's rankings to: {womens_filename}")

        # Save as JSON
        json_filename = f"{filename_prefix}_{timestamp}.json"
        with open(json_filename, 'w') as f:
            json.dump({
                'data': data,
                'scraped_at': datetime.now().isoformat(),
                'season_id': self.season_id,
                'total_teams': len(data),
                'teams_with_mens': len(mens_data) if mens_data else 0,
                'teams_with_womens': len(womens_data) if womens_data else 0
            }, f, indent=2)
        print(f"✓ Saved JSON data to: {json_filename}")

    def print_summary(self, data):
        """Print a summary of scraped data"""
        if not data:
            print("\n✗ No data scraped")
            return

        mens_teams = [d for d in data if d['mens_national_rank']]
        womens_teams = [d for d in data if d['womens_national_rank']]

        print("\n" + "="*70)
        print("SCRAPING SUMMARY")
        print("="*70)

        print(f"\nTotal Schools Scraped: {len(data)}")
        print(f"Schools with Men's Rankings: {len(mens_teams)}")
        print(f"Schools with Women's Rankings: {len(womens_teams)}")

        if mens_teams:
            print(f"\nTop 5 Men's Schools:")
            sorted_mens = sorted(mens_teams, key=lambda x: int(x['mens_national_rank']) if x['mens_national_rank'].isdigit() else 999)
            for school in sorted_mens[:5]:
                rank = school['mens_national_rank']
                name = school['name']
                conf = school['conference'] or 'N/A'
                pts = school['mens_points'] or 'N/A'
                print(f"  #{rank}. {name} ({conf}) - {pts} pts")

        if womens_teams:
            print(f"\nTop 5 Women's Schools:")
            sorted_womens = sorted(womens_teams, key=lambda x: int(x['womens_national_rank']) if x['womens_national_rank'].isdigit() else 999)
            for school in sorted_womens[:5]:
                rank = school['womens_national_rank']
                name = school['name']
                conf = school['conference'] or 'N/A'
                pts = school['womens_points'] or 'N/A'
                print(f"  #{rank}. {name} ({conf}) - {pts} pts")

        print("="*70)


def main():
    """Main execution function"""
    # Initialize scraper with season ID 29 (2025-2026 season)
    scraper = SchoolRankingsScraper(season_id="29")

    # Scrape all teams
    # Set max_pages to control how many pages of teams to scrape (each page has ~50 teams)
    # Set max_teams to limit total number of teams (useful for testing)
    data = scraper.scrape_all_teams(max_pages=3, max_teams=None)  # Change max_teams to a number for testing

    # Print summary
    scraper.print_summary(data)

    # Save to files
    if data:
        scraper.save_to_csv(data)
        print(f"\n✓ All data saved successfully!")
    else:
        print("\n✗ No data was scraped. Please check the website structure.")


if __name__ == "__main__":
    main()
