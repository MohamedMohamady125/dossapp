# Men's Swimming Times - Visualizations Guide

All visualizations have been generated and saved in the `visualizations/` directory.

## Generated Visualizations

### 1. Records by School (01_records_by_school.png)
**Type:** Horizontal Bar Chart
**Description:** Shows the top 30 schools by number of recorded times in the dataset.
**Insights:**
- Identifies which schools have the most comprehensive data
- Helps understand team activity and size
- Color-coded from purple to yellow (viridis palette)

---

### 2. Events Distribution (02_events_distribution.png)
**Type:** Pie Chart + Bar Chart
**Description:** Two-panel view showing event distribution by percentage and count.
**Insights:**
- Left panel: Pie chart showing percentage breakdown of all events
- Right panel: Bar chart showing exact counts per event
- Helps identify which events are most commonly competed

---

### 3. Time Distributions - Box Plots (03_time_distributions_boxplot.png)
**Type:** Multi-panel Box Plots
**Description:** Box plots for all 14 swimming events showing time distributions.
**Insights:**
- Shows median times (red line), quartiles, and outliers
- Identifies variation within each event
- Useful for understanding competitive ranges

---

### 4. Time Distributions - Violin Plots (04_time_distributions_violin.png)
**Type:** Multi-panel Violin Plots
**Description:** Violin plots for all events showing probability density distributions.
**Insights:**
- Shows the shape of time distributions
- Wider sections = more swimmers at that time
- Helps identify common performance clusters

---

### 5. Top Schools Comparison (05_top_schools_comparison.png)
**Type:** Dual Horizontal Bar Charts
**Description:** Compares top 15 schools (with 50+ records) by average and best times.
**Insights:**
- Left panel: Average times across all events
- Right panel: Best recorded times
- Red-yellow-green color scheme (faster = greener)
- Identifies consistently fast programs

---

### 6. School-Event Performance Heatmap (06_school_event_heatmap.png)
**Type:** Heatmap
**Description:** Matrix showing average times for top 20 schools across all events.
**Insights:**
- Yellow = faster times, Red = slower times
- Shows which schools excel at which events
- Identifies event strengths and weaknesses per school

---

### 7. Freestyle Events Comparison (07_freestyle_comparison.png)
**Type:** Box Plot + Bar Chart
**Description:** Analysis of all freestyle events (50, 100, 200, 500, 1000, 1650).
**Insights:**
- Top panel: Box plots comparing distributions
- Bottom panel: Average times with formatted labels
- Shows progression across distances

---

### 8. Stroke Comparison (08_stroke_comparison.png)
**Type:** Dual Box Plots
**Description:** Compares performance across strokes at 100 and 200 yard distances.
**Insights:**
- Left panel: 100-yard events (Free, Back, Breast, Fly)
- Right panel: 200-yard events (Free, Back, Breast, Fly)
- Shows relative difficulty/speed of different strokes

---

### 9. Swimmer Distribution Analysis (09_swimmer_distribution.png)
**Type:** 4-Panel Multi-Chart
**Description:** Comprehensive view of swimmer and participation statistics.
**Insights:**
- Top-left: Top 20 swimmers by number of recorded times
- Top-right: Histogram of times per swimmer (mean and median shown)
- Bottom-left: Top 20 schools by roster size (unique swimmers)
- Bottom-right: Top 15 meets by participation

---

### 10. Performance Range Analysis (10_performance_ranges.png)
**Type:** Violin Plots
**Description:** Performance distribution for top 10 schools showing full range.
**Insights:**
- Shows team depth and consistency
- Wider distributions = more varied performance levels
- Helps compare team strength beyond just best times

---

## How to Use These Visualizations

### For Coaches:
- Use #5 and #6 to identify competitive programs
- Use #8 to understand stroke-specific performance
- Use #10 to assess team depth

### For Analysts:
- Use #3 and #4 to understand statistical distributions
- Use #6 for detailed school-event analysis
- Use #9 for participation and engagement metrics

### For Recruiters:
- Use #1 to find active programs
- Use #5 to identify top performing schools
- Use #9 to see roster sizes and swimmer activity

### For Swimmers:
- Use #3 and #4 to see where your times rank
- Use #7 and #8 to understand event difficulty
- Use #10 to compare school performance ranges

---

## Regenerating Visualizations

To regenerate all visualizations:

```bash
python3 visualize_mens_times.py
```

All images will be saved to the `visualizations/` folder in high resolution (300 DPI).

---

## File Sizes

All visualizations are high-resolution PNG files:
- Total size: ~3.9 MB
- Individual files: 200-800 KB each
- Resolution: 300 DPI (publication quality)

---

## Technical Details

**Tools Used:**
- Python 3
- Pandas (data manipulation)
- Matplotlib (plotting)
- Seaborn (statistical visualization)

**Color Schemes:**
- Viridis, Magma, Rocket (sequential)
- Set2, Set3, Pastel (qualitative)
- RdYlGn, YlOrRd, Blues (diverging)

**Chart Types:**
- Bar charts (horizontal and vertical)
- Box plots
- Violin plots
- Pie charts
- Heatmaps
- Histograms

---

## Next Steps

1. **Custom Analysis:** Modify `visualize_mens_times.py` to create specific charts
2. **Interactive Tool:** Use `analyze_mens_times.py` for detailed exploration
3. **Export Data:** Use the analysis scripts to export CSV summaries

---

## Support

For questions or custom visualizations, modify the `visualize_mens_times.py` script or use the `MensTimesAnalyzer` class from `analyze_mens_times.py`.
