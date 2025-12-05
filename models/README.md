# Data Models Architecture

This directory contains the refactored dimensional model for the GTM (Go-To-Market) funnel analytics data mart. The architecture follows a layered approach with shared dimensions and domain-specific marts.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              DATA FLOW                                       │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   ┌──────────────┐     ┌──────────────┐     ┌────────────────────────────┐  │
│   │   RAW_DATA   │     │   STAGING    │     │          COMMON            │  │
│   │              │     │              │     │                            │  │
│   │ • ad_spend   │────▶│ • stg_ad_    │────▶│  • dim_date                │  │
│   │ • web_       │     │   spend      │     │  • dim_channel             │  │
│   │   analytics  │     │ • stg_web_   │     │  • dim_campaign            │  │
│   │ • salesforce_│     │   analytics  │     │  • dim_landing_page        │  │
│   │   opps       │     │ • stg_sf_    │     │  • dim_region              │  │
│   │              │     │   opps       │     │  • dim_deal_stage          │  │
│   └──────────────┘     └──────────────┘     └─────────────┬──────────────┘  │
│                                                           │                  │
│                              ┌────────────────────────────┴───────────┐      │
│                              │                                        │      │
│                              ▼                                        ▼      │
│                  ┌───────────────────────┐            ┌─────────────────────┐│
│                  │     SALES_MART        │            │   MARKETING_MART    ││
│                  │                       │            │                     ││
│                  │ • fct_opportunities   │            │ • fct_ad_performance││
│                  │ • fct_closed_deals    │            │ • fct_web_sessions  ││
│                  │ • fct_pipeline_       │            │ • fct_marketing_    ││
│                  │   snapshot            │            │   funnel            ││
│                  │ • fct_sales_summary   │            │ • fct_channel_roi   ││
│                  │                       │            │ • fct_campaign_     ││
│                  │                       │            │   performance       ││
│                  └───────────────────────┘            └─────────────────────┘│
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Directory Structure

```
models/
├── README.md                           # This file
├── raw_data/                           # Layer 1: Source data landing zone
│   └── raw_data_ddl.sql               
├── staging/                            # Layer 2: Cleaned & standardized data
│   └── staging_ddl.sql                
├── common/                             # Layer 3: Shared dimension tables
│   ├── common_dimensions_ddl.sql      
│   └── common_dimensions_populate.sql 
└── marts/                              # Layer 4: Business-facing marts
    ├── sales/                          # Sales/Revenue analytics
    │   ├── sales_mart_ddl.sql         
    │   └── sales_mart_populate.sql    
    └── marketing/                      # Marketing/Growth analytics
        ├── marketing_mart_ddl.sql     
        └── marketing_mart_populate.sql
```

## Schema Descriptions

### 1. RAW_DATA Schema

**Purpose:** Landing zone for source data files. No transformations applied.

| Table | Source File | Description |
|-------|-------------|-------------|
| `ad_spend` | ad_spend.csv | Daily advertising performance by campaign |
| `web_analytics` | web_analytics.csv | Session-level web analytics |
| `salesforce_opportunities` | salesforce_opportunities.csv | CRM opportunity data |

**Key Features:**
- Mirrors source file structure exactly
- Includes `_loaded_at` and `_source_file` metadata columns
- No data transformations or business logic

### 2. STAGING Schema

**Purpose:** Clean, standardize, and prepare data for dimensional modeling.

| Table | Source | Transformations Applied |
|-------|--------|------------------------|
| `stg_ad_spend` | raw_data.ad_spend | Normalize channel names, lowercase UTMs, calculate CTR/CPC/CPM |
| `stg_web_analytics` | raw_data.web_analytics | Derive channel from UTM source, add conversion flags |
| `stg_salesforce_opportunities` | raw_data.salesforce_opportunities | Categorize stages, normalize source/region |

