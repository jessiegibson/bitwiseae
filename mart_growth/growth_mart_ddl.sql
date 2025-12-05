-- ============================================
-- GROWTH/MARKETING MART DDL
-- Data Mart for Marketing Performance & Funnel Analytics
-- ============================================

-- Create schema (if not exists)
CREATE SCHEMA IF NOT EXISTS growth_mart;

-- ============================================
-- DIMENSION TABLES
-- ============================================

-- Dimension: dim_date
-- Standard date dimension for time-based analysis
CREATE OR REPLACE TABLE growth_mart.dim_date (
    date_key            INTEGER PRIMARY KEY,      -- YYYYMMDD format
    date_actual         DATE NOT NULL,
    day_of_week         INTEGER,
    day_name            VARCHAR(10),
    day_of_month        INTEGER,
    day_of_year         INTEGER,
    week_of_year        INTEGER,
    month_actual        INTEGER,
    month_name          VARCHAR(10),
    quarter_actual      INTEGER,
    quarter_name        VARCHAR(10),
    year_actual         INTEGER,
    is_weekend          BOOLEAN
);

-- Dimension: dim_channel
-- Marketing channels with UTM source mapping
CREATE OR REPLACE TABLE growth_mart.dim_channel (
    channel_key         INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_name        VARCHAR(50) NOT NULL,     -- e.g., 'Google Ads', 'LinkedIn', 'Meta'
    channel_category    VARCHAR(50),              -- e.g., 'Paid Search', 'Paid Social', 'Organic', 'Direct'
    utm_source          VARCHAR(50),              -- e.g., 'google', 'linkedin', 'facebook'
    is_paid             BOOLEAN
);

-- Dimension: dim_campaign
-- Campaign-level attributes from ad platforms
CREATE OR REPLACE TABLE growth_mart.dim_campaign (
    campaign_key        INTEGER PRIMARY KEY AUTOINCREMENT,
    campaign_id         VARCHAR(100) NOT NULL,    -- Natural key from ad_spend
    utm_campaign        VARCHAR(100),
    channel_key         INTEGER,                  -- FK to dim_channel
    campaign_name       VARCHAR(255),             -- Derived/friendly name
    FOREIGN KEY (channel_key) REFERENCES growth_mart.dim_channel(channel_key)
);

-- Dimension: dim_landing_page
-- Landing pages from web analytics
CREATE OR REPLACE TABLE growth_mart.dim_landing_page (
    landing_page_key    INTEGER PRIMARY KEY AUTOINCREMENT,
    landing_page_path   VARCHAR(255) NOT NULL,    -- e.g., '/pricing', '/demo', '/blog'
    page_category       VARCHAR(50),              -- e.g., 'Product', 'Content', 'Conversion'
    is_conversion_page  BOOLEAN
);

-- Dimension: dim_utm
-- UTM parameter combinations for attribution
CREATE OR REPLACE TABLE growth_mart.dim_utm (
    utm_key             INTEGER PRIMARY KEY AUTOINCREMENT,
    utm_source          VARCHAR(50),
    utm_campaign        VARCHAR(100),
    channel_key         INTEGER,                  -- FK to dim_channel
    FOREIGN KEY (channel_key) REFERENCES growth_mart.dim_channel(channel_key)
);

-- ============================================
-- FACT TABLES
-- ============================================

-- Fact: fct_ad_performance
-- Grain: One row per date + campaign_id (daily campaign performance)
CREATE OR REPLACE TABLE growth_mart.fct_ad_performance (
    ad_performance_key  INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Dimension Foreign Keys
    date_key            INTEGER NOT NULL,         -- FK to dim_date
    campaign_key        INTEGER NOT NULL,         -- FK to dim_campaign
    channel_key         INTEGER NOT NULL,         -- FK to dim_channel

    -- Measures
    spend_usd           DECIMAL(12, 2),
    clicks              INTEGER,
    impressions         INTEGER,

    -- Derived Metrics (can also be calculated in views)
    ctr                 DECIMAL(10, 6),           -- Click-through rate (clicks/impressions)
    cpc                 DECIMAL(10, 4),           -- Cost per click (spend/clicks)
    cpm                 DECIMAL(10, 4),           -- Cost per mille (spend/impressions * 1000)

    -- Audit
    loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    FOREIGN KEY (date_key) REFERENCES growth_mart.dim_date(date_key),
    FOREIGN KEY (campaign_key) REFERENCES growth_mart.dim_campaign(campaign_key),
    FOREIGN KEY (channel_key) REFERENCES growth_mart.dim_channel(channel_key)
);

