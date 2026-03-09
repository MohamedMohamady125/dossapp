#!/usr/bin/env python3
"""
Analysis Script for Schools Men's Swimming Times
This script provides comprehensive analysis of men's swimming times data.
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from datetime import datetime
import warnings
warnings.filterwarnings('ignore')

# Set style for better visualizations
sns.set_style("whitegrid")
plt.rcParams['figure.figsize'] = (12, 6)


class MensTimesAnalyzer:
    """Analyzer for men's swimming times data"""

    def __init__(self, csv_file='schools_mens_times.csv'):
        """Initialize analyzer with CSV file"""
        print(f"Loading data from {csv_file}...")
        self.df = pd.read_csv(csv_file)
        self._preprocess_data()
        print(f"Loaded {len(self.df)} records for {self.df['school_name'].nunique()} schools")

    def _preprocess_data(self):
        """Preprocess and clean the data"""
        # Convert time strings to seconds for analysis
        self.df['time_seconds'] = self.df['time'].apply(self._time_to_seconds)

        # Fill missing values
        self.df['year'] = self.df['year'].fillna('Unknown')
        self.df['meet'] = self.df['meet'].fillna('Unknown')

    def _time_to_seconds(self, time_str):
        """Convert time string to seconds"""
        try:
            if pd.isna(time_str):
                return np.nan
            time_str = str(time_str).strip()

            # Handle formats like "1:23.45" (minutes:seconds)
            if ':' in time_str:
                parts = time_str.split(':')
                minutes = int(parts[0])
                seconds = float(parts[1])
                return minutes * 60 + seconds
            else:
                # Handle formats like "23.45" (just seconds)
                return float(time_str)
        except:
            return np.nan

    def _seconds_to_time(self, seconds):
        """Convert seconds back to time string"""
        if pd.isna(seconds):
            return "N/A"
        minutes = int(seconds // 60)
        secs = seconds % 60
        if minutes > 0:
            return f"{minutes}:{secs:05.2f}"
        else:
            return f"{secs:.2f}"

    def overview(self):
        """Print overview of the dataset"""
        print("\n" + "="*80)
        print("DATASET OVERVIEW")
        print("="*80)
        print(f"\nTotal Records: {len(self.df):,}")
        print(f"Schools: {self.df['school_name'].nunique()}")
        print(f"Swimmers: {self.df['swimmer'].nunique()}")
        print(f"Events: {self.df['event'].nunique()}")
        print(f"Meets: {self.df['meet'].nunique()}")

        print("\n" + "-"*80)
        print("EVENTS BREAKDOWN:")
        print("-"*80)
        events = self.df['event'].value_counts().sort_index()
        for event, count in events.items():
            print(f"  {event:.<30} {count:>6,} records")

        print("\n" + "-"*80)
        print("DATA QUALITY:")
        print("-"*80)
        print(f"  Missing times: {self.df['time'].isna().sum()}")
        print(f"  Missing swimmers: {self.df['swimmer'].isna().sum()}")
        print(f"  Missing years: {(self.df['year'] == 'Unknown').sum()}")

    def top_schools_by_event(self, event=None, top_n=10):
        """Show top schools by average time for a specific event"""
        print("\n" + "="*80)
        if event:
            print(f"TOP {top_n} SCHOOLS - {event}")
            data = self.df[self.df['event'] == event].copy()
        else:
            print(f"TOP {top_n} SCHOOLS - OVERALL (All Events)")
            data = self.df.copy()
        print("="*80)

        if len(data) == 0:
            print("No data found for this event!")
            return

        # Calculate average time per school
        school_avg = data.groupby('school_name').agg({
            'time_seconds': ['mean', 'min', 'count']
        }).round(2)

        school_avg.columns = ['avg_time', 'best_time', 'num_times']
        school_avg = school_avg.sort_values('avg_time').head(top_n)

        print(f"\n{'Rank':<6} {'School':<30} {'Avg Time':<12} {'Best Time':<12} {'Count':<8}")
        print("-"*80)

        for i, (school, row) in enumerate(school_avg.iterrows(), 1):
            avg = self._seconds_to_time(row['avg_time'])
            best = self._seconds_to_time(row['best_time'])
            print(f"{i:<6} {school:<30} {avg:<12} {best:<12} {int(row['num_times']):<8}")

    def top_swimmers(self, event=None, top_n=20):
        """Show top swimmers by best time"""
        print("\n" + "="*80)
        if event:
            print(f"TOP {top_n} SWIMMERS - {event}")
            data = self.df[self.df['event'] == event].copy()
        else:
            print(f"TOP {top_n} SWIMMERS - ALL EVENTS")
            data = self.df.copy()
        print("="*80)

        if len(data) == 0:
            print("No data found!")
            return

        # Get best time per swimmer
        swimmer_best = data.groupby(['swimmer', 'school_name', 'event']).agg({
            'time_seconds': 'min'
        }).reset_index()

        swimmer_best = swimmer_best.sort_values('time_seconds').head(top_n)

        print(f"\n{'Rank':<6} {'Swimmer':<25} {'School':<25} {'Event':<15} {'Time':<10}")
        print("-"*100)

        for i, row in enumerate(swimmer_best.itertuples(), 1):
            time_str = self._seconds_to_time(row.time_seconds)
            print(f"{i:<6} {row.swimmer:<25} {row.school_name:<25} {row.event:<15} {time_str:<10}")

    def school_profile(self, school_name):
        """Detailed profile for a specific school"""
        school_data = self.df[self.df['school_name'].str.contains(school_name, case=False, na=False)]

        if len(school_data) == 0:
            print(f"No data found for school: {school_name}")
            return

        actual_name = school_data['school_name'].iloc[0]

        print("\n" + "="*80)
        print(f"SCHOOL PROFILE: {actual_name}")
        print("="*80)

        print(f"\nTotal Records: {len(school_data)}")
        print(f"Unique Swimmers: {school_data['swimmer'].nunique()}")
        print(f"Events Competed: {school_data['event'].nunique()}")
        print(f"Meets Attended: {school_data['meet'].nunique()}")

        print("\n" + "-"*80)
        print("PERFORMANCE BY EVENT:")
        print("-"*80)
        print(f"{'Event':<20} {'Count':<8} {'Best Time':<12} {'Avg Time':<12} {'Top Swimmer':<25}")
        print("-"*80)

        event_stats = school_data.groupby('event').agg({
            'time_seconds': ['count', 'min', 'mean']
        })

        for event in sorted(school_data['event'].unique()):
            event_data = school_data[school_data['event'] == event]
            best_idx = event_data['time_seconds'].idxmin()
            best_swimmer = event_data.loc[best_idx, 'swimmer']

            stats = event_stats.loc[event]
            count = int(stats[('time_seconds', 'count')])
            best = self._seconds_to_time(stats[('time_seconds', 'min')])
            avg = self._seconds_to_time(stats[('time_seconds', 'mean')])

            print(f"{event:<20} {count:<8} {best:<12} {avg:<12} {best_swimmer:<25}")

        # Top swimmers for this school
        print("\n" + "-"*80)
        print("TOP 10 SWIMMERS:")
        print("-"*80)

        swimmer_stats = school_data.groupby('swimmer').agg({
            'time_seconds': ['count', 'min'],
            'event': lambda x: x.mode()[0] if len(x.mode()) > 0 else x.iloc[0]
        })
        swimmer_stats.columns = ['num_times', 'best_time', 'main_event']
        swimmer_stats = swimmer_stats.sort_values('best_time').head(10)

        print(f"{'Rank':<6} {'Swimmer':<25} {'Best Time':<12} {'Main Event':<15} {'Times':<8}")
        print("-"*80)

        for i, (swimmer, row) in enumerate(swimmer_stats.iterrows(), 1):
            best = self._seconds_to_time(row['best_time'])
            print(f"{i:<6} {swimmer:<25} {best:<12} {row['main_event']:<15} {int(row['num_times']):<8}")

    def event_statistics(self, event):
        """Detailed statistics for a specific event"""
        event_data = self.df[self.df['event'] == event].copy()

        if len(event_data) == 0:
            print(f"No data found for event: {event}")
            return

        print("\n" + "="*80)
        print(f"EVENT ANALYSIS: {event}")
        print("="*80)

        print(f"\nTotal Times Recorded: {len(event_data)}")
        print(f"Schools Participating: {event_data['school_name'].nunique()}")
        print(f"Unique Swimmers: {event_data['swimmer'].nunique()}")

        times = event_data['time_seconds'].dropna()

        print("\n" + "-"*80)
        print("TIME STATISTICS:")
        print("-"*80)
        print(f"  Fastest Time:    {self._seconds_to_time(times.min())}")
        print(f"  Slowest Time:    {self._seconds_to_time(times.max())}")
        print(f"  Average Time:    {self._seconds_to_time(times.mean())}")
        print(f"  Median Time:     {self._seconds_to_time(times.median())}")
        print(f"  Std Deviation:   {times.std():.2f} seconds")

        # Percentiles
        print("\n" + "-"*80)
        print("PERCENTILES:")
        print("-"*80)
        for pct in [10, 25, 50, 75, 90, 95, 99]:
            val = np.percentile(times, pct)
            print(f"  {pct}th percentile: {self._seconds_to_time(val)}")

    def compare_schools(self, school_names, event=None):
        """Compare multiple schools"""
        print("\n" + "="*80)
        print(f"SCHOOL COMPARISON{' - ' + event if event else ''}")
        print("="*80)

        results = []
        for school in school_names:
            school_data = self.df[self.df['school_name'].str.contains(school, case=False, na=False)]
            if event:
                school_data = school_data[school_data['event'] == event]

            if len(school_data) > 0:
                actual_name = school_data['school_name'].iloc[0]
                times = school_data['time_seconds'].dropna()
                results.append({
                    'school': actual_name,
                    'count': len(times),
                    'best': times.min(),
                    'avg': times.mean(),
                    'median': times.median()
                })

        if not results:
            print("No data found for the specified schools!")
            return

        df_compare = pd.DataFrame(results)
        df_compare = df_compare.sort_values('avg')

        print(f"\n{'Rank':<6} {'School':<30} {'Count':<8} {'Best':<12} {'Average':<12} {'Median':<12}")
        print("-"*90)

        for i, row in enumerate(df_compare.itertuples(), 1):
            best = self._seconds_to_time(row.best)
            avg = self._seconds_to_time(row.avg)
            median = self._seconds_to_time(row.median)
            print(f"{i:<6} {row.school:<30} {row.count:<8} {best:<12} {avg:<12} {median:<12}")

    def list_events(self):
        """List all available events"""
        print("\n" + "="*80)
        print("AVAILABLE EVENTS")
        print("="*80)
        events = sorted(self.df['event'].unique())
        for i, event in enumerate(events, 1):
            count = len(self.df[self.df['event'] == event])
            print(f"{i:2}. {event:<20} ({count:,} records)")

    def list_schools(self, min_records=0):
        """List all schools with record counts"""
        print("\n" + "="*80)
        print("SCHOOLS LIST")
        print("="*80)

        school_counts = self.df['school_name'].value_counts().sort_index()
        school_counts = school_counts[school_counts >= min_records]

        print(f"\n{'School':<40} {'Records':<10}")
        print("-"*50)
        for school, count in school_counts.items():
            print(f"{school:<40} {count:>8,}")

        print(f"\nTotal: {len(school_counts)} schools")

    def export_summary(self, output_file='mens_times_summary.csv'):
        """Export summary statistics to CSV"""
        print(f"\nExporting summary to {output_file}...")

        summary = self.df.groupby(['school_name', 'event']).agg({
            'time_seconds': ['count', 'min', 'mean', 'median', 'max'],
            'swimmer': 'nunique'
        }).round(2)

        summary.columns = ['num_times', 'best_time', 'avg_time', 'median_time', 'worst_time', 'num_swimmers']
        summary = summary.reset_index()

        # Convert times back to readable format
        for col in ['best_time', 'avg_time', 'median_time', 'worst_time']:
            summary[col + '_formatted'] = summary[col].apply(self._seconds_to_time)

        summary.to_csv(output_file, index=False)
        print(f"Summary exported successfully! ({len(summary)} records)")

    def plot_time_distribution(self, event, save_fig=False):
        """Plot time distribution for an event"""
        event_data = self.df[self.df['event'] == event].copy()

        if len(event_data) == 0:
            print(f"No data found for event: {event}")
            return

        plt.figure(figsize=(14, 6))

        # Histogram
        plt.subplot(1, 2, 1)
        times = event_data['time_seconds'].dropna()
        plt.hist(times, bins=50, edgecolor='black', alpha=0.7)
        plt.xlabel('Time (seconds)')
        plt.ylabel('Frequency')
        plt.title(f'{event} - Time Distribution')
        plt.axvline(times.mean(), color='red', linestyle='--', label=f'Mean: {self._seconds_to_time(times.mean())}')
        plt.axvline(times.median(), color='green', linestyle='--', label=f'Median: {self._seconds_to_time(times.median())}')
        plt.legend()

        # Box plot
        plt.subplot(1, 2, 2)
        plt.boxplot(times, vert=True)
        plt.ylabel('Time (seconds)')
        plt.title(f'{event} - Box Plot')
        plt.grid(True, alpha=0.3)

        plt.tight_layout()

        if save_fig:
            filename = f"time_distribution_{event.replace(' ', '_')}.png"
            plt.savefig(filename, dpi=300, bbox_inches='tight')
            print(f"Figure saved as {filename}")
        else:
            plt.show()

    def plot_school_comparison(self, school_names, event=None, save_fig=False):
        """Plot comparison between schools"""
        data_list = []
        labels = []

        for school in school_names:
            school_data = self.df[self.df['school_name'].str.contains(school, case=False, na=False)]
            if event:
                school_data = school_data[school_data['event'] == event]

            if len(school_data) > 0:
                actual_name = school_data['school_name'].iloc[0]
                times = school_data['time_seconds'].dropna()
                data_list.append(times)
                labels.append(actual_name)

        if not data_list:
            print("No data found for comparison!")
            return

        plt.figure(figsize=(12, 6))
        plt.boxplot(data_list, labels=labels, vert=True)
        plt.ylabel('Time (seconds)')
        plt.xlabel('School')
        plt.title(f"School Comparison{' - ' + event if event else ''}")
        plt.xticks(rotation=45, ha='right')
        plt.grid(True, alpha=0.3)
        plt.tight_layout()

        if save_fig:
            filename = f"school_comparison_{event.replace(' ', '_') if event else 'all'}.png"
            plt.savefig(filename, dpi=300, bbox_inches='tight')
            print(f"Figure saved as {filename}")
        else:
            plt.show()


def main():
    """Main function with interactive menu"""
    analyzer = MensTimesAnalyzer()

    while True:
        print("\n" + "="*80)
        print("MEN'S SWIMMING TIMES ANALYSIS - MENU")
        print("="*80)
        print("1.  Dataset Overview")
        print("2.  List All Events")
        print("3.  List All Schools")
        print("4.  Top Schools by Event")
        print("5.  Top Swimmers")
        print("6.  School Profile")
        print("7.  Event Statistics")
        print("8.  Compare Schools")
        print("9.  Plot Time Distribution")
        print("10. Plot School Comparison")
        print("11. Export Summary to CSV")
        print("0.  Exit")
        print("="*80)

        choice = input("\nEnter your choice (0-11): ").strip()

        try:
            if choice == '0':
                print("Goodbye!")
                break
            elif choice == '1':
                analyzer.overview()
            elif choice == '2':
                analyzer.list_events()
            elif choice == '3':
                min_rec = input("Minimum records (default 0): ").strip()
                min_rec = int(min_rec) if min_rec else 0
                analyzer.list_schools(min_records=min_rec)
            elif choice == '4':
                analyzer.list_events()
                event = input("Enter event name (or press Enter for all): ").strip()
                event = event if event else None
                analyzer.top_schools_by_event(event=event)
            elif choice == '5':
                analyzer.list_events()
                event = input("Enter event name (or press Enter for all): ").strip()
                event = event if event else None
                analyzer.top_swimmers(event=event)
            elif choice == '6':
                school = input("Enter school name: ").strip()
                analyzer.school_profile(school)
            elif choice == '7':
                analyzer.list_events()
                event = input("Enter event name: ").strip()
                analyzer.event_statistics(event)
            elif choice == '8':
                print("Enter school names (comma-separated):")
                schools = input().strip().split(',')
                schools = [s.strip() for s in schools]
                event = input("Enter event name (or press Enter for all): ").strip()
                event = event if event else None
                analyzer.compare_schools(schools, event)
            elif choice == '9':
                analyzer.list_events()
                event = input("Enter event name: ").strip()
                save = input("Save figure? (y/n): ").strip().lower() == 'y'
                analyzer.plot_time_distribution(event, save_fig=save)
            elif choice == '10':
                print("Enter school names (comma-separated):")
                schools = input().strip().split(',')
                schools = [s.strip() for s in schools]
                event = input("Enter event name (or press Enter for all): ").strip()
                event = event if event else None
                save = input("Save figure? (y/n): ").strip().lower() == 'y'
                analyzer.plot_school_comparison(schools, event, save_fig=save)
            elif choice == '11':
                filename = input("Output filename (default: mens_times_summary.csv): ").strip()
                filename = filename if filename else 'mens_times_summary.csv'
                analyzer.export_summary(filename)
            else:
                print("Invalid choice! Please try again.")
        except Exception as e:
            print(f"Error: {e}")
            print("Please try again.")

        input("\nPress Enter to continue...")


if __name__ == "__main__":
    main()
