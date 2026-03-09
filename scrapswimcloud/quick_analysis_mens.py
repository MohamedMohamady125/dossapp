#!/usr/bin/env python3
"""
Quick Analysis - Men's Swimming Times
Run predefined analyses without interactive menu
"""

from analyze_mens_times import MensTimesAnalyzer

def main():
    # Initialize analyzer
    print("Initializing analyzer...")
    analyzer = MensTimesAnalyzer()

    # 1. Dataset Overview
    analyzer.overview()

    # 2. List all events
    analyzer.list_events()

    # 3. Top 10 schools overall
    print("\n" + "="*80)
    print("QUICK ANALYSIS: TOP PERFORMING SCHOOLS")
    print("="*80)
    analyzer.top_schools_by_event(top_n=10)

    # 4. Top schools for specific popular events
    popular_events = ['50 Free', '100 Free', '200 Free', '100 Fly', '200 Im']
    for event in popular_events:
        analyzer.top_schools_by_event(event=event, top_n=5)

    # 5. Top swimmers in 100 Free
    analyzer.top_swimmers(event='100 Free', top_n=20)

    # 6. Event statistics for 100 Free
    analyzer.event_statistics('100 Free')

    # 7. Example school profiles (if they exist)
    example_schools = ['Stanford', 'California', 'Texas', 'Florida', 'Auburn']
    for school in example_schools:
        try:
            analyzer.school_profile(school)
        except:
            print(f"School {school} not found in dataset")
            continue

    # 8. Export summary
    print("\n" + "="*80)
    analyzer.export_summary('mens_times_detailed_summary.csv')

    print("\n" + "="*80)
    print("ANALYSIS COMPLETE!")
    print("="*80)
    print("\nGenerated Files:")
    print("  - mens_times_detailed_summary.csv")
    print("\nTo run interactive analysis, use: python3 analyze_mens_times.py")
    print("="*80)

if __name__ == "__main__":
    main()
