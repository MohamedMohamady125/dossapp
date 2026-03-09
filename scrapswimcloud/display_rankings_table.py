#!/usr/bin/env python3
"""
Simple Rankings Table Display
Shows all schools with men's and women's national and conference rankings
"""

import pandas as pd
from tabulate import tabulate


def display_all_rankings():
    """Display all schools with rankings in a clean table"""
    print("\nLoading rankings data...")
    df = pd.read_csv('mens_womens_rankings.csv')

    print("\n" + "="*130)
    print("ALL SCHOOLS - MEN'S AND WOMEN'S RANKINGS")
    print("="*130)

    table_data = []

    for _, row in df.iterrows():
        # Men's rankings
        if pd.notna(row['mens_division_rank']):
            mens_nat = f"#{int(row['mens_division_rank'])}"
            mens_conf = f"#{int(row['mens_conference_rank'])}"
        else:
            mens_nat = "-"
            mens_conf = "-"

        # Women's rankings
        if pd.notna(row['womens_division_rank']):
            womens_nat = f"#{int(row['womens_division_rank'])}"
            womens_conf = f"#{int(row['womens_conference_rank'])}"
        else:
            womens_nat = "-"
            womens_conf = "-"

        table_data.append([
            row['name'],
            row['conference'],
            mens_nat,
            mens_conf,
            womens_nat,
            womens_conf
        ])

    # Sort by school name
    table_data.sort(key=lambda x: x[0])

    headers = ["School", "Conference", "M-National", "M-Conf", "W-National", "W-Conf"]
    print("\n" + tabulate(table_data, headers=headers, tablefmt="grid"))

    # Summary statistics
    print("\n" + "="*130)
    print("SUMMARY")
    print("="*130)
    print(f"Total Schools: {len(df)}")
    print(f"Schools with Men's Teams: {df['mens_division_rank'].notna().sum()}")
    print(f"Schools with Women's Teams: {df['womens_division_rank'].notna().sum()}")
    print(f"Schools with Both Teams: {((df['mens_division_rank'].notna()) & (df['womens_division_rank'].notna())).sum()}")
    print(f"Total Conferences: {df['conference'].nunique()}")


def display_top_20():
    """Display top 20 schools for both men and women side by side"""
    df = pd.read_csv('mens_womens_rankings.csv')

    print("\n" + "="*130)
    print("TOP 20 SCHOOLS - MEN'S AND WOMEN'S SIDE BY SIDE")
    print("="*130)

    # Men's top 20
    mens_top = df[df['mens_division_rank'].notna()].sort_values('mens_division_rank').head(20)

    # Women's top 20
    womens_top = df[df['womens_division_rank'].notna()].sort_values('womens_division_rank').head(20)

    print("\n" + tabulate([
        ["="*60, "="*60],
        ["MEN'S TOP 20", "WOMEN'S TOP 20"],
        ["="*60, "="*60]
    ], tablefmt="plain"))

    table_data = []
    for i in range(20):
        # Men's side
        if i < len(mens_top):
            mens_row = mens_top.iloc[i]
            mens_line = f"#{int(mens_row['mens_division_rank']):2d}  {mens_row['name']:<30s} ({mens_row['conference']})"
        else:
            mens_line = ""

        # Women's side
        if i < len(womens_top):
            womens_row = womens_top.iloc[i]
            womens_line = f"#{int(womens_row['womens_division_rank']):2d}  {womens_row['name']:<30s} ({womens_row['conference']})"
        else:
            womens_line = ""

        table_data.append([mens_line, womens_line])

    print(tabulate(table_data, tablefmt="plain"))


def display_by_conference():
    """Display schools grouped by conference"""
    df = pd.read_csv('mens_womens_rankings.csv')

    print("\n" + "="*130)
    print("SCHOOLS BY CONFERENCE")
    print("="*130)

    conferences = sorted(df['conference'].unique())

    for conf in conferences:
        conf_data = df[df['conference'] == conf].copy()

        print(f"\n{'─'*130}")
        print(f"CONFERENCE: {conf}")
        print(f"{'─'*130}")

        # Sort by men's rank (or women's if no men's)
        if conf_data['mens_division_rank'].notna().any():
            conf_data = conf_data.sort_values('mens_division_rank')
        else:
            conf_data = conf_data.sort_values('womens_division_rank')

        table_data = []
        for _, row in conf_data.iterrows():
            # Men's rankings
            if pd.notna(row['mens_division_rank']):
                mens_nat = f"#{int(row['mens_division_rank'])}"
                mens_conf = f"#{int(row['mens_conference_rank'])}"
            else:
                mens_nat = "-"
                mens_conf = "-"

            # Women's rankings
            if pd.notna(row['womens_division_rank']):
                womens_nat = f"#{int(row['womens_division_rank'])}"
                womens_conf = f"#{int(row['womens_conference_rank'])}"
            else:
                womens_nat = "-"
                womens_conf = "-"

            table_data.append([
                row['name'],
                mens_nat,
                mens_conf,
                womens_nat,
                womens_conf
            ])

        headers = ["School", "M-National", "M-Conf", "W-National", "W-Conf"]
        print(tabulate(table_data, headers=headers, tablefmt="simple"))


def main():
    """Main function"""
    print("\n" + "="*130)
    print("SWIMMING RANKINGS - COMPREHENSIVE DISPLAY")
    print("="*130)

    # Display all rankings in one table
    display_all_rankings()

    # Display top 20 side by side
    display_top_20()

    # Display by conference
    display_by_conference()

    print("\n" + "="*130)
    print("DISPLAY COMPLETE!")
    print("="*130)
    print("\nFor interactive analysis, run: python3 analyze_rankings.py")
    print("="*130 + "\n")


if __name__ == "__main__":
    main()