**Reference Tables:**
- `ref_channel_mapping` - UTM source to channel mapping
- `ref_region_mapping` - Region name standardization

**Data Quality Views:**
- `v_stg_ad_spend_quality` - Ad spend validation metrics
- `v_stg_web_analytics_quality` - Web analytics validation
- `v_stg_opportunities_quality` - Opportunity validation

### 3. COMMON Schema

**Purpose:** Shared dimension tables used by all marts. Single source of truth for conformed dimensions.

| Dimension | Description | Key Attributes |
|-----------|-------------|----------------|
| `dim_date` | Calendar dimension | date_key, date_actual, week/month/quarter/year attributes, flags |
| `dim_channel` | Marketing channels | channel_name, channel_category, utm_source, is_paid |
| `dim_campaign` | Ad campaigns | campaign_id, campaign_name, utm_campaign, channel_key |
| `dim_landing_page` | Web landing pages | landing_page_path, page_category, is_conversion_page |
| `dim_region` | Sales regions | region_code, region_name, super_region |
| `dim_deal_stage` | Opportunity stages | stage_name, stage_category, is_closed, is_won, stage_order |

**Why Shared Dimensions?**
- **Consistency:** Same channel definition across Sales and Marketing
- **Maintainability:** Update once, reflect everywhere
- **Query Performance:** Smaller dimension tables, faster joins
- **Drill-across:** Enable queries that span multiple fact tables

### 4. SALES_MART Schema

**Purpose:** Serve Sales Ops and Revenue Analytics use cases.

| Fact Table | Grain | Key Measures |
|------------|-------|--------------|
| `fct_opportunities` | One row per opportunity | amount_usd, is_closed, is_won |
| `fct_closed_deals` | One row per closed-won opportunity | deal_amount_usd |
| `fct_pipeline_snapshot` | One row per opportunity per snapshot date | amount_usd, days_in_stage |
| `fct_sales_summary` | One row per date + channel + region | opp counts, revenue totals, win_rate |

**Key Views:**
- `v_opportunities_detail` - Flattened star schema for ad-hoc queries
- `v_channel_performance` - Channel-level sales metrics
- `v_regional_performance` - Regional performance summary
- `v_monthly_revenue_trend` - Monthly revenue by channel

### 5. MARKETING_MART Schema

**Purpose:** Serve Marketing/Growth Analytics use cases.

| Fact Table | Grain | Key Measures |
|------------|-------|--------------|
| `fct_ad_performance` | One row per date + campaign | spend, clicks, impressions, CTR, CPC, CPM |
| `fct_web_sessions` | One row per session | pageviews, conversions, is_converted |
| `fct_marketing_funnel` | One row per date + channel | Full funnel: spend→clicks→sessions→conversions→opps→revenue |
| `fct_channel_roi` | One row per channel (period aggregate) | ROI, ROAS, CAC, cost metrics |
| `fct_campaign_performance` | One row per campaign (aggregate) | Campaign-level efficiency metrics |

**Key Views:**
- `v_sessions_detail` - Flattened session data with all dimensions
- `v_channel_performance` - Marketing channel ROI summary
- `v_weekly_funnel_trends` - Weekly funnel metrics by channel
- `v_landing_page_performance` - Landing page conversion analysis
- `v_campaign_comparison` - Campaign performance comparison
- `v_funnel_visualization` - Data formatted for funnel charts

## Execution Order

Run the scripts in this order for a full refresh:

```sql
-- 1. Create schemas and raw tables
\i models/raw_data/raw_data_ddl.sql

-- 2. Load source data into raw tables
-- (Use COPY commands or your ETL tool)

-- 3. Create and populate staging tables
\i models/staging/staging_ddl.sql

-- 4. Create common dimension tables
\i models/common/common_dimensions_ddl.sql

-- 5. Populate common dimensions
\i models/common/common_dimensions_populate.sql

-- 6. Create sales mart tables
\i models/marts/sales/sales_mart_ddl.sql

-- 7. Populate sales mart
\i models/marts/sales/sales_mart_populate.sql

-- 8. Create marketing mart tables
\i models/marts/marketing/marketing_mart_ddl.sql

-- 9. Populate marketing mart
\i models/marts/marketing/marketing_mart_populate.sql
```

