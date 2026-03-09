import csv

print("\n" + "="*80)
print("EXTRACTING WEBSITE URLs FROM EXISTING DATA")
print("="*80)

# Read the existing schools_info.csv
input_file = "schools_info.csv"
output_file = "all_schools_websites.csv"

schools_data = []

try:
    with open(input_file, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            schools_data.append({
                'name': row.get('name', ''),
                'team_id': row.get('team_id', ''),
                'swimcloud_url': row.get('url', ''),
                'website_url': row.get('website_url', '')
            })

    print(f"\n✓ Read {len(schools_data)} schools from {input_file}")

    # Write to new file
    with open(output_file, 'w', newline='', encoding='utf-8') as f:
        fieldnames = ['name', 'team_id', 'swimcloud_url', 'website_url']
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for school in schools_data:
            writer.writerow(school)

    print(f"✓ Saved {len(schools_data)} schools to {output_file}")

    # Statistics
    schools_with_website = sum(1 for s in schools_data if s.get('website_url'))
    schools_without_website = len(schools_data) - schools_with_website

    print(f"\nStatistics:")
    print(f"  - Schools with website: {schools_with_website}")
    print(f"  - Schools without website: {schools_without_website}")
    print(f"  - Total schools: {len(schools_data)}")

    # Show first 10 schools
    print(f"\nFirst 10 schools:")
    for i, school in enumerate(schools_data[:10], 1):
        print(f"  [{i}] {school['name']}")
        print(f"      Website: {school['website_url'] or 'Not available'}")

except FileNotFoundError:
    print(f"\n✗ Error: {input_file} not found!")
    print("Please run scrape_division1_schools.py first to generate the data.")
except Exception as e:
    print(f"\n✗ Error: {e}")
    import traceback
    traceback.print_exc()

print("\n" + "="*80)
print("DONE!")
print("="*80 + "\n")
