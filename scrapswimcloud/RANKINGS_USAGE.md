# School Rankings Script - Usage Guide

Simple script to get men's and women's rankings for each school.

## File: `get_school_rankings.py`

Shows national ranking and conference ranking for both men's and women's teams.

---

## Usage

### 1. Display All Schools
Show rankings for all 63 schools:

```bash
python3 get_school_rankings.py
```

**Output:**
- Table with all schools
- Men's national and conference rankings
- Women's national and conference rankings
- Summary statistics

---

### 2. Search Specific School
Get rankings for one school:

```bash
python3 get_school_rankings.py Auburn
```

**Output:**
```
RANKINGS FOR: Auburn
Conference: SEC
Division: Division 1

MEN'S TEAM:
  National Ranking:    #3
  Conference Ranking:  #1

WOMEN'S TEAM:
  National Ranking:    #3
  Conference Ranking:  #1
```

---

### 3. Export to CSV
Export all rankings to a CSV file:

```bash
python3 get_school_rankings.py export
```

**Creates:** `school_rankings_export.csv`

**Format:**
```csv
School,Conference,Mens_National_Rank,Mens_Conference_Rank,Womens_National_Rank,Womens_Conference_Rank
American,Patriot,1,1,1,1
Arizona State,Big 12,2,1,2,1
Auburn,SEC,3,1,3,1
...
```

---

## Data Source

**File:** `mens_womens_rankings.csv`

**Contains:**
- 63 schools total
- 50 men's teams
- 50 women's teams
- 37 schools with both teams
- 21 conferences

---

## Examples

### Check your school:
```bash
python3 get_school_rankings.py "Arizona State"
python3 get_school_rankings.py Brown
python3 get_school_rankings.py "Boston College"
```

### View all and export:
```bash
python3 get_school_rankings.py > all_rankings.txt
python3 get_school_rankings.py export
```

---

## Output Columns

| Column | Description |
|--------|-------------|
| School | School name |
| Conference | Conference affiliation |
| Men's National | National ranking for men's team (or N/A) |
| Men's Conference | Conference ranking for men's team (or N/A) |
| Women's National | National ranking for women's team (or N/A) |
| Women's Conference | Conference ranking for women's team (or N/A) |

---

## Sample Output

```
School              Conference    Men's National  Men's Conference  Women's National  Women's Conference
American            Patriot       #1              #1                #1                #1
Arizona State       Big 12        #2              #1                #2                #1
Auburn              SEC           #3              #1                #3                #1
Indiana             Big Ten       #38             #1                N/A               N/A
Butler              Big East      N/A             N/A               #14               #1
```

---

## Notes

- **N/A** means the school doesn't have a team in that category
- Rankings are for NCAA Division 1 swimming
- Conference rankings show position within their conference
- National rankings show overall position across all D1 schools

---

## Quick Reference

```bash
# View all schools
python3 get_school_rankings.py

# Search one school
python3 get_school_rankings.py [SchoolName]

# Export to CSV
python3 get_school_rankings.py export
```

---

**That's it! Simple and focused on getting the rankings you need.**
