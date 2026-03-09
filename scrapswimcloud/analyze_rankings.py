#!/usr/bin/env python3
"""
Rankings Analysis Script for Men's and Women's Swimming
Analyzes national and conference rankings for all schools
"""

import pandas as pd
import numpy as np
from tabulate import tabulate


class RankingsAnalyzer:
    """Analyzer for swimming rankings data"""

    def __init__(self, csv_file='mens_womens_rankings.csv'):
        """Initialize with rankings CSV file"""
        print(f"Loading rankings data from {csv_file}...")
        self.df = pd.read_csv(csv_file)
        print(f"Loaded {len(self.df)} schools\n")

    def overview(self):
        """Print overview of rankings"""
        print("\n" + "="*100)
        print("RANKINGS OVERVIEW")
        print("="*100)

        # Men's rankings
        mens_data = self.df[self.df['mens_division_rank'].notna()].copy()
        print(f"\nMen's Teams: {len(mens_data)}")
        print(f"  - Division 1: {len(mens_data[mens_data['is_mid_major'] == False])}")
        print(f"  - Division 1 Mid-Major: {len(mens_data[mens_data['is_mid_major'] == True])}")
        print(f"  - Conferences: {mens_data['conference'].nunique()}")

        # Women's rankings
        womens_data = self.df[self.df['womens_division_rank'].notna()].copy()
        print(f"\nWomen's Teams: {len(womens_data)}")
        print(f"  - Division 1: {len(womens_data[womens_data['is_mid_major'] == False])}")
        print(f"  - Division 1 Mid-Major: {len(womens_data[womens_data['is_mid_major'] == True])}")
        print(f"  - Conferences: {womens_data['conference'].nunique()}")

        # Both teams
        both = self.df[(self.df['mens_division_rank'].notna()) & (self.df['womens_division_rank'].notna())]
        print(f"\nSchools with Both Teams: {len(both)}")

        # Only men's
        only_mens = self.df[(self.df['mens_division_rank'].notna()) & (self.df['womens_division_rank'].isna())]
        print(f"Schools with Only Men's Team: {len(only_mens)}")

        # Only women's
        only_womens = self.df[(self.df['mens_division_rank'].isna()) & (self.df['womens_division_rank'].notna())]
        print(f"Schools with Only Women's Team: {len(only_womens)}")

    def mens_national_rankings(self, top_n=50):
        """Display men's national rankings"""
        print("\n" + "="*100)
        print(f"MEN'S NATIONAL RANKINGS - TOP {top_n}")
        print("="*100)

        data = self.df[self.df['mens_division_rank'].notna()].copy()
        data = data.sort_values('mens_division_rank').head(top_n)

        table_data = []
        for _, row in data.iterrows():
            conf_rank = f"#{int(row['mens_conference_rank'])}" if pd.notna(row['mens_conference_rank']) else "N/A"
            table_data.append([
                int(row['mens_division_rank']),
                row['name'],
                row['conference'],
                conf_rank,
                row['division']
            ])

        headers = ["National Rank", "School", "Conference", "Conf. Rank", "Division"]
        print("\n" + tabulate(table_data, headers=headers, tablefmt="grid"))

    def womens_national_rankings(self, top_n=50):
        """Display women's national rankings"""
        print("\n" + "="*100)
        print(f"WOMEN'S NATIONAL RANKINGS - TOP {top_n}")
        print("="*100)

        data = self.df[self.df['womens_division_rank'].notna()].copy()
        data = data.sort_values('womens_division_rank').head(top_n)

        table_data = []
        for _, row in data.iterrows():
            conf_rank = f"#{int(row['womens_conference_rank'])}" if pd.notna(row['womens_conference_rank']) else "N/A"
            table_data.append([
                int(row['womens_division_rank']),
                row['name'],
                row['conference'],
                conf_rank,
                row['division']
            ])

        headers = ["National Rank", "School", "Conference", "Conf. Rank", "Division"]
        print("\n" + tabulate(table_data, headers=headers, tablefmt="grid"))

    def conference_rankings(self, conference_name):
        """Display rankings for a specific conference"""
        conf_data = self.df[self.df['conference'].str.contains(conference_name, case=False, na=False)].copy()

        if len(conf_data) == 0:
            print(f"No data found for conference: {conference_name}")
            return

        actual_conf = conf_data['conference'].iloc[0]

        print("\n" + "="*120)
        print(f"CONFERENCE RANKINGS: {actual_conf}")
        print("="*120)

        # Men's rankings
        mens = conf_data[conf_data['mens_division_rank'].notna()].sort_values('mens_conference_rank')
        if len(mens) > 0:
            print(f"\nMEN'S TEAMS ({len(mens)} schools):")
            print("-" * 120)

            table_data = []
            for _, row in mens.iterrows():
                table_data.append([
                    int(row['mens_conference_rank']),
                    row['name'],
                    int(row['mens_division_rank']),
                    row['division']
                ])

            headers = ["Conf. Rank", "School", "National Rank", "Division"]
            print(tabulate(table_data, headers=headers, tablefmt="grid"))

        # Women's rankings
        womens = conf_data[conf_data['womens_division_rank'].notna()].sort_values('womens_conference_rank')
        if len(womens) > 0:
            print(f"\nWOMEN'S TEAMS ({len(womens)} schools):")
            print("-" * 120)

            table_data = []
            for _, row in womens.iterrows():
                table_data.append([
                    int(row['womens_conference_rank']),
                    row['name'],
                    int(row['womens_division_rank']),
                    row['division']
                ])

            headers = ["Conf. Rank", "School", "National Rank", "Division"]
            print(tabulate(table_data, headers=headers, tablefmt="grid"))

    def school_rankings(self, school_name):
        """Display rankings for a specific school"""
        school_data = self.df[self.df['name'].str.contains(school_name, case=False, na=False)]

        if len(school_data) == 0:
            print(f"No data found for school: {school_name}")
            return

        row = school_data.iloc[0]
        actual_name = row['name']

        print("\n" + "="*100)
        print(f"RANKINGS: {actual_name}")
        print("="*100)

        print(f"\nConference: {row['conference']}")
        print(f"Division: {row['division']}")
        print(f"Mid-Major: {'Yes' if row['is_mid_major'] else 'No'}")

        print("\n" + "-"*100)
        print("MEN'S RANKINGS:")
        print("-"*100)
        if pd.notna(row['mens_division_rank']):
            print(f"  National Rank:    #{int(row['mens_division_rank'])}")
            print(f"  Conference Rank:  #{int(row['mens_conference_rank'])}")
            if pd.notna(row['mens_mid_major_rank']):
                print(f"  Mid-Major Rank:   #{int(row['mens_mid_major_rank'])}")
        else:
            print("  No men's team ranked")

        print("\n" + "-"*100)
        print("WOMEN'S RANKINGS:")
        print("-"*100)
        if pd.notna(row['womens_division_rank']):
            print(f"  National Rank:    #{int(row['womens_division_rank'])}")
            print(f"  Conference Rank:  #{int(row['womens_conference_rank'])}")
            if pd.notna(row['womens_mid_major_rank']):
                print(f"  Mid-Major Rank:   #{int(row['womens_mid_major_rank'])}")
        else:
            print("  No women's team ranked")

    def compare_mens_womens(self, top_n=30):
        """Compare men's and women's rankings side by side"""
        print("\n" + "="*120)
        print(f"MEN'S VS WOMEN'S RANKINGS COMPARISON - TOP {top_n} SCHOOLS WITH BOTH TEAMS")
        print("="*120)

        # Get schools with both teams
        both = self.df[(self.df['mens_division_rank'].notna()) &
                      (self.df['womens_division_rank'].notna())].copy()

        # Sort by average rank
        both['avg_rank'] = (both['mens_division_rank'] + both['womens_division_rank']) / 2
        both = both.sort_values('avg_rank').head(top_n)

        table_data = []
        for _, row in both.iterrows():
            mens_nat = int(row['mens_division_rank'])
            mens_conf = int(row['mens_conference_rank'])
            womens_nat = int(row['womens_division_rank'])
            womens_conf = int(row['womens_conference_rank'])

            # Calculate rank difference
            diff = womens_nat - mens_nat
            diff_str = f"+{diff}" if diff > 0 else str(diff) if diff < 0 else "="

            table_data.append([
                row['name'],
                row['conference'],
                f"#{mens_nat}",
                f"#{mens_conf}",
                f"#{womens_nat}",
                f"#{womens_conf}",
                diff_str
            ])

        headers = ["School", "Conference", "M-National", "M-Conf", "W-National", "W-Conf", "Diff (W-M)"]
        print("\n" + tabulate(table_data, headers=headers, tablefmt="grid"))

    def top_conferences(self):
        """Show top performing conferences"""
        print("\n" + "="*100)
        print("TOP CONFERENCES BY AVERAGE RANKING")
        print("="*100)

        # Men's conferences
        mens_conf = self.df[self.df['mens_division_rank'].notna()].groupby('conference').agg({
            'mens_division_rank': ['mean', 'min', 'count']
        }).round(1)
        mens_conf.columns = ['avg_rank', 'best_rank', 'num_teams']
        mens_conf = mens_conf[mens_conf['num_teams'] >= 3]  # At least 3 teams
        mens_conf = mens_conf.sort_values('avg_rank').head(15)

        print("\nMEN'S CONFERENCES (minimum 3 teams):")
        print("-" * 100)
        table_data = []
        for conf, row in mens_conf.iterrows():
            table_data.append([
                conf,
                int(row['num_teams']),
                f"{row['avg_rank']:.1f}",
                f"#{int(row['best_rank'])}"
            ])

        headers = ["Conference", "Teams", "Avg Rank", "Best Rank"]
        print(tabulate(table_data, headers=headers, tablefmt="grid"))

        # Women's conferences
        womens_conf = self.df[self.df['womens_division_rank'].notna()].groupby('conference').agg({
            'womens_division_rank': ['mean', 'min', 'count']
        }).round(1)
        womens_conf.columns = ['avg_rank', 'best_rank', 'num_teams']
        womens_conf = womens_conf[womens_conf['num_teams'] >= 3]  # At least 3 teams
        womens_conf = womens_conf.sort_values('avg_rank').head(15)

        print("\nWOMEN'S CONFERENCES (minimum 3 teams):")
        print("-" * 100)
        table_data = []
        for conf, row in womens_conf.iterrows():
            table_data.append([
                conf,
                int(row['num_teams']),
                f"{row['avg_rank']:.1f}",
                f"#{int(row['best_rank'])}"
            ])

        headers = ["Conference", "Teams", "Avg Rank", "Best Rank"]
        print(tabulate(table_data, headers=headers, tablefmt="grid"))

    def list_conferences(self):
        """List all conferences"""
        print("\n" + "="*100)
        print("ALL CONFERENCES")
        print("="*100)

        conferences = self.df.groupby('conference').agg({
            'mens_division_rank': 'count',
            'womens_division_rank': 'count',
            'name': 'count'
        }).rename(columns={
            'mens_division_rank': "Men's Teams",
            'womens_division_rank': "Women's Teams",
            'name': 'Total Schools'
        })

        conferences = conferences.sort_values('Total Schools', ascending=False)

        table_data = []
        for conf, row in conferences.iterrows():
            table_data.append([
                conf,
                int(row['Total Schools']),
                int(row["Men's Teams"]),
                int(row["Women's Teams"])
            ])

        headers = ["Conference", "Total Schools", "Men's Teams", "Women's Teams"]
        print("\n" + tabulate(table_data, headers=headers, tablefmt="grid"))

    def export_rankings_report(self, output_file='rankings_report.csv'):
        """Export comprehensive rankings report"""
        print(f"\nExporting rankings report to {output_file}...")

        export_data = self.df[[
            'name', 'conference', 'division', 'is_mid_major',
            'mens_division_rank', 'mens_conference_rank',
            'womens_division_rank', 'womens_conference_rank'
        ]].copy()

        # Rename columns for clarity
        export_data.columns = [
            'School', 'Conference', 'Division', 'Mid-Major',
            'Men_National_Rank', 'Men_Conference_Rank',
            'Women_National_Rank', 'Women_Conference_Rank'
        ]

        # Sort by men's rank
        export_data = export_data.sort_values('Men_National_Rank')

        export_data.to_csv(output_file, index=False)
        print(f"Report exported successfully! ({len(export_data)} schools)")

    def export_by_conference(self):
        """Export separate files for each conference"""
        print("\nExporting conference-specific files...")

        conferences = self.df['conference'].unique()
        for conf in conferences:
            conf_data = self.df[self.df['conference'] == conf].copy()

            # Sort by men's rank (or women's if no men's)
            if conf_data['mens_division_rank'].notna().any():
                conf_data = conf_data.sort_values('mens_division_rank')
            else:
                conf_data = conf_data.sort_values('womens_division_rank')

            # Clean filename
            filename = f"rankings_{conf.replace(' ', '_').replace('/', '_')}.csv"

            conf_data[[
                'name', 'conference', 'division',
                'mens_division_rank', 'mens_conference_rank',
                'womens_division_rank', 'womens_conference_rank'
            ]].to_csv(filename, index=False)

            print(f"  ✓ {filename} ({len(conf_data)} schools)")

        print(f"\nExported {len(conferences)} conference files!")


