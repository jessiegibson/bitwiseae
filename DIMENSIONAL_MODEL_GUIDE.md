# How to Use Your GTM Funnel Dimensional Model

## Overview

You've created two complementary data marts with a well-designed dimensional model:

- **`sales_mart`**: Sales Operations perspective (opportunities, pipeline, regions, deal stages)
- **`growth_mart`**: Marketing/Growth perspective (ad performance, web sessions, funnel metrics, ROI)

This guide explains how to use these models effectively for analysis and reporting.

---
## Table of Contents

1. [Understanding the Model Architecture](#1-understanding-the-model-architecture)
2. [How to Query the Model](#2-how-to-query-the-model)
3. [Common Analysis Patterns](#3-common-analysis-patterns)
4. [Example Queries](#4-example-queries)
5. [Best Practices](#5-best-practices)
6. [Troubleshooting](#6-troubleshooting)

---
## 1. Understanding the Model Architecture
### Sales Mart Structure
```
DIMENSIONS (Descriptive Attributes)
├── dim_date              → Time-based analysis
├── dim_channel           → Marketing channel attributes
├── dim_campaign          → Campaign-level details
├── dim_deal_stage        → Opportunity stage attributes
└── dim_sales_region      → Geographic/territory information

FACTS (Measures & Metrics)
├── fct_opportunities     → All opportunities (grain: 1 row per opportunity)
└── fct_closed_deals      → Closed-won only (grain: 1 row per closed-won opportunity)
```

**Use Sales Mart for:**
- Sales pipeline analysis
- Opportunity win rates by region
- Deal stage progression
- Sales performance by territory
- Opportunity source attribution

---
### Marketing Mart Structure
```
DIMENSIONS (Descriptive Attributes)
├── dim_date              → Time-based analysis
├── dim_channel           → Marketing channel attributes
├── dim_campaign          → Campaign-level details
├── dim_landing_page      → Landing page categorization
└── dim_utm               → UTM parameter combinations

FACTS (Measures & Metrics)
├── fct_ad_performance    → Daily campaign metrics (grain: 1 row per date + campaign)
├── fct_web_sessions      → Session-level analytics (grain: 1 row per session)
├── fct_channel_roi       → Channel aggregates (grain: 1 row per channel + period)
└── fct_marketing_funnel  → Daily channel funnel (grain: 1 row per date + channel)
```

**Use Growth Mart for:**
- Channel performance and ROI
- Marketing funnel analysis
- Campaign effectiveness
- Web session behavior
- Ad spend efficiency (CTR, CPC, CPA)
- Targeting Efficiency - CPM

---
## 2. How to Query the Model
### Basic Query Pattern

```sql
SELECT
    -- Dimensions (what you're grouping/filtering by)
    d.column_name,

    -- Facts/Measures (what you're calculating)
    SUM(f.measure_column) AS total_metric,
    AVG(f.measure_column) AS avg_metric,
    COUNT(DISTINCT f.id_column) AS count_metric

FROM fact_table f
JOIN dimension_table d ON f.dimension_key = d.dimension_key
WHERE d.filter_column = 'filter_value'
GROUP BY d.column_name
ORDER BY total_metric DESC;
```

### Key Join Patterns

**Time-Based Joins:**
```sql
-- Join fact to date dimension
FROM fct_marketing_funnel f
JOIN dim_date d ON f.date_key = d.date_key
WHERE d.year_actual = 2025
  AND d.month_actual IN (9, 10, 11)  -- Q4
```

**Channel Analysis:**
```sql
-- Join fact to channel dimension
FROM fct_ad_performance f
JOIN dim_channel c ON f.channel_key = c.channel_key
WHERE c.is_paid = TRUE
  AND c.channel_category = 'Paid Social'
```

**Multi-Dimension Analysis:**
```sql
-- Join multiple dimensions
FROM fct_marketing_funnel f
JOIN dim_date d ON f.date_key = d.date_key
JOIN dim_channel c ON f.channel_key = c.channel_key
WHERE d.quarter_actual = 4
  AND c.is_paid = TRUE
GROUP BY d.month_name, c.channel_name
```

---
## 3. Common Analysis Patterns
### Pattern 1: Channel Performance Analysis

**Question:** "Which marketing channels are most effective?"

**Which Mart:** `growth_mart`
**Primary Table:** `fct_channel_roi` (aggregate) or `fct_marketing_funnel` (daily detail)

```sql
SELECT
    c.channel_name,
    c.channel_category,
    SUM(f.spend_usd) AS total_spend,
    SUM(f.closed_won_revenue) AS total_revenue,
    SUM(f.closed_won_opps) AS closed_won_count,

    -- Calculated metrics
    SUM(f.closed_won_revenue) / NULLIF(SUM(f.spend_usd), 0) AS roas,
    (SUM(f.closed_won_revenue) - SUM(f.spend_usd)) / NULLIF(SUM(f.spend_usd), 0) AS roi,
    SUM(f.spend_usd) / NULLIF(SUM(f.closed_won_opps), 0) AS cac

FROM growth_mart.fct_marketing_funnel f
JOIN growth_mart.dim_channel c ON f.channel_key = c.channel_key
GROUP BY c.channel_name, c.channel_category
ORDER BY roi DESC;
```

---

### Pattern 2: Funnel Conversion Analysis
**Question:** "Where are we losing prospects in the marketing funnel?"
**Which Mart:** `growth_mart`
**Primary Table:** `fct_marketing_funnel`

```sql
SELECT
    c.channel_name,

    -- Top of funnel
    SUM(f.impressions) AS total_impressions,
    SUM(f.clicks) AS total_clicks,
    SUM(f.clicks)::FLOAT / NULLIF(SUM(f.impressions), 0) AS ctr,

    -- Middle of funnel
    SUM(f.sessions) AS total_sessions,
    SUM(f.conversions) AS total_conversions,
    SUM(f.sessions)::FLOAT / NULLIF(SUM(f.clicks), 0) AS click_to_session_rate,
    SUM(f.conversions)::FLOAT / NULLIF(SUM(f.sessions), 0) AS session_conversion_rate,

    -- Bottom of funnel
    SUM(f.opportunities) AS total_opportunities,
    SUM(f.closed_won_opps) AS total_closed_won,
    SUM(f.closed_won_opps)::FLOAT / NULLIF(SUM(f.opportunities), 0) AS opp_win_rate

FROM growth_mart.fct_marketing_funnel f
JOIN growth_mart.dim_channel c ON f.channel_key = c.channel_key
GROUP BY c.channel_name
ORDER BY total_closed_won DESC;
```

---

### Pattern 3: Sales Pipeline Analysis

**Question:** "What's the health of our sales pipeline by channel?"

**Which Mart:** `sales_mart`
**Primary Table:** `fct_opportunities`

```sql
SELECT
    c.channel_name,
    s.stage_name,
    s.stage_category,

    COUNT(DISTINCT o.opportunity_id) AS opp_count,
    SUM(o.amount_usd) AS total_value,
    AVG(o.amount_usd) AS avg_deal_size

FROM sales_mart.fct_opportunities o
JOIN sales_mart.dim_channel c ON o.channel_key = c.channel_key
JOIN sales_mart.dim_deal_stage s ON o.stage_key = s.stage_key
GROUP BY c.channel_name, s.stage_name, s.stage_category, s.stage_order
ORDER BY c.channel_name, s.stage_order;
```

---

### Pattern 4: Time-Based Trend Analysis

**Question:** "How has channel performance changed over time?"

**Which Mart:** `growth_mart`
**Primary Table:** `fct_marketing_funnel`

```sql
SELECT
    d.year_actual,
    d.month_name,
    c.channel_name,

    SUM(f.spend_usd) AS monthly_spend,
    SUM(f.clicks) AS monthly_clicks,
    SUM(f.conversions) AS monthly_conversions,
    SUM(f.closed_won_revenue) AS monthly_revenue,

    -- Month-over-month growth (use window functions)
    SUM(f.closed_won_revenue) - LAG(SUM(f.closed_won_revenue))
        OVER (PARTITION BY c.channel_name ORDER BY d.year_actual, d.month_actual) AS mom_revenue_change

FROM growth_mart.fct_marketing_funnel f
JOIN growth_mart.dim_date d ON f.date_key = d.date_key
JOIN growth_mart.dim_channel c ON f.channel_key = c.channel_key
GROUP BY d.year_actual, d.month_actual, d.month_name, c.channel_name
ORDER BY d.year_actual, d.month_actual, c.channel_name;
```

---

### Pattern 5: Campaign-Level Deep Dive

**Question:** "Which specific campaigns perform best within a channel?"

**Which Mart:** `growth_mart`
**Primary Table:** `fct_ad_performance`

```sql
SELECT
    c.channel_name,
    camp.campaign_name,
    camp.utm_campaign,

    SUM(f.spend_usd) AS campaign_spend,
    SUM(f.clicks) AS campaign_clicks,
    AVG(f.ctr) AS avg_ctr,
    AVG(f.cpc) AS avg_cpc

FROM growth_mart.fct_ad_performance f
JOIN growth_mart.dim_campaign camp ON f.campaign_key = camp.campaign_key
JOIN growth_mart.dim_channel c ON f.channel_key = c.channel_key
WHERE c.channel_name = 'Google Ads'  -- Focus on one channel
GROUP BY c.channel_name, camp.campaign_name, camp.utm_campaign
ORDER BY campaign_spend DESC
LIMIT 10;
```

---

### Pattern 6: Regional Sales Performance

**Question:** "How do opportunities vary by region and channel?"

**Which Mart:** `sales_mart`
**Primary Table:** `fct_opportunities`

```sql
SELECT
    r.region_name,
    c.channel_name,

    COUNT(DISTINCT o.opportunity_id) AS total_opps,
    SUM(CASE WHEN s.is_won = TRUE THEN 1 ELSE 0 END) AS won_opps,
    SUM(CASE WHEN s.is_won = TRUE THEN o.amount_usd ELSE 0 END) AS won_revenue,

    AVG(CASE WHEN s.is_won = TRUE THEN o.amount_usd END) AS avg_deal_size

FROM sales_mart.fct_opportunities o
JOIN sales_mart.dim_sales_region r ON o.region_key = r.region_key
JOIN sales_mart.dim_channel c ON o.channel_key = c.channel_key
JOIN sales_mart.dim_deal_stage s ON o.stage_key = s.stage_key
GROUP BY r.region_name, c.channel_name
ORDER BY won_revenue DESC;
```

---

## 4. Example Queries

### Example 1: Top 5 Campaigns by ROI

```sql
-- Find the most profitable campaigns
WITH campaign_performance AS (
    SELECT
        camp.campaign_name,
        c.channel_name,
        SUM(f.spend_usd) AS total_spend,
        SUM(f.clicks) AS total_clicks,

        -- Need to join to web sessions for conversions (if tracked)
        -- For now, use aggregate from funnel table
        0 AS placeholder_conversions  -- Replace with actual conversion tracking

    FROM growth_mart.fct_ad_performance f
    JOIN growth_mart.dim_campaign camp ON f.campaign_key = camp.campaign_key
    JOIN growth_mart.dim_channel c ON f.channel_key = c.channel_key
    GROUP BY camp.campaign_name, c.channel_name
)
SELECT *
FROM campaign_performance
WHERE total_spend > 1000  -- Minimum spend threshold
ORDER BY total_clicks / NULLIF(total_spend, 0) DESC  -- Clicks per dollar
LIMIT 5;
```

---

### Example 2: Weekly Performance Dashboard

```sql
-- Create a weekly summary for leadership dashboard
SELECT
    d.year_actual,
    d.week_of_year,
    MIN(d.date_actual) AS week_start_date,

    SUM(f.spend_usd) AS weekly_spend,
    SUM(f.clicks) AS weekly_clicks,
    SUM(f.sessions) AS weekly_sessions,
    SUM(f.conversions) AS weekly_conversions,
    SUM(f.opportunities) AS weekly_opps,
    SUM(f.closed_won_opps) AS weekly_closed_won,
    SUM(f.closed_won_revenue) AS weekly_revenue,

    -- Calculated metrics
    SUM(f.closed_won_revenue) / NULLIF(SUM(f.spend_usd), 0) AS weekly_roas,
    SUM(f.conversions)::FLOAT / NULLIF(SUM(f.sessions), 0) AS weekly_conversion_rate

FROM growth_mart.fct_marketing_funnel f
JOIN growth_mart.dim_date d ON f.date_key = d.date_key
GROUP BY d.year_actual, d.week_of_year
ORDER BY d.year_actual, d.week_of_year;
```

---

### Example 3: Channel Attribution Comparison

```sql
-- Compare different channels' contribution to pipeline
SELECT
    c.channel_name,
    c.channel_category,

    -- Marketing metrics
    SUM(f.spend_usd) AS total_marketing_spend,

    -- Sales metrics
    COUNT(DISTINCT o.opportunity_id) AS opportunities_created,
    SUM(CASE WHEN s.is_won THEN o.amount_usd ELSE 0 END) AS revenue_attributed,

    -- Efficiency metrics
    SUM(CASE WHEN s.is_won THEN o.amount_usd ELSE 0 END) / NULLIF(SUM(f.spend_usd), 0) AS marketing_attributed_roas

FROM growth_mart.fct_marketing_funnel f
JOIN growth_mart.dim_channel c ON f.channel_key = c.channel_key
LEFT JOIN sales_mart.fct_opportunities o ON c.channel_key = o.channel_key
LEFT JOIN sales_mart.dim_deal_stage s ON o.stage_key = s.stage_key
GROUP BY c.channel_name, c.channel_category
ORDER BY revenue_attributed DESC;
```

---

## 5. Best Practices

### When to Use Each Mart

| Analysis Type | Use This Mart | Reason |
|---------------|---------------|---------|
| Channel ROI, ad efficiency | `growth_mart` | Pre-aggregated funnel metrics |
| Campaign performance | `growth_mart` | Daily campaign-level detail |
| Web session behavior | `growth_mart` | Session-level granularity |
| Pipeline health | `sales_mart` | Opportunity stage tracking |
| Regional performance | `sales_mart` | Territory/region dimensions |
| Deal velocity | `sales_mart` | Opportunity-level timestamps |

---

### Query Performance Tips

1. **Use Pre-Aggregated Tables When Possible**
   - `fct_channel_roi` for channel summaries (faster than aggregating `fct_marketing_funnel`)
   - `fct_marketing_funnel` for daily channel trends (faster than joining raw facts)

2. **Filter on Indexed Columns**
   - Date filters: Use `date_key` instead of `date_actual`
   - Channel filters: Use `channel_key` instead of `channel_name`

3. **Leverage Date Dimension for Time Filtering**
   ```sql
   -- Good: Use date dimension attributes
   WHERE d.year_actual = 2025 AND d.quarter_actual = 4

   -- Avoid: Parsing date functions on fact table
   WHERE YEAR(f.some_date) = 2025  -- Slower
   ```

4. **Avoid SELECT * on Large Fact Tables**
   - Always specify columns you need
   - Fact tables can be very large (millions of rows)

---

### Metric Calculation Best Practices

**Always Use NULLIF to Prevent Division by Zero:**
```sql
-- Good
SUM(revenue) / NULLIF(SUM(spend), 0) AS roi

-- Bad (will error if spend = 0)
SUM(revenue) / SUM(spend) AS roi
```

**Cast to FLOAT for Accurate Percentages:**
```sql
-- Good: Accurate decimal result
SUM(conversions)::FLOAT / NULLIF(SUM(sessions), 0) AS conversion_rate

-- Bad: Integer division truncates to 0
SUM(conversions) / NULLIF(SUM(sessions), 0)  -- Returns 0 or 1
```

**Use CASE Statements for Conditional Aggregation:**
```sql
-- Count only closed-won opportunities
SUM(CASE WHEN stage = 'Closed Won' THEN 1 ELSE 0 END) AS won_count

-- Sum revenue only for closed-won
SUM(CASE WHEN stage = 'Closed Won' THEN amount_usd ELSE 0 END) AS won_revenue
```

---

## 6. Troubleshooting

### Problem: "My results don't match between Growth Mart and Sales Mart"

**Cause:** Different grains and attribution models

**Solution:**
- Growth Mart uses **daily channel-level** aggregation
- Sales Mart uses **opportunity-level** detail
- Attribution mapping `source` → `channel` may differ

**Check:**
```sql
-- Verify channel mapping consistency
SELECT DISTINCT source FROM salesforce_opportunities
EXCEPT
SELECT DISTINCT channel_name FROM dim_channel;

-- This should return empty or only "Organic", "Direct" (non-paid sources)
```

---

### Problem: "I'm getting duplicate rows in my results"

**Cause:** Missing GROUP BY or incorrect join logic

**Solution:**
1. Always use `GROUP BY` when using aggregate functions (SUM, COUNT, AVG)
2. Check for many-to-many joins (e.g., joining web sessions to opportunities without proper keys)

**Debug:**
```sql
-- Add DISTINCT to see unique combinations
SELECT DISTINCT
    f.opportunity_id,
    c.channel_name
FROM fct_opportunities f
JOIN dim_channel c ON f.channel_key = c.channel_key;
```

---

### Problem: "Conversion rates look too low or too high"

**Cause:** Attribution gaps or UTM parameter issues

**Check:**
```sql
-- How many sessions lack UTM attribution?
SELECT
    COUNT(*) AS total_sessions,
    SUM(CASE WHEN utm_key IS NULL THEN 1 ELSE 0 END) AS unattributed_sessions,
    SUM(CASE WHEN utm_key IS NULL THEN 1 ELSE 0 END)::FLOAT / COUNT(*) AS pct_unattributed
FROM growth_mart.fct_web_sessions;

-- If > 30% unattributed, your conversion metrics will be understated
```

---

### Problem: "Query is running very slow"

**Optimization Steps:**

1. **Check if indexes exist:**
   ```sql
   -- List indexes
   SHOW INDEXES FROM growth_mart.fct_marketing_funnel;
   ```

2. **Use EXPLAIN to see query plan:**
   ```sql
   EXPLAIN
   SELECT ...
   FROM fct_marketing_funnel f
   JOIN dim_date d ON f.date_key = d.date_key;
   ```

3. **Add date filters to reduce scan:**
   ```sql
   -- Good: Limits data scanned
   WHERE d.date_actual >= '2025-09-01'

   -- Bad: Scans entire table
   -- (no WHERE clause)
   ```

---

## Summary: Your Go-To Query Templates

### 📊 For Marketing (Head of Growth):
```sql
-- Channel ROI Summary
SELECT channel_name, total_spend, closed_won_revenue, roi, roas
FROM growth_mart.fct_channel_roi;
```

### 💰 For Sales (Head of Sales Ops):
```sql
-- Pipeline Health by Source
SELECT c.channel_name, s.stage_name, COUNT(*) AS opp_count, SUM(amount_usd) AS pipeline_value
FROM sales_mart.fct_opportunities o
JOIN sales_mart.dim_channel c ON o.channel_key = c.channel_key
JOIN sales_mart.dim_deal_stage s ON o.stage_key = s.stage_key
GROUP BY c.channel_name, s.stage_name;
```

### 📈 For Trend Analysis:
```sql
-- Weekly Funnel Trends
SELECT year_actual, week_of_year, channel_name,
       SUM(spend_usd), SUM(sessions), SUM(conversions), SUM(closed_won_revenue)
FROM growth_mart.fct_marketing_funnel f
JOIN growth_mart.dim_date d ON f.date_key = d.date_key
JOIN growth_mart.dim_channel c ON f.channel_key = c.channel_key
GROUP BY year_actual, week_of_year, channel_name;
```

---

## Need Help?

- **Documentation:** See data dictionary at `data/_data_dictionary.md`
- **Schema DDL:** Review `sales_mart_ddl.sql` and `growth_mart_ddl.sql`
- **Sample Queries:** Check pre-built views in DDL files:
  - `growth_mart.v_channel_performance`
  - `growth_mart.v_weekly_funnel_trends`

---

**Created:** 2025-12-03
**Version:** 1.0
**Maintainer:** Analytics Engineering Team
