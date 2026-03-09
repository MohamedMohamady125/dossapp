#!/usr/bin/env python3
"""
Quick Rankings Display - Shows all rankings automatically
"""

from analyze_rankings import RankingsAnalyzer


def main():
    # Initialize analyzer
    analyzer = RankingsAnalyzer()

    # 1. Overview
    analyzer.overview()

    # 2. Men's Top 30
    analyzer.mens_national_rankings(top_n=30)

    # 3. Women's Top 30
    analyzer.womens_national_rankings(top_n=30)

    # 4. Compare Men's vs Women's
    analyzer.compare_mens_womens(top_n=25)

    # 5. Top Conferences
    analyzer.top_conferences()

    # 6. List all conferences
    analyzer.list_conferences()

    # 7. Example: Show specific conference
    print("\n\n" + "="*100)
    print("EXAMPLE: ACC CONFERENCE RANKINGS")
    print("="*100)
    analyzer.conference_rankings('ACC')

    # 8. Example: Show specific school
    print("\n\n" + "="*100)
    print("EXAMPLE: SPECIFIC SCHOOL RANKINGS")
    print("="*100)
    analyzer.school_rankings('Stanford')

    # 9. Export reports
    print("\n\n" + "="*100)
    print("EXPORTING REPORTS")
    print("="*100)
    analyzer.export_rankings_report('complete_rankings.csv')

    print("\n" + "="*100)
    print("ANALYSIS COMPLETE!")
    print("="*100)
    print("\nTo run interactive analysis: python3 analyze_rankings.py")
    print("="*100)


if __name__ == "__main__":
    main()
