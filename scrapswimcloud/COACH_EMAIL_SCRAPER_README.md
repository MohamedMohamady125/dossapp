# Coach Email Scraper - Usage Guide

## Overview
This package contains two scripts to scrape coaching staff emails from swimming school websites using the data in your `data/` folder.

## Scripts

### 1. `scrape_all_coach_emails.py` (Recommended for most users)
**Basic scraper using requests and BeautifulSoup**

- ✅ Faster execution
- ✅ Lower resource usage
- ✅ Works for most static websites
- ✅ No browser installation needed
- ❌ May miss JavaScript-loaded content

### 2. `scrape_coach_emails_advanced.py` (For advanced users)
**Advanced scraper with optional Selenium support**

- ✅ Handles JavaScript-loaded content
- ✅ Better context extraction
- ✅ More sophisticated email filtering
- ✅ Works on complex websites
- ❌ Slower execution
- ❌ Requires ChromeDriver for Selenium mode

## Installation

### Basic Requirements (for both scripts)
```bash
pip install requests beautifulsoup4
```

### Advanced Requirements (for Selenium support)
```bash
pip install selenium
```

You'll also need ChromeDriver:
- **Mac (via Homebrew)**: `brew install chromedriver`
- **Manual**: Download from [ChromeDriver Downloads](https://chromedriver.chromium.org/downloads)

## Usage

### Quick Start (Basic Script)
```bash
python scrape_all_coach_emails.py
```

This will:
1. Read all CSV files in the `data/` folder
2. Extract school names and website URLs
3. Scrape each website for coaching staff emails
4. Save results to timestamped CSV and JSON files

### Advanced Usage (Advanced Script)
```bash
python scrape_coach_emails_advanced.py
```

You'll be prompted to choose whether to use Selenium:
- **No**: Uses basic requests (faster)
- **Yes**: Uses Selenium browser automation (slower but more thorough)

## Input Files

The scripts automatically process these files from the `data/` folder:
- `schools_info_page2.csv`
- `schools_info_page3.csv`
- `schools_info_division2.csv`
- Any other `schools_info_*.csv` files

### Required CSV Columns
- `name`: School name
- `website_url`: School's athletics website
- `team_id`: (Optional) Team identifier

## Output Files

### CSV Output
`coach_emails_YYYYMMDD_HHMMSS.csv`
- One row per email found
- Includes school name, email, context, and URL where found

### JSON Output
`coach_emails_YYYYMMDD_HHMMSS.json`
- Detailed structured data
- Includes all pages checked and full context

### Progress Files
`coach_emails_progress_*.csv/json`
- Saved every 5-10 schools to prevent data loss

## Features

### Both Scripts
- ✅ Email validation and filtering
- ✅ Removes generic emails (info@, admin@, etc.)
- ✅ Finds coach/staff pages automatically
- ✅ Progress saving (prevents data loss)
- ✅ Detailed error logging
- ✅ Summary statistics

### Advanced Script Only
- ✅ Context extraction (text around email)
- ✅ Smart coach email detection
- ✅ Multiple scraping strategies
- ✅ JavaScript rendering (with Selenium)

## Customization

### Adjust Delay Between Requests
To be more/less aggressive, edit the `time.sleep()` values:

```python
# In scrape_all_coach_emails.py (line ~270)
time.sleep(2)  # Change to 1 for faster, 5 for slower

# Between schools
time.sleep(2)  # Delay between processing schools
```

### Filter Keywords
To target specific pages, edit the keywords:

```python
# In the __init__ method
self.staff_keywords = [
    'staff', 'coach', 'coaching', 'coaches',
    'swimming-and-diving', 'swim/staff',
    # Add more keywords here
]
```

### Maximum Pages to Check
To check more/fewer pages per school:

```python
# In find_coach_pages/find_staff_pages method
return potential_pages[:5]  # Change 5 to desired number
```

## Tips for Best Results

1. **Run during off-peak hours**: Less likely to be rate-limited
2. **Start with a small test**: Test on a few schools first
3. **Check progress files**: Monitor results during long runs
4. **Increase delays if blocked**: If getting errors, increase `time.sleep()` values
5. **Use advanced script for stubborn sites**: If basic script finds no emails

## Expected Runtime

For ~100 schools:
- **Basic script**: 10-20 minutes
- **Advanced script (no Selenium)**: 15-30 minutes
- **Advanced script (with Selenium)**: 30-60 minutes

## Troubleshooting

### "No module named 'requests'"
```bash
pip install requests beautifulsoup4
```

### "No module named 'selenium'"
```bash
pip install selenium
# Then install ChromeDriver (see Installation section)
```

### "ChromeDriver not found"
```bash
# Mac
brew install chromedriver

# Or download manually and add to PATH
```

### "No emails found"
- Some schools may not list emails publicly
- Try the advanced script with Selenium
- Check if the website URL is correct
- Some sites may block scrapers

### "Connection timeout"
- Increase timeout in the script
- Check your internet connection
- Try again later (site may be down)

## Output Statistics

After completion, you'll see:
- Total schools processed
- Number with emails found
- Number with no emails
- Error count
- Total emails discovered
- Average emails per school

## Example Output

```
================================================================================
📊 SCRAPING SUMMARY
================================================================================

🏫 Total Schools Processed: 45
✅ Successful (with emails): 32
⚠️  No emails found: 8
❌ Errors: 3
⏭️  Skipped: 2

📧 Total Emails Found: 87
📈 Average emails per school: 1.93
```

## Legal & Ethical Considerations

⚠️ **Important**:
- Only scrape publicly available information
- Respect robots.txt and terms of service
- Use reasonable delays between requests
- Don't overwhelm servers with requests
- Only use emails for legitimate recruiting purposes

## Support

For issues or questions:
1. Check the error messages in the output
2. Review the error log in the JSON output
3. Try the advanced script if basic one fails
4. Adjust delay times if getting rate-limited

## Files Generated

After running, you'll have:
```
coach_emails_20240126_153045.csv          # Main results (CSV)
coach_emails_20240126_153045.json         # Main results (JSON)
coach_emails_progress_*.csv               # Progress checkpoints
coach_emails_progress_*.json              # Progress checkpoints
```

Keep all files for reference and backup!
