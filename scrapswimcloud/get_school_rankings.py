#!/usr/bin/env python3
"""
Simple script to display men's and women's rankings for each school
Shows national ranking and conference ranking
"""

import pandas as pd
from tabulate import tabulate


def get_school_rankings():
    """Get and display rankings for all schools"""

    # Load data
    print("\nLoading rankings data...\n")
    df = pd.read_csv('mens_womens_rankings.csv')

    print("="*120)
    print("SCHOOL RANKINGS - MEN'S AND WOMEN'S")
    print("="*120)
    print(f"\nTotal Schools: {len(df)}\n")

    # Prepare table data
    table_data = []

    for _, row in df.iterrows():
        school_name = row['name']
        conference = row['conference']

        # Men's rankings
        if pd.notna(row['mens_division_rank']):
            mens_national = f"#{int(row['mens_division_rank'])}"
            mens_conf = f"#{int(row['mens_conference_rank'])}"
        else:
            mens_national = "N/A"
            mens_conf = "N/A"

        # Women's rankings
        if pd.notna(row['womens_division_rank']):
            womens_national = f"#{int(row['womens_division_rank'])}"
            womens_conf = f"#{int(row['womens_conference_rank'])}"
        else:
            womens_national = "N/A"
            womens_conf = "N/A"

        table_data.append([
            school_name,
            conference,
            mens_national,
            mens_conf,
            womens_national,
            womens_conf
        ])

    # Display table
    headers = [
        "School",
        "Conference",
        "Men's National",
        "Men's Conference",
        "Women's National",
        "Women's Conference"
    ]

    print(tabulate(table_data, headers=headers, tablefmt="grid"))

    # Summary statistics
    print("\n" + "="*120)
    print("SUMMARY")
    print("="*120)
    mens_count = df['mens_division_rank'].notna().sum()
    womens_count = df['womens_division_rank'].notna().sum()
    both_count = ((df['mens_division_rank'].notna()) & (df['womens_division_rank'].notna())).sum()

    print(f"Schools with Men's Team:    {mens_count}")
    print(f"Schools with Women's Team:  {womens_count}")
    print(f"Schools with Both Teams:    {both_count}")
    print(f"Total Conferences:          {df['conference'].nunique()}")
    print("="*120 + "\n")


def get_specific_school(school_name):
    """Get rankings for a specific school"""

    df = pd.read_csv('mens_womens_rankings.csv')

    # Find school (case insensitive)
    school_data = df[df['name'].str.contains(school_name, case=False, na=False)]

    if len(school_data) == 0:
        print(f"\nSchool '{school_name}' not found!")
        return

    row = school_data.iloc[0]

    print("\n" + "="*80)
    print(f"RANKINGS FOR: {row['name']}")
    print("="*80)
    print(f"Conference: {row['conference']}")
    print(f"Division: {row['division']}")

    print("\n" + "-"*80)
    print("MEN'S TEAM:")
    print("-"*80)
    if pd.notna(row['mens_division_rank']):
        print(f"  National Ranking:    #{int(row['mens_division_rank'])}")
        print(f"  Conference Ranking:  #{int(row['mens_conference_rank'])}")
    else:
        print("  No men's team ranked")

    print("\n" + "-"*80)
    print("WOMEN'S TEAM:")
    print("-"*80)
    if pd.notna(row['womens_division_rank']):
        print(f"  National Ranking:    #{int(row['womens_division_rank'])}")
        print(f"  Conference Ranking:  #{int(row['womens_conference_rank'])}")
    else:
        print("  No women's team ranked")

    print("="*80 + "\n")


def export_rankings_csv(output_file='school_rankings_export.csv'):
    """Export rankings to a simple CSV file"""

    df = pd.read_csv('mens_womens_rankings.csv')

    # Create export dataframe
    export_data = []

    for _, row in df.iterrows():
        export_data.append({
            'School': row['name'],
            'Conference': row['conference'],
            'Mens_National_Rank': int(row['mens_division_rank']) if pd.notna(row['mens_division_rank']) else '',
            'Mens_Conference_Rank': int(row['mens_conference_rank']) if pd.notna(row['mens_conference_rank']) else '',
            'Womens_National_Rank': int(row['womens_division_rank']) if pd.notna(row['womens_division_rank']) else '',
            'Womens_Conference_Rank': int(row['womens_conference_rank']) if pd.notna(row['womens_conference_rank']) else ''
        })

    export_df = pd.DataFrame(export_data)
    export_df.to_csv(output_file, index=False)

    print(f"\n✓ Rankings exported to {output_file}")
    print(f"  Total schools: {len(export_df)}\n")


def main():
    """Main function"""
    import sys

    if len(sys.argv) > 1:
        # If school name provided as argument
        school_name = ' '.join(sys.argv[1:])
        get_specific_school(school_name)
    else:
        # Display all schools
        get_school_rankings()

        # Ask if user wants to export
        print("\nOptions:")
        print("  - To search a specific school: python3 get_school_rankings.py [SchoolName]")
        print("  - To export to CSV: Add 'export' as argument")
        print()


if __name__ == "__main__":
    import sys

    if len(sys.argv) > 1 and sys.argv[1].lower() == 'export':
        export_rankings_csv()
    else:
        main()