-- Fact: fct_web_sessions
-- Grain: One row per session_id (session-level web analytics)
CREATE OR REPLACE TABLE growth_mart.fct_web_sessions (
    web_session_key     INTEGER PRIMARY KEY AUTOINCREMENT,
    session_id          VARCHAR(50) NOT NULL,     -- Natural key from web_analytics
    user_id             VARCHAR(50),

    -- Dimension Foreign Keys
    session_date_key    INTEGER NOT NULL,         -- FK to dim_date
    channel_key         INTEGER,                  -- FK to dim_channel (derived from utm_source)
    landing_page_key    INTEGER,                  -- FK to dim_landing_page
    utm_key             INTEGER,                  -- FK to dim_utm

    -- Measures
    pageviews           INTEGER,
    conversions         INTEGER,

    -- Flags
    is_converted        BOOLEAN,                  -- TRUE if conversions > 0
    is_attributed       BOOLEAN,                  -- TRUE if UTM params present

    -- Audit
    loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    FOREIGN KEY (session_date_key) REFERENCES growth_mart.dim_date(date_key),
    FOREIGN KEY (channel_key) REFERENCES growth_mart.dim_channel(channel_key),
    FOREIGN KEY (landing_page_key) REFERENCES growth_mart.dim_landing_page(landing_page_key),
    FOREIGN KEY (utm_key) REFERENCES growth_mart.dim_utm(utm_key)
);

-- Fact: fct_channel_roi
-- Grain: One row per channel (aggregated totals for ROI calculation)
-- Joins marketing data with closed deals for full-funnel ROI
CREATE OR REPLACE TABLE growth_mart.fct_channel_roi (
    channel_roi_key         INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Dimension Foreign Keys
    channel_key             INTEGER NOT NULL,         -- FK to dim_channel

    -- Period (for filtering)
    period_start_date       DATE,
    period_end_date         DATE,

    -- Marketing Metrics (totals)
    total_spend_usd         DECIMAL(14, 2),
    total_impressions       INTEGER,
    total_clicks            INTEGER,
    total_sessions          INTEGER,
    total_conversions       INTEGER,

    -- Sales Metrics (from salesforce)
    total_opportunities     INTEGER,
    total_closed_won        INTEGER,
    total_closed_lost       INTEGER,
    total_pipeline_value    DECIMAL(14, 2),
    total_closed_won_revenue DECIMAL(14, 2),

    -- ROI & Efficiency Metrics
    roi_percentage          DECIMAL(10, 2),           -- (Revenue - Spend) / Spend * 100
    roas                    DECIMAL(10, 2),           -- Return on Ad Spend: Revenue / Spend
    cac                     DECIMAL(10, 2),           -- Customer Acquisition Cost: Spend / Closed Won
    cost_per_opportunity    DECIMAL(10, 2),           -- Spend / Total Opportunities
    opportunity_to_closed_won_rate DECIMAL(10, 2),    -- Closed Won / Total Opportunities * 100

    -- Audit
    loaded_at               TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    FOREIGN KEY (channel_key) REFERENCES growth_mart.dim_channel(channel_key)
);

-- Fact: fct_marketing_funnel
-- Grain: One row per date + channel (daily channel-level funnel metrics)
-- This is an aggregated fact table for funnel/ROI analysis
CREATE OR REPLACE TABLE growth_mart.fct_marketing_funnel (
    funnel_key          INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Dimension Foreign Keys
    date_key            INTEGER NOT NULL,         -- FK to dim_date
    channel_key         INTEGER NOT NULL,         -- FK to dim_channel

    -- Top of Funnel (from ad_spend)
    spend_usd           DECIMAL(12, 2),
    impressions         INTEGER,
    clicks              INTEGER,

    -- Middle of Funnel (from web_analytics)
    sessions            INTEGER,
    total_pageviews     INTEGER,
    conversions         INTEGER,

    -- Bottom of Funnel (from salesforce_opportunities)
    opportunities       INTEGER,
    pipeline_value_usd  DECIMAL(14, 2),
    closed_won_opps     INTEGER,
    closed_won_revenue  DECIMAL(14, 2),
    closed_lost_opps    INTEGER,

    -- Derived Efficiency Metrics
    ctr                 DECIMAL(10, 6),           -- clicks / impressions
    cpc                 DECIMAL(10, 4),           -- spend / clicks
    cost_per_session    DECIMAL(10, 4),           -- spend / sessions
    cost_per_conversion DECIMAL(10, 4),           -- spend / conversions
    cost_per_opportunity DECIMAL(10, 4),          -- spend / opportunities
    cac                 DECIMAL(10, 4),           -- Customer Acquisition Cost: spend / closed_won_opps

    -- Derived Conversion Rates
    click_to_session_rate    DECIMAL(10, 6),      -- sessions / clicks
    session_conversion_rate  DECIMAL(10, 6),      -- conversions / sessions
    opp_win_rate            DECIMAL(10, 6),       -- closed_won_opps / opportunities

    -- ROI Metrics
    revenue_per_click   DECIMAL(10, 4),           -- closed_won_revenue / clicks
    roas                DECIMAL(10, 4),           -- Return on Ad Spend: closed_won_revenue / spend
    roi                 DECIMAL(10, 4),           -- ROI: (closed_won_revenue - spend) / spend

    -- Audit
    loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    FOREIGN KEY (date_key) REFERENCES growth_mart.dim_date(date_key),
    FOREIGN KEY (channel_key) REFERENCES growth_mart.dim_channel(channel_key)
);

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

