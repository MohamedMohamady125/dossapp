# School Rankings Scraper

This script scrapes school rankings, conference information, and points for both men's and women's swimming teams from SwimCloud.

## Features

- ✅ Scrapes **men's and women's rankings** for Division 1 schools
- ✅ Extracts **national (division) rankings**
- ✅ Extracts **conference rankings**
- ✅ Collects **conference** and **division** information
- ✅ Handles pagination to scrape multiple pages of schools
- ✅ Saves data in multiple formats (CSV for men's, women's, and combined data + JSON)
- ✅ Progress tracking and error handling

## Output Files

The script generates 4 files:

1. **`school_rankings_combined_TIMESTAMP.csv`** - All data (men's and women's) in one file
2. **`school_rankings_mens_TIMESTAMP.csv`** - Men's rankings only
3. **`school_rankings_womens_TIMESTAMP.csv`** - Women's rankings only
4. **`school_rankings_TIMESTAMP.json`** - Complete data in JSON format with metadata

## Data Columns

### Combined CSV
- `name` - School name
- `team_id` - SwimCloud team ID
- `url` - Team URL
- `conference` - Conference name
- `division` - Division (e.g., "Division 1", "Division 1 Mid-Major")
- `mens_national_rank` - Men's division ranking
- `mens_conference_rank` - Men's conference ranking
- `mens_points` - Men's points (if available)
- `womens_national_rank` - Women's division ranking
- `womens_conference_rank` - Women's conference ranking
- `womens_points` - Women's points (if available)

## Requirements

```bash
pip install selenium beautifulsoup4 pandas
```

You also need ChromeDriver installed on your system.

## Usage

### Basic Usage (Scrape 3 pages = ~150 schools)

```bash
python3 schools_rankings_scrap.py
```

### Custom Usage

```python
from schools_rankings_scrap import SchoolRankingsScraper

# Initialize scraper
scraper = SchoolRankingsScraper(season_id="29")  # 29 = 2025-2026 season

# Scrape specific number of teams/pages
data = scraper.scrape_all_teams(
    max_pages=5,      # Number of pages to scrape (50 teams per page)
    max_teams=100     # Max total teams to scrape (leave as None for all)
)

# View summary
scraper.print_summary(data)

# Save to files
scraper.save_to_csv(data)
```

### Examples

```python
# Scrape just 10 teams for testing
data = scraper.scrape_all_teams(max_teams=10, max_pages=1)

# Scrape first 50 teams (1 page)
data = scraper.scrape_all_teams(max_pages=1)

# Scrape all Division 1 teams (adjust max_pages as needed)
data = scraper.scrape_all_teams(max_pages=10, max_teams=None)
```

## Season IDs

To scrape different seasons, change the `season_id` parameter:

- `29` = 2025-2026 season
- `28` = 2024-2025 season
- `27` = 2023-2024 season
- etc.

## Performance

- Each school requires 2 page loads (men's + women's rankings)
- With delays, expect ~5-10 seconds per school
- 150 schools ≈ 12-25 minutes
- Adjust `time.sleep()` values in the code if you want faster/slower scraping

## Notes

- The script scrapes Division 1 teams by default
- Rankings shown are for "Dual Meet" type (not Championship)
- Points data may not always be available on the rankings page
- Rankings of "50" typically indicate teams outside the top 50
- Conference rankings may be empty for some teams
- The script runs in headless mode (no browser window)

## Troubleshooting

### "No teams found"
- Check internet connection
- Verify SwimCloud website is accessible
- The website structure may have changed

### ChromeDriver errors
- Make sure ChromeDriver is installed and in your PATH
- Update ChromeDriver to match your Chrome browser version

### Slow performance
- Reduce `time.sleep()` values (but be respectful to the server)
- Use `max_teams` parameter to limit scope

## Example Output

```
======================================================================
SCRAPING SUMMARY
======================================================================

Total Schools Scraped: 20
Schools with Men's Rankings: 20
Schools with Women's Rankings: 20

Top 5 Men's Schools:
  #2. Arizona State (Big 12) - N/A pts
  #13. Auburn (SEC) - N/A pts
  #14. Cornell (Ivy) - N/A pts
  #20. Brown (Ivy) - N/A pts
  #21. Columbia (Ivy) - N/A pts

Top 5 Women's Schools:
  #4. Brown (Ivy) - N/A pts
  #17. Arizona State (Big 12) - N/A pts
  #18. Auburn (SEC) - N/A pts
  #22. Ball State (Missouri Valley) - N/A pts
  #41. Cornell (Ivy) - N/A pts
======================================================================
```

## Modifying for Other Divisions

To scrape Division 2, Division 3, etc., modify the `teams_list_url` in the `__init__` method:

```python
# Division 2
self.teams_list_url = f"https://www.swimcloud.com/country/usa/teams/?eventCourse=Y&rankType=D&region=division_2&seasonId={season_id}&sortBy=all&gender=M&page="

# Division 3
self.teams_list_url = f"https://www.swimcloud.com/country/usa/teams/?eventCourse=Y&rankType=D&region=division_3&seasonId={season_id}&sortBy=all&gender=M&page="
```

## License

This script is for educational purposes. Be respectful when scraping and follow SwimCloud's terms of service.

## Author

Created for scraping SwimCloud school rankings data.