def main():
    """Main function with interactive menu"""
    analyzer = RankingsAnalyzer()

    while True:
        print("\n" + "="*100)
        print("SWIMMING RANKINGS ANALYSIS - MENU")
        print("="*100)
        print("1.  Overview")
        print("2.  Men's National Rankings")
        print("3.  Women's National Rankings")
        print("4.  Compare Men's vs Women's Rankings")
        print("5.  Conference Rankings")
        print("6.  School Rankings")
        print("7.  Top Conferences")
        print("8.  List All Conferences")
        print("9.  Export Rankings Report")
        print("10. Export by Conference")
        print("0.  Exit")
        print("="*100)

        choice = input("\nEnter your choice (0-10): ").strip()

        try:
            if choice == '0':
                print("Goodbye!")
                break
            elif choice == '1':
                analyzer.overview()
            elif choice == '2':
                n = input("Number of schools to display (default 50): ").strip()
                n = int(n) if n else 50
                analyzer.mens_national_rankings(top_n=n)
            elif choice == '3':
                n = input("Number of schools to display (default 50): ").strip()
                n = int(n) if n else 50
                analyzer.womens_national_rankings(top_n=n)
            elif choice == '4':
                n = input("Number of schools to display (default 30): ").strip()
                n = int(n) if n else 30
                analyzer.compare_mens_womens(top_n=n)
            elif choice == '5':
                analyzer.list_conferences()
                conf = input("\nEnter conference name: ").strip()
                analyzer.conference_rankings(conf)
            elif choice == '6':
                school = input("Enter school name: ").strip()
                analyzer.school_rankings(school)
            elif choice == '7':
                analyzer.top_conferences()
            elif choice == '8':
                analyzer.list_conferences()
            elif choice == '9':
                filename = input("Output filename (default: rankings_report.csv): ").strip()
                filename = filename if filename else 'rankings_report.csv'
                analyzer.export_rankings_report(filename)
            elif choice == '10':
                analyzer.export_by_conference()
            else:
                print("Invalid choice! Please try again.")
        except Exception as e:
            print(f"Error: {e}")
            print("Please try again.")

        input("\nPress Enter to continue...")


if __name__ == "__main__":
    main()
