# Quick Start Guide - School Rankings Scraper

## Run the Script

### Quick Test (20 schools)
```bash
python3 -c "
from schools_rankings_scrap import SchoolRankingsScraper
scraper = SchoolRankingsScraper(season_id='29')
data = scraper.scrape_all_teams(max_teams=20, max_pages=1)
scraper.print_summary(data)
scraper.save_to_csv(data)
"
```

### Full Scrape (All Division 1 - ~150 schools, takes 15-20 min)
```bash
python3 schools_rankings_scrap.py
```

### Custom Scrape
```bash
python3 -c "
from schools_rankings_scrap import SchoolRankingsScraper
scraper = SchoolRankingsScraper(season_id='29')
data = scraper.scrape_all_teams(max_pages=5, max_teams=None)  # 5 pages = ~250 schools
scraper.print_summary(data)
scraper.save_to_csv(data)
"
```

## Output Files

After running, you'll get:
- `school_rankings_combined_TIMESTAMP.csv` - All data
- `school_rankings_mens_TIMESTAMP.csv` - Men's only
- `school_rankings_womens_TIMESTAMP.csv` - Women's only
- `school_rankings_TIMESTAMP.json` - JSON format

## What You Get

For each school:
- School name, ID, and URL
- Conference and Division
- Men's national (division) rank
- Men's conference rank
- Women's national (division) rank
- Women's conference rank

## Sample Data

```csv
name,conference,division,mens_national_rank,mens_conference_rank,womens_national_rank,womens_conference_rank
Arizona State,Big 12,Division 1,2,1,17,1
Auburn,SEC,Division 1,13,4,18,7
Brown,Ivy,Division 1,20,1,4,1
```

Read SCHOOL_RANKINGS_README.md for full documentation!
