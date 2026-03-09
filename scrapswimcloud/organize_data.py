import csv
import json

def organize_swimcloud_data(input_file):
    """Reorganize the scraped data into multiple readable CSV files"""

    print("="*80)
    print("ORGANIZING SWIMCLOUD DATA")
    print("="*80)

    # Read the complete data
    with open(input_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        all_data = list(reader)

    print(f"\nRead {len(all_data)} schools from {input_file}")

    # 1. Create schools_info.csv with core information
    print("\n[1/3] Creating schools_info.csv...")

    info_fields = [
        'name',
        'abbreviation',
        'team_id',
        'url',
        'logo_url',
        'website_url',
        'city',
        'state',
        'zip_code',
        'division',
        'conference',
        'national_ranking',
        'conference_ranking',
        'has_mens_team',
        'has_womens_team',
        'total_athletes',
        'founded_year',
        'ncaa_id',
        'description',
        'facilities_description'
    ]

    with open('schools_info.csv', 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=info_fields, extrasaction='ignore')
        writer.writeheader()
        for school in all_data:
            # Only write fields that exist
            row = {k: school.get(k, '') for k in info_fields}
            writer.writerow(row)

    print(f"   ✓ Created schools_info.csv with {len(info_fields)} columns")

    # 2. Create schools_mens_times.csv
    print("\n[2/3] Creating schools_mens_times.csv...")

    mens_times_data = []
    for school in all_data:
        school_name = school.get('name', '')
        team_id = school.get('team_id', '')

        # Extract all men's times
        for key, value in school.items():
            if key.startswith('mens_') and '_rank' in key and value:
                # Parse the key: mens_50_free_rank1_time
                parts = key.replace('mens_', '').split('_')

                # Find where 'rank' appears
                rank_idx = None
                for i, part in enumerate(parts):
                    if part.startswith('rank'):
                        rank_idx = i
                        break

                if rank_idx:
                    # Event is everything before 'rank'
                    event = '_'.join(parts[:rank_idx])
                    # Rank number and field type (time/swimmer/meet)
                    rank_num = parts[rank_idx].replace('rank', '')
                    field_type = '_'.join(parts[rank_idx+1:])

                    # Find or create the time entry
                    existing = None
                    for t in mens_times_data:
                        if (t['school_name'] == school_name and
                            t['event'] == event.replace('_', ' ').title() and
                            t['rank'] == int(rank_num)):
                            existing = t
                            break

                    if existing:
                        existing[field_type] = value
                    else:
                        new_entry = {
                            'school_name': school_name,
                            'team_id': team_id,
                            'event': event.replace('_', ' ').title(),
                            'rank': int(rank_num),
                            'time': '',
                            'swimmer': '',
                            'meet': ''
                        }
                        new_entry[field_type] = value
                        mens_times_data.append(new_entry)

    # Write men's times (sorted by school, event, rank)
    if mens_times_data:
        mens_times_data.sort(key=lambda x: (x['school_name'], x['event'], x['rank']))
        mens_fields = ['school_name', 'team_id', 'event', 'rank', 'time', 'swimmer', 'meet']
        with open('schools_mens_times.csv', 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=mens_fields, extrasaction='ignore')
            writer.writeheader()
            for entry in mens_times_data:
                writer.writerow(entry)

        print(f"   ✓ Created schools_mens_times.csv with {len(mens_times_data)} time entries")

    # 3. Create schools_womens_times.csv
    print("\n[3/3] Creating schools_womens_times.csv...")

    womens_times_data = []
    for school in all_data:
        school_name = school.get('name', '')
        team_id = school.get('team_id', '')

        # Extract all women's times
        for key, value in school.items():
            if key.startswith('womens_') and '_rank' in key and value:
                # Parse the key: womens_50_free_rank1_time
                parts = key.replace('womens_', '').split('_')

                # Find where 'rank' appears
                rank_idx = None
                for i, part in enumerate(parts):
                    if part.startswith('rank'):
                        rank_idx = i
                        break

                if rank_idx:
                    # Event is everything before 'rank'
                    event = '_'.join(parts[:rank_idx])
                    # Rank number and field type (time/swimmer/meet)
                    rank_num = parts[rank_idx].replace('rank', '')
                    field_type = '_'.join(parts[rank_idx+1:])

                    # Find or create the time entry
                    existing = None
                    for t in womens_times_data:
                        if (t['school_name'] == school_name and
                            t['event'] == event.replace('_', ' ').title() and
                            t['rank'] == int(rank_num)):
                            existing = t
                            break

                    if existing:
                        existing[field_type] = value
                    else:
                        new_entry = {
                            'school_name': school_name,
                            'team_id': team_id,
                            'event': event.replace('_', ' ').title(),
                            'rank': int(rank_num),
                            'time': '',
                            'swimmer': '',
                            'meet': ''
                        }
                        new_entry[field_type] = value
                        womens_times_data.append(new_entry)

    # Write women's times (sorted by school, event, rank)
    if womens_times_data:
        womens_times_data.sort(key=lambda x: (x['school_name'], x['event'], x['rank']))
        womens_fields = ['school_name', 'team_id', 'event', 'rank', 'time', 'swimmer', 'meet']
        with open('schools_womens_times.csv', 'w', newline='', encoding='utf-8') as f:
            writer = csv.DictWriter(f, fieldnames=womens_fields, extrasaction='ignore')
            writer.writeheader()
            for entry in womens_times_data:
                writer.writerow(entry)

        print(f"   ✓ Created schools_womens_times.csv with {len(womens_times_data)} time entries")

    # Summary
    print("\n" + "="*80)
    print("ORGANIZATION COMPLETE!")
    print("="*80)
    print("\nCreated files:")
    print(f"  1. schools_info.csv - {len(all_data)} schools × {len(info_fields)} columns")
    print(f"  2. schools_mens_times.csv - {len(mens_times_data)} time entries")
    print(f"  3. schools_womens_times.csv - {len(womens_times_data)} time entries")
    print("\nEach file is organized and easy to view in Excel/Google Sheets!")
    print("="*80 + "\n")

if __name__ == "__main__":
    organize_swimcloud_data('swimcloud_schools_complete.csv')