-- Indexes on fact tables for common query patterns
CREATE INDEX IF NOT EXISTS idx_fct_ad_performance_date ON growth_mart.fct_ad_performance(date_key);
CREATE INDEX IF NOT EXISTS idx_fct_ad_performance_channel ON growth_mart.fct_ad_performance(channel_key);
CREATE INDEX IF NOT EXISTS idx_fct_web_sessions_date ON growth_mart.fct_web_sessions(session_date_key);
CREATE INDEX IF NOT EXISTS idx_fct_web_sessions_channel ON growth_mart.fct_web_sessions(channel_key);
CREATE INDEX IF NOT EXISTS idx_fct_marketing_funnel_date ON growth_mart.fct_marketing_funnel(date_key);
CREATE INDEX IF NOT EXISTS idx_fct_marketing_funnel_channel ON growth_mart.fct_marketing_funnel(channel_key);

-- ============================================
-- VIEWS FOR COMMON ANALYSES
-- ============================================

-- View: Channel Performance Summary
CREATE OR REPLACE VIEW growth_mart.v_channel_performance AS
SELECT
    c.channel_name,
    c.channel_category,
    SUM(f.spend_usd) AS total_spend,
    SUM(f.impressions) AS total_impressions,
    SUM(f.clicks) AS total_clicks,
    SUM(f.sessions) AS total_sessions,
    SUM(f.conversions) AS total_conversions,
    SUM(f.opportunities) AS total_opportunities,
    SUM(f.closed_won_opps) AS total_closed_won,
    SUM(f.closed_won_revenue) AS total_revenue,
    -- Calculated metrics
    CASE WHEN SUM(f.impressions) > 0 THEN SUM(f.clicks) / SUM(f.impressions) END AS overall_ctr,
    CASE WHEN SUM(f.clicks) > 0 THEN SUM(f.spend_usd) / SUM(f.clicks) END AS overall_cpc,
    CASE WHEN SUM(f.closed_won_opps) > 0 THEN SUM(f.spend_usd) / SUM(f.closed_won_opps) END AS overall_cac,
    CASE WHEN SUM(f.spend_usd) > 0 THEN SUM(f.closed_won_revenue) / SUM(f.spend_usd) END AS overall_roas,
    CASE WHEN SUM(f.spend_usd) > 0 THEN (SUM(f.closed_won_revenue) - SUM(f.spend_usd)) / SUM(f.spend_usd) END AS overall_roi
FROM growth_mart.fct_marketing_funnel f
JOIN growth_mart.dim_channel c ON f.channel_key = c.channel_key
GROUP BY c.channel_name, c.channel_category;

-- View: Weekly Funnel Trends
CREATE OR REPLACE VIEW growth_mart.v_weekly_funnel_trends AS
SELECT
    d.year_actual,
    d.week_of_year,
    MIN(d.date_actual) AS week_start_date,
    c.channel_name,
    SUM(f.spend_usd) AS weekly_spend,
    SUM(f.clicks) AS weekly_clicks,
    SUM(f.sessions) AS weekly_sessions,
    SUM(f.conversions) AS weekly_conversions,
    SUM(f.closed_won_opps) AS weekly_closed_won,
    SUM(f.closed_won_revenue) AS weekly_revenue
FROM growth_mart.fct_marketing_funnel f
JOIN growth_mart.dim_date d ON f.date_key = d.date_key
JOIN growth_mart.dim_channel c ON f.channel_key = c.channel_key
GROUP BY d.year_actual, d.week_of_year, c.channel_name;
