#!/usr/bin/env python3
"""
Sequential Scraper Runner
This script monitors the current Division 1 Page 3 scraper and automatically
starts the Division 2 Page 1 scraper when it completes.
"""

import subprocess
import time
import os
import psutil
from datetime import datetime

def find_running_scraper():
    """Find if scrape_division1_schools.py is currently running"""
    for proc in psutil.process_iter(['pid', 'name', 'cmdline']):
        try:
            cmdline = proc.info['cmdline']
            if cmdline and 'python' in cmdline[0].lower():
                if any('scrape_division1_schools.py' in arg for arg in cmdline):
                    return proc.info['pid']
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess):
            pass
    return None

def monitor_and_run():
    """Monitor current scraper and run Division 2 when complete"""
    print("="*80)
    print("SEQUENTIAL SCRAPER SCHEDULER")
    print("="*80)
    print(f"\nStarted at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

    # Check if Division 1 Page 3 scraper is running
    print("Checking for running Division 1 Page 3 scraper...")
    pid = find_running_scraper()

    if pid:
        print(f"✓ Found running scraper (PID: {pid})")
        print(f"⏳ Waiting for Division 1 Page 3 scraper to complete...\n")

        # Monitor the process
        try:
            process = psutil.Process(pid)
            check_count = 0
            while process.is_running():
                check_count += 1
                if check_count % 30 == 0:  # Print status every 30 seconds
                    elapsed = check_count // 2  # seconds
                    print(f"  Still running... ({elapsed}s elapsed)")
                time.sleep(2)

            print(f"\n✓ Division 1 Page 3 scraper completed!")
            print(f"  Finished at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")

        except psutil.NoSuchProcess:
            print(f"\n✓ Division 1 Page 3 scraper completed!")
    else:
        print("⚠ No Division 1 Page 3 scraper currently running.")
        print("  It may have already completed.")

    # Wait a bit before starting next scraper
    print("\nWaiting 5 seconds before starting Division 2 Page 1 scraper...")
    time.sleep(5)

    # Start Division 2 Page 1 scraper
    print("\n" + "="*80)
    print("STARTING DIVISION 2 PAGE 1 SCRAPER")
    print("="*80)
    print(f"Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

    d2_page1_success = False
    try:
        # Run the Division 2 Page 1 scraper
        result = subprocess.run(
            ['python3', 'scrape_division2_schools.py'],
            cwd=os.path.dirname(os.path.abspath(__file__))
        )

        if result.returncode == 0:
            print("\n" + "="*80)
            print("✓ DIVISION 2 PAGE 1 SCRAPER COMPLETED SUCCESSFULLY!")
            print("="*80)
            print(f"Completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            d2_page1_success = True
        else:
            print("\n" + "="*80)
            print("✗ DIVISION 2 PAGE 1 SCRAPER FAILED")
            print("="*80)
            print(f"Exit code: {result.returncode}")

    except Exception as e:
        print(f"\n✗ Error running Division 2 Page 1 scraper: {e}")
        import traceback
        traceback.print_exc()

    # If Division 2 Page 1 succeeded, continue with Division 2 Page 2
    if d2_page1_success:
        print("\nWaiting 5 seconds before starting Division 2 Page 2 scraper...")
        time.sleep(5)

        print("\n" + "="*80)
        print("STARTING DIVISION 2 PAGE 2 SCRAPER")
        print("="*80)
        print(f"Started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

        try:
            # Run the Division 2 Page 2 scraper
            result = subprocess.run(
                ['python3', 'scrape_division2_page2_schools.py'],
                cwd=os.path.dirname(os.path.abspath(__file__))
            )

            if result.returncode == 0:
                print("\n" + "="*80)
                print("✓ DIVISION 2 PAGE 2 SCRAPER COMPLETED SUCCESSFULLY!")
                print("="*80)
                print(f"Completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
            else:
                print("\n" + "="*80)
                print("✗ DIVISION 2 PAGE 2 SCRAPER FAILED")
                print("="*80)
                print(f"Exit code: {result.returncode}")

        except Exception as e:
            print(f"\n✗ Error running Division 2 Page 2 scraper: {e}")
            import traceback
            traceback.print_exc()

    print("\n" + "="*80)
    print("SEQUENTIAL SCRAPING COMPLETE!")
    print("="*80)
    print(f"All tasks finished at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

if __name__ == "__main__":
    monitor_and_run()