## Key Design Decisions

### Attribution Model
- **Current Approach:** Direct source-to-channel mapping (rule-based)
- `salesforce_opportunities.source` → `dim_channel.channel_name`
- `web_analytics.utm_source` → `dim_channel.utm_source`
- **Limitation:** No multi-touch or time-decay attribution

### Date Handling
- All dates converted to integer keys in YYYYMMDD format
- `dim_date` covers 3 years (2024-2026) by default
- Fiscal year assumed equal to calendar year

### Channel Standardization
- UTM sources normalized: `google` → `Google Ads`, `facebook` → `Meta`
- Unknown/null sources mapped to `Direct` channel
- Paid vs Organic determined by presence of UTM parameters

### Grain Decisions
| Fact Table | Grain | Rationale |
|------------|-------|-----------|
| fct_ad_performance | Date + Campaign | Match source grain, support daily trending |
| fct_web_sessions | Session | Preserve session-level detail for analysis |
| fct_marketing_funnel | Date + Channel | Balance granularity vs query performance |
| fct_opportunities | Opportunity | Preserve detail for drill-down |

## Metrics Glossary

| Metric | Formula | Used In |
|--------|---------|---------|
| CTR (Click-Through Rate) | clicks / impressions | Marketing |
| CPC (Cost Per Click) | spend / clicks | Marketing |
| CPM (Cost Per Mille) | (spend / impressions) × 1000 | Marketing |
| CAC (Customer Acquisition Cost) | spend / closed_won_count | Both |
| ROAS (Return on Ad Spend) | revenue / spend | Marketing |
| ROI (Return on Investment) | (revenue - spend) / spend | Both |
| Win Rate | closed_won / (closed_won + closed_lost) | Sales |
| Conversion Rate | conversions / sessions | Marketing |

## Query Examples

### Channel ROI Comparison
```sql
SELECT 
    channel_name,
    total_spend_usd,
    total_closed_won_revenue,
    roi_percentage,
    roas,
    cac
FROM marketing_mart.fct_channel_roi
ORDER BY roi_percentage DESC;
```

### Full Funnel by Channel
```sql
SELECT 
    c.channel_name,
    SUM(f.impressions) AS impressions,
    SUM(f.clicks) AS clicks,
    SUM(f.sessions) AS sessions,
    SUM(f.conversions) AS conversions,
    SUM(f.opportunities) AS opportunities,
    SUM(f.closed_won_opps) AS closed_won
FROM marketing_mart.fct_marketing_funnel f
JOIN common.dim_channel c ON f.channel_key = c.channel_key
GROUP BY c.channel_name;
```

### Sales Pipeline by Region
```sql
SELECT 
    r.region_name,
    COUNT(*) AS total_opps,
    SUM(CASE WHEN f.is_won THEN f.amount_usd ELSE 0 END) AS won_revenue,
    SUM(CASE WHEN NOT f.is_closed THEN f.amount_usd ELSE 0 END) AS pipeline_value
FROM sales_mart.fct_opportunities f
JOIN common.dim_region r ON f.region_key = r.region_key
GROUP BY r.region_name;
```

## Future Enhancements

1. **Multi-touch Attribution:** Add session-to-opportunity linking with attribution weighting
2. **SCD Type 2:** Implement slowly changing dimensions for campaign and opportunity stage history
3. **Real-time Layer:** Add streaming tables for live dashboard updates
4. **Data Quality Framework:** Add Great Expectations or dbt tests
5. **Semantic Layer:** Define metrics in a semantic layer (Cube, dbt Metrics, LookML)