#!/usr/bin/env python3
"""
Visualization Script for Men's Swimming Times
Generates comprehensive graphs and charts
"""

import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path
import warnings
warnings.filterwarnings('ignore')

# Set style
sns.set_style("whitegrid")
plt.rcParams['figure.figsize'] = (14, 8)
plt.rcParams['font.size'] = 10

class SwimDataVisualizer:
    """Generate visualizations for swimming data"""

    def __init__(self, csv_file='schools_mens_times.csv'):
        print(f"Loading data from {csv_file}...")
        self.df = pd.read_csv(csv_file)
        self._preprocess_data()

        # Create output directory
        self.output_dir = Path('visualizations')
        self.output_dir.mkdir(exist_ok=True)
        print(f"Visualizations will be saved to: {self.output_dir}/")

    def _preprocess_data(self):
        """Preprocess the data"""
        self.df['time_seconds'] = self.df['time'].apply(self._time_to_seconds)
        self.df['year'] = self.df['year'].fillna('Unknown')
        self.df['meet'] = self.df['meet'].fillna('Unknown')

    def _time_to_seconds(self, time_str):
        """Convert time string to seconds"""
        try:
            if pd.isna(time_str):
                return np.nan
            time_str = str(time_str).strip()
            if ':' in time_str:
                parts = time_str.split(':')
                minutes = int(parts[0])
                seconds = float(parts[1])
                return minutes * 60 + seconds
            else:
                return float(time_str)
        except:
            return np.nan

    def _seconds_to_time(self, seconds):
        """Convert seconds to time string"""
        if pd.isna(seconds):
            return "N/A"
        minutes = int(seconds // 60)
        secs = seconds % 60
        if minutes > 0:
            return f"{minutes}:{secs:05.2f}"
        return f"{secs:.2f}"

    def plot_records_by_school(self):
        """Bar chart of number of records by school"""
        print("Generating: Records by School...")

        fig, ax = plt.subplots(figsize=(16, 10))

        school_counts = self.df['school_name'].value_counts().head(30)

        colors = sns.color_palette("viridis", len(school_counts))
        bars = ax.barh(range(len(school_counts)), school_counts.values, color=colors)

        ax.set_yticks(range(len(school_counts)))
        ax.set_yticklabels(school_counts.index)
        ax.set_xlabel('Number of Records', fontsize=12, fontweight='bold')
        ax.set_ylabel('School', fontsize=12, fontweight='bold')
        ax.set_title('Top 30 Schools by Number of Recorded Times', fontsize=16, fontweight='bold', pad=20)

        # Add value labels
        for i, bar in enumerate(bars):
            width = bar.get_width()
            ax.text(width, bar.get_y() + bar.get_height()/2,
                   f' {int(width)}', ha='left', va='center', fontsize=9)

        plt.tight_layout()
        plt.savefig(self.output_dir / '01_records_by_school.png', dpi=300, bbox_inches='tight')
        plt.close()
        print("  ✓ Saved: 01_records_by_school.png")

    def plot_events_distribution(self):
        """Pie chart and bar chart of events distribution"""
        print("Generating: Events Distribution...")

        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(18, 8))

        event_counts = self.df['event'].value_counts()

        # Pie chart
        colors = sns.color_palette("Set3", len(event_counts))
        wedges, texts, autotexts = ax1.pie(event_counts.values, labels=event_counts.index,
                                            autopct='%1.1f%%', colors=colors, startangle=90)
        for text in texts:
            text.set_fontsize(9)
        for autotext in autotexts:
            autotext.set_color('white')
            autotext.set_fontsize(8)
            autotext.set_fontweight('bold')
        ax1.set_title('Events Distribution (Percentage)', fontsize=14, fontweight='bold')

        # Bar chart
        event_counts_sorted = event_counts.sort_values(ascending=True)
        colors2 = sns.color_palette("coolwarm", len(event_counts_sorted))
        bars = ax2.barh(range(len(event_counts_sorted)), event_counts_sorted.values, color=colors2)
        ax2.set_yticks(range(len(event_counts_sorted)))
        ax2.set_yticklabels(event_counts_sorted.index)
        ax2.set_xlabel('Number of Records', fontsize=11, fontweight='bold')
        ax2.set_title('Events Distribution (Count)', fontsize=14, fontweight='bold')

        # Add value labels
        for i, bar in enumerate(bars):
            width = bar.get_width()
            ax2.text(width, bar.get_y() + bar.get_height()/2,
                    f' {int(width)}', ha='left', va='center', fontsize=9)

        plt.tight_layout()
        plt.savefig(self.output_dir / '02_events_distribution.png', dpi=300, bbox_inches='tight')
        plt.close()
        print("  ✓ Saved: 02_events_distribution.png")

    def plot_time_distributions_by_event(self):
        """Box plots and violin plots for time distributions"""
        print("Generating: Time Distributions by Event...")

        events = sorted(self.df['event'].unique())

        # Box plots
        fig, axes = plt.subplots(3, 5, figsize=(20, 12))
        axes = axes.flatten()

        for idx, event in enumerate(events):
            if idx < len(axes):
                event_data = self.df[self.df['event'] == event]['time_seconds'].dropna()

                axes[idx].boxplot(event_data, vert=True, patch_artist=True,
                                 boxprops=dict(facecolor='lightblue', alpha=0.7),
                                 medianprops=dict(color='red', linewidth=2),
                                 whiskerprops=dict(color='blue', linewidth=1.5),
                                 capprops=dict(color='blue', linewidth=1.5))
                axes[idx].set_title(event, fontsize=11, fontweight='bold')
                axes[idx].set_ylabel('Time (seconds)', fontsize=9)
                axes[idx].grid(True, alpha=0.3)

        # Hide extra subplots
        for idx in range(len(events), len(axes)):
            axes[idx].axis('off')

        plt.suptitle('Time Distributions by Event (Box Plots)', fontsize=16, fontweight='bold', y=0.995)
        plt.tight_layout()
        plt.savefig(self.output_dir / '03_time_distributions_boxplot.png', dpi=300, bbox_inches='tight')
        plt.close()
        print("  ✓ Saved: 03_time_distributions_boxplot.png")

        # Violin plots
        fig, axes = plt.subplots(3, 5, figsize=(20, 12))
        axes = axes.flatten()

        for idx, event in enumerate(events):
            if idx < len(axes):
                event_data = self.df[self.df['event'] == event][['event', 'time_seconds']].dropna()

                parts = axes[idx].violinplot([event_data['time_seconds']], positions=[0],
                                            showmeans=True, showmedians=True)
                for pc in parts['bodies']:
                    pc.set_facecolor('lightgreen')
                    pc.set_alpha(0.7)

                axes[idx].set_title(event, fontsize=11, fontweight='bold')
                axes[idx].set_ylabel('Time (seconds)', fontsize=9)
                axes[idx].set_xticks([])
                axes[idx].grid(True, alpha=0.3)

        # Hide extra subplots
        for idx in range(len(events), len(axes)):
            axes[idx].axis('off')

        plt.suptitle('Time Distributions by Event (Violin Plots)', fontsize=16, fontweight='bold', y=0.995)
        plt.tight_layout()
        plt.savefig(self.output_dir / '04_time_distributions_violin.png', dpi=300, bbox_inches='tight')
        plt.close()
        print("  ✓ Saved: 04_time_distributions_violin.png")

    def plot_top_schools_comparison(self, top_n=15):
        """Compare average times for top schools"""
        print(f"Generating: Top {top_n} Schools Comparison...")

        # Calculate average times per school
        school_stats = self.df.groupby('school_name').agg({
            'time_seconds': ['mean', 'min', 'count']
        }).round(2)
        school_stats.columns = ['avg_time', 'best_time', 'count']
        school_stats = school_stats[school_stats['count'] >= 50]  # At least 50 records
        school_stats = school_stats.sort_values('avg_time').head(top_n)

        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(18, 8))

        # Average times
        colors1 = sns.color_palette("RdYlGn_r", len(school_stats))
        bars1 = ax1.barh(range(len(school_stats)), school_stats['avg_time'].values, color=colors1)
        ax1.set_yticks(range(len(school_stats)))
        ax1.set_yticklabels(school_stats.index)
        ax1.set_xlabel('Average Time (seconds)', fontsize=12, fontweight='bold')
        ax1.set_title(f'Top {top_n} Schools - Average Times', fontsize=14, fontweight='bold')
        ax1.invert_yaxis()

        for i, bar in enumerate(bars1):
            width = bar.get_width()
            ax1.text(width, bar.get_y() + bar.get_height()/2,
                    f' {width:.2f}', ha='left', va='center', fontsize=9)

        # Best times
        colors2 = sns.color_palette("Blues_r", len(school_stats))
        bars2 = ax2.barh(range(len(school_stats)), school_stats['best_time'].values, color=colors2)
        ax2.set_yticks(range(len(school_stats)))
        ax2.set_yticklabels(school_stats.index)
        ax2.set_xlabel('Best Time (seconds)', fontsize=12, fontweight='bold')
        ax2.set_title(f'Top {top_n} Schools - Best Times', fontsize=14, fontweight='bold')
        ax2.invert_yaxis()

        for i, bar in enumerate(bars2):
            width = bar.get_width()
            ax2.text(width, bar.get_y() + bar.get_height()/2,
                    f' {width:.2f}', ha='left', va='center', fontsize=9)

        plt.tight_layout()
        plt.savefig(self.output_dir / '05_top_schools_comparison.png', dpi=300, bbox_inches='tight')
        plt.close()
        print("  ✓ Saved: 05_top_schools_comparison.png")

    def plot_event_heatmap(self):
        """Heatmap of average times by school and event"""
        print("Generating: School-Event Performance Heatmap...")

        # Get top 20 schools by record count
        top_schools = self.df['school_name'].value_counts().head(20).index

        # Create pivot table
        heatmap_data = self.df[self.df['school_name'].isin(top_schools)].pivot_table(
            values='time_seconds',
            index='school_name',
            columns='event',
            aggfunc='mean'
        )

        fig, ax = plt.subplots(figsize=(16, 10))

        sns.heatmap(heatmap_data, annot=False, cmap='YlOrRd', cbar_kws={'label': 'Avg Time (seconds)'},
                   linewidths=0.5, ax=ax)

        ax.set_title('Average Times by School and Event (Top 20 Schools)',
                    fontsize=16, fontweight='bold', pad=20)
        ax.set_xlabel('Event', fontsize=12, fontweight='bold')
        ax.set_ylabel('School', fontsize=12, fontweight='bold')
        plt.xticks(rotation=45, ha='right')
        plt.yticks(rotation=0)

        plt.tight_layout()
        plt.savefig(self.output_dir / '06_school_event_heatmap.png', dpi=300, bbox_inches='tight')
        plt.close()
        print("  ✓ Saved: 06_school_event_heatmap.png")

    def plot_freestyle_events_comparison(self):
        """Compare freestyle events across distances"""
        print("Generating: Freestyle Events Comparison...")

        freestyle_events = ['50 Free', '100 Free', '200 Free', '500 Free', '1000 Free', '1650 Free']
        freestyle_data = self.df[self.df['event'].isin(freestyle_events)].copy()

        if len(freestyle_data) == 0:
            print("  ⚠ No freestyle data found, skipping...")
            return

        fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(16, 12))

        # Box plot comparison
        data_for_box = [freestyle_data[freestyle_data['event'] == event]['time_seconds'].dropna()
                        for event in freestyle_events if event in freestyle_data['event'].unique()]
        labels_for_box = [event for event in freestyle_events if event in freestyle_data['event'].unique()]

        bp = ax1.boxplot(data_for_box, labels=labels_for_box, patch_artist=True)
        for patch, color in zip(bp['boxes'], sns.color_palette("Set2", len(data_for_box))):
            patch.set_facecolor(color)
            patch.set_alpha(0.7)

        ax1.set_ylabel('Time (seconds)', fontsize=12, fontweight='bold')
        ax1.set_title('Freestyle Events - Time Distribution Comparison', fontsize=14, fontweight='bold')
        ax1.grid(True, alpha=0.3)

        # Average times comparison
        avg_times = []
        for event in freestyle_events:
            event_data = freestyle_data[freestyle_data['event'] == event]['time_seconds'].dropna()
            if len(event_data) > 0:
                avg_times.append(event_data.mean())
            else:
                avg_times.append(0)

        colors = sns.color_palette("coolwarm", len(freestyle_events))
        bars = ax2.bar(range(len(freestyle_events)), avg_times, color=colors, alpha=0.7, edgecolor='black')
        ax2.set_xticks(range(len(freestyle_events)))
        ax2.set_xticklabels(freestyle_events, rotation=0)
        ax2.set_ylabel('Average Time (seconds)', fontsize=12, fontweight='bold')
        ax2.set_title('Freestyle Events - Average Times', fontsize=14, fontweight='bold')
        ax2.grid(True, alpha=0.3, axis='y')

        for i, (bar, time) in enumerate(zip(bars, avg_times)):
            if time > 0:
                ax2.text(bar.get_x() + bar.get_width()/2, bar.get_height(),
                        f'{time:.2f}s\n{self._seconds_to_time(time)}',
                        ha='center', va='bottom', fontsize=9, fontweight='bold')

        plt.tight_layout()
        plt.savefig(self.output_dir / '07_freestyle_comparison.png', dpi=300, bbox_inches='tight')
        plt.close()
        print("  ✓ Saved: 07_freestyle_comparison.png")

    def plot_stroke_comparison(self):
        """Compare 100 and 200 yard events across strokes"""
        print("Generating: Stroke Comparison...")

        stroke_100 = ['100 Free', '100 Back', '100 Breast', '100 Fly']
        stroke_200 = ['200 Free', '200 Back', '200 Breast', '200 Fly']

        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(18, 8))

        # 100 yard events
        data_100 = []
        labels_100 = []
        for event in stroke_100:
            event_data = self.df[self.df['event'] == event]['time_seconds'].dropna()
            if len(event_data) > 0:
                data_100.append(event_data)
                labels_100.append(event)

        bp1 = ax1.boxplot(data_100, labels=labels_100, patch_artist=True)
        colors1 = sns.color_palette("pastel", len(data_100))
        for patch, color in zip(bp1['boxes'], colors1):
            patch.set_facecolor(color)
            patch.set_alpha(0.8)

        ax1.set_ylabel('Time (seconds)', fontsize=12, fontweight='bold')
        ax1.set_title('100 Yard Events - Stroke Comparison', fontsize=14, fontweight='bold')
        ax1.grid(True, alpha=0.3)
        ax1.set_xticklabels(labels_100, rotation=15, ha='right')

        # 200 yard events
        data_200 = []
        labels_200 = []
        for event in stroke_200:
            event_data = self.df[self.df['event'] == event]['time_seconds'].dropna()
            if len(event_data) > 0:
                data_200.append(event_data)
                labels_200.append(event)

        bp2 = ax2.boxplot(data_200, labels=labels_200, patch_artist=True)
        colors2 = sns.color_palette("Set3", len(data_200))
        for patch, color in zip(bp2['boxes'], colors2):
            patch.set_facecolor(color)
            patch.set_alpha(0.8)

        ax2.set_ylabel('Time (seconds)', fontsize=12, fontweight='bold')
        ax2.set_title('200 Yard Events - Stroke Comparison', fontsize=14, fontweight='bold')
        ax2.grid(True, alpha=0.3)
        ax2.set_xticklabels(labels_200, rotation=15, ha='right')

        plt.tight_layout()
        plt.savefig(self.output_dir / '08_stroke_comparison.png', dpi=300, bbox_inches='tight')
        plt.close()
        print("  ✓ Saved: 08_stroke_comparison.png")

    def plot_swimmer_distribution(self):
        """Distribution of swimmers and times"""
        print("Generating: Swimmer Distribution Analysis...")

        fig, ((ax1, ax2), (ax3, ax4)) = plt.subplots(2, 2, figsize=(18, 12))

        # 1. Top swimmers by number of recorded times
        swimmer_counts = self.df['swimmer'].value_counts().head(20)
        colors1 = sns.color_palette("viridis", len(swimmer_counts))
        bars1 = ax1.barh(range(len(swimmer_counts)), swimmer_counts.values, color=colors1)
        ax1.set_yticks(range(len(swimmer_counts)))
        ax1.set_yticklabels(swimmer_counts.index, fontsize=9)
        ax1.set_xlabel('Number of Recorded Times', fontsize=11, fontweight='bold')
        ax1.set_title('Top 20 Swimmers by Record Count', fontsize=12, fontweight='bold')
        ax1.invert_yaxis()

        for i, bar in enumerate(bars1):
            width = bar.get_width()
            ax1.text(width, bar.get_y() + bar.get_height()/2,
                    f' {int(width)}', ha='left', va='center', fontsize=8)

        # 2. Distribution of times per swimmer
        times_per_swimmer = self.df.groupby('swimmer').size()
        ax2.hist(times_per_swimmer, bins=30, color='skyblue', edgecolor='black', alpha=0.7)
        ax2.set_xlabel('Number of Times Recorded', fontsize=11, fontweight='bold')
        ax2.set_ylabel('Number of Swimmers', fontsize=11, fontweight='bold')
        ax2.set_title('Distribution of Recorded Times per Swimmer', fontsize=12, fontweight='bold')
        ax2.axvline(times_per_swimmer.mean(), color='red', linestyle='--',
                   label=f'Mean: {times_per_swimmer.mean():.1f}')
        ax2.axvline(times_per_swimmer.median(), color='green', linestyle='--',
                   label=f'Median: {times_per_swimmer.median():.1f}')
        ax2.legend()
        ax2.grid(True, alpha=0.3)

        # 3. Schools by number of unique swimmers
        swimmers_per_school = self.df.groupby('school_name')['swimmer'].nunique().sort_values(ascending=False).head(20)
        colors3 = sns.color_palette("magma", len(swimmers_per_school))
        bars3 = ax3.barh(range(len(swimmers_per_school)), swimmers_per_school.values, color=colors3)
        ax3.set_yticks(range(len(swimmers_per_school)))
        ax3.set_yticklabels(swimmers_per_school.index, fontsize=9)
        ax3.set_xlabel('Number of Unique Swimmers', fontsize=11, fontweight='bold')
        ax3.set_title('Top 20 Schools by Roster Size', fontsize=12, fontweight='bold')
        ax3.invert_yaxis()

        for i, bar in enumerate(bars3):
            width = bar.get_width()
            ax3.text(width, bar.get_y() + bar.get_height()/2,
                    f' {int(width)}', ha='left', va='center', fontsize=8)

        # 4. Meet participation distribution
        meet_counts = self.df['meet'].value_counts().head(15)
        colors4 = sns.color_palette("rocket", len(meet_counts))
        bars4 = ax4.barh(range(len(meet_counts)), meet_counts.values, color=colors4)
        ax4.set_yticks(range(len(meet_counts)))
        # Truncate long meet names
        meet_labels = [label[:40] + '...' if len(label) > 40 else label for label in meet_counts.index]
        ax4.set_yticklabels(meet_labels, fontsize=8)
        ax4.set_xlabel('Number of Recorded Times', fontsize=11, fontweight='bold')
        ax4.set_title('Top 15 Meets by Participation', fontsize=12, fontweight='bold')
        ax4.invert_yaxis()

        for i, bar in enumerate(bars4):
            width = bar.get_width()
            ax4.text(width, bar.get_y() + bar.get_height()/2,
                    f' {int(width)}', ha='left', va='center', fontsize=8)

        plt.tight_layout()
        plt.savefig(self.output_dir / '09_swimmer_distribution.png', dpi=300, bbox_inches='tight')
        plt.close()
        print("  ✓ Saved: 09_swimmer_distribution.png")

    def plot_performance_ranges(self):
        """Performance range analysis"""
        print("Generating: Performance Range Analysis...")

        # Get top 10 schools
        top_schools = self.df['school_name'].value_counts().head(10).index

        fig, ax = plt.subplots(figsize=(16, 10))

        data_for_violin = []
        labels = []

        for school in top_schools:
            school_data = self.df[self.df['school_name'] == school]['time_seconds'].dropna()
            if len(school_data) > 0:
                data_for_violin.append(school_data)
                labels.append(school)

        parts = ax.violinplot(data_for_violin, positions=range(len(data_for_violin)),
                             showmeans=True, showmedians=True)

        for pc in parts['bodies']:
            pc.set_facecolor('lightcoral')
            pc.set_alpha(0.6)

        ax.set_xticks(range(len(labels)))
        ax.set_xticklabels(labels, rotation=45, ha='right')
        ax.set_ylabel('Time (seconds)', fontsize=12, fontweight='bold')
        ax.set_title('Performance Range Distribution - Top 10 Schools', fontsize=16, fontweight='bold', pad=20)
        ax.grid(True, alpha=0.3, axis='y')

        plt.tight_layout()
        plt.savefig(self.output_dir / '10_performance_ranges.png', dpi=300, bbox_inches='tight')
        plt.close()
        print("  ✓ Saved: 10_performance_ranges.png")

    def generate_all(self):
        """Generate all visualizations"""
        print("\n" + "="*80)
        print("GENERATING ALL VISUALIZATIONS")
        print("="*80 + "\n")

        self.plot_records_by_school()
        self.plot_events_distribution()
        self.plot_time_distributions_by_event()
        self.plot_top_schools_comparison()
        self.plot_event_heatmap()
        self.plot_freestyle_events_comparison()
        self.plot_stroke_comparison()
        self.plot_swimmer_distribution()
        self.plot_performance_ranges()

        print("\n" + "="*80)
        print("VISUALIZATION COMPLETE!")
        print("="*80)
        print(f"\nAll visualizations saved to: {self.output_dir.absolute()}/")
        print("\nGenerated files:")
        for file in sorted(self.output_dir.glob('*.png')):
            print(f"  - {file.name}")
        print("="*80 + "\n")


def main():
    visualizer = SwimDataVisualizer()
    visualizer.generate_all()


if __name__ == "__main__":
    main()
