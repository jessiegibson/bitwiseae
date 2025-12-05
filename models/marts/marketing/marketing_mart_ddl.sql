-- ============================================
-- MARKETING MART DDL
-- Fact tables for Marketing/Growth Analytics
-- References common dimension tables
-- ============================================

-- Create schema
CREATE SCHEMA IF NOT EXISTS marketing_mart;

-- ============================================
-- FACT: fct_ad_performance
-- Grain: One row per date + campaign
-- Daily campaign-level ad metrics
-- ============================================

CREATE OR REPLACE TABLE marketing_mart.fct_ad_performance (
    -- Surrogate key
    ad_performance_sk       INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Dimension Foreign Keys (referencing common schema)
    date_key                INTEGER NOT NULL,         -- FK to common.dim_date
    campaign_key            INTEGER NOT NULL,         -- FK to common.dim_campaign
    channel_key             INTEGER NOT NULL,         -- FK to common.dim_channel

    -- Raw Measures (additive)
    spend_usd               DECIMAL(12, 2) NOT NULL DEFAULT 0,
    clicks                  INTEGER NOT NULL DEFAULT 0,
    impressions             INTEGER NOT NULL DEFAULT 0,

    -- Derived Metrics (calculated at load time for performance)
    ctr                     DECIMAL(10, 6),           -- Click-through rate (clicks/impressions)
    cpc                     DECIMAL(10, 4),           -- Cost per click (spend/clicks)
    cpm                     DECIMAL(10, 4),           -- Cost per mille (spend/impressions * 1000)

    -- Audit fields
    _loaded_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Foreign key constraints
    FOREIGN KEY (date_key) REFERENCES common.dim_date(date_key),
    FOREIGN KEY (campaign_key) REFERENCES common.dim_campaign(campaign_key),
    FOREIGN KEY (channel_key) REFERENCES common.dim_channel(channel_key)
);

-- ============================================
-- FACT: fct_web_sessions
-- Grain: One row per session
-- Session-level web analytics
-- ============================================

CREATE OR REPLACE TABLE marketing_mart.fct_web_sessions (
    -- Surrogate key
    web_session_sk          INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Natural key
    session_id              VARCHAR(50) NOT NULL UNIQUE,
    user_id                 VARCHAR(50),

    -- Dimension Foreign Keys (referencing common schema)
    session_date_key        INTEGER NOT NULL,         -- FK to common.dim_date
    channel_key             INTEGER,                  -- FK to common.dim_channel (derived from utm_source)
    campaign_key            INTEGER,                  -- FK to common.dim_campaign (via utm_campaign)
    landing_page_key        INTEGER,                  -- FK to common.dim_landing_page

    -- UTM parameters (degenerate dimensions)
    utm_source              VARCHAR(50),
    utm_campaign            VARCHAR(100),

    -- Measures
    pageviews               INTEGER NOT NULL DEFAULT 0,
    conversions             INTEGER NOT NULL DEFAULT 0,

    -- Derived flags
    is_converted            BOOLEAN NOT NULL DEFAULT FALSE,   -- TRUE if conversions > 0
    is_attributed           BOOLEAN NOT NULL DEFAULT FALSE,   -- TRUE if UTM params present
    is_bounce               BOOLEAN NOT NULL DEFAULT FALSE,   -- TRUE if pageviews = 1

    -- Audit fields
    _loaded_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Foreign key constraints
    FOREIGN KEY (session_date_key) REFERENCES common.dim_date(date_key),
    FOREIGN KEY (channel_key) REFERENCES common.dim_channel(channel_key),
    FOREIGN KEY (campaign_key) REFERENCES common.dim_campaign(campaign_key),
    FOREIGN KEY (landing_page_key) REFERENCES common.dim_landing_page(landing_page_key)
);

-- ============================================
-- FACT: fct_marketing_funnel
-- Grain: One row per date + channel
-- Daily channel-level funnel metrics (aggregated)
-- ============================================

CREATE OR REPLACE TABLE marketing_mart.fct_marketing_funnel (
    -- Surrogate key
    funnel_sk               INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Dimension Foreign Keys
    date_key                INTEGER NOT NULL,         -- FK to common.dim_date
    channel_key             INTEGER NOT NULL,         -- FK to common.dim_channel

    -- Top of Funnel (from ad_spend)
    spend_usd               DECIMAL(12, 2) DEFAULT 0,
    impressions             INTEGER DEFAULT 0,
    clicks                  INTEGER DEFAULT 0,

    -- Middle of Funnel (from web_analytics)
    sessions                INTEGER DEFAULT 0,
    unique_users            INTEGER DEFAULT 0,
    total_pageviews         INTEGER DEFAULT 0,
    conversions             INTEGER DEFAULT 0,
    bounces                 INTEGER DEFAULT 0,

    -- Bottom of Funnel (from salesforce - opportunities created on this date)
    opportunities           INTEGER DEFAULT 0,
    pipeline_value_usd      DECIMAL(14, 2) DEFAULT 0,
    closed_won_opps         INTEGER DEFAULT 0,
    closed_won_revenue      DECIMAL(14, 2) DEFAULT 0,
    closed_lost_opps        INTEGER DEFAULT 0,

    -- Derived Efficiency Metrics
    ctr                     DECIMAL(10, 6),           -- clicks / impressions
    cpc                     DECIMAL(10, 4),           -- spend / clicks
    cpm                     DECIMAL(10, 4),           -- spend / impressions * 1000
    cost_per_session        DECIMAL(10, 4),           -- spend / sessions
    cost_per_conversion     DECIMAL(10, 4),           -- spend / conversions
    cost_per_opportunity    DECIMAL(10, 4),           -- spend / opportunities
    cac                     DECIMAL(10, 4),           -- Customer Acquisition Cost: spend / closed_won_opps

    -- Derived Conversion Rates
    click_to_session_rate   DECIMAL(10, 6),           -- sessions / clicks
    session_conversion_rate DECIMAL(10, 6),           -- conversions / sessions
    bounce_rate             DECIMAL(10, 6),           -- bounces / sessions
    opp_win_rate            DECIMAL(10, 6),           -- closed_won_opps / opportunities

    -- ROI Metrics
    revenue_per_click       DECIMAL(10, 4),           -- closed_won_revenue / clicks
    roas                    DECIMAL(10, 4),           -- Return on Ad Spend: closed_won_revenue / spend
    roi                     DECIMAL(10, 4),           -- ROI: (closed_won_revenue - spend) / spend

    -- Audit fields
    _loaded_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Foreign key constraints
    FOREIGN KEY (date_key) REFERENCES common.dim_date(date_key),
    FOREIGN KEY (channel_key) REFERENCES common.dim_channel(channel_key)
);

-- ============================================
-- FACT: fct_channel_roi
-- Grain: One row per channel (period aggregate)
-- Summary ROI metrics by channel
-- ============================================

CREATE OR REPLACE TABLE marketing_mart.fct_channel_roi (
    -- Surrogate key
    channel_roi_sk          INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Dimension Foreign Keys
    channel_key             INTEGER NOT NULL,         -- FK to common.dim_channel

    -- Period definition
    period_start_date       DATE,
    period_end_date         DATE,
    period_type             VARCHAR(20) DEFAULT 'all_time',  -- 'all_time', 'ytd', 'qtd', 'mtd'

    -- Marketing Metrics (totals)
    total_spend_usd         DECIMAL(14, 2) DEFAULT 0,
    total_impressions       BIGINT DEFAULT 0,
    total_clicks            INTEGER DEFAULT 0,
    total_sessions          INTEGER DEFAULT 0,
    total_conversions       INTEGER DEFAULT 0,

    -- Sales Metrics (from salesforce)
    total_opportunities     INTEGER DEFAULT 0,
    total_closed_won        INTEGER DEFAULT 0,
    total_closed_lost       INTEGER DEFAULT 0,
    total_pipeline_value    DECIMAL(14, 2) DEFAULT 0,
    total_closed_won_revenue DECIMAL(14, 2) DEFAULT 0,

    -- Efficiency Metrics
    avg_ctr                 DECIMAL(10, 6),           -- Overall CTR
    avg_cpc                 DECIMAL(10, 4),           -- Overall CPC
    avg_cpm                 DECIMAL(10, 4),           -- Overall CPM

    -- ROI & Efficiency Metrics
    roi_percentage          DECIMAL(10, 2),           -- (Revenue - Spend) / Spend * 100
    roas                    DECIMAL(10, 2),           -- Return on Ad Spend: Revenue / Spend
    cac                     DECIMAL(10, 2),           -- Customer Acquisition Cost: Spend / Closed Won
    cost_per_opportunity    DECIMAL(10, 2),           -- Spend / Total Opportunities
    cost_per_conversion     DECIMAL(10, 2),           -- Spend / Conversions
    ltv_to_cac_ratio        DECIMAL(10, 2),           -- Avg deal size / CAC (if LTV available)

    -- Conversion Rates
    click_to_session_rate   DECIMAL(10, 4),
    session_to_conversion_rate DECIMAL(10, 4),
    conversion_to_opp_rate  DECIMAL(10, 4),
    opp_to_closed_won_rate  DECIMAL(10, 4),           -- Win rate

    -- Audit fields
    _loaded_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Foreign key constraints
    FOREIGN KEY (channel_key) REFERENCES common.dim_channel(channel_key)
);

-- ============================================
-- FACT: fct_campaign_performance
-- Grain: One row per campaign (period aggregate)
-- Campaign-level performance summary
-- ============================================

CREATE OR REPLACE TABLE marketing_mart.fct_campaign_performance (
    -- Surrogate key
    campaign_performance_sk INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Dimension Foreign Keys
    campaign_key            INTEGER NOT NULL,         -- FK to common.dim_campaign
    channel_key             INTEGER NOT NULL,         -- FK to common.dim_channel

    -- Period definition
    period_start_date       DATE,
    period_end_date         DATE,

    -- Ad Metrics (totals)
    total_spend_usd         DECIMAL(14, 2) DEFAULT 0,
    total_impressions       BIGINT DEFAULT 0,
    total_clicks            INTEGER DEFAULT 0,

    -- Web Metrics (totals)
    total_sessions          INTEGER DEFAULT 0,
    total_conversions       INTEGER DEFAULT 0,

    -- Efficiency Metrics
    avg_ctr                 DECIMAL(10, 6),
    avg_cpc                 DECIMAL(10, 4),
    avg_cpm                 DECIMAL(10, 4),
    conversion_rate         DECIMAL(10, 6),
    cost_per_conversion     DECIMAL(10, 4),

    -- Campaign status
    days_active             INTEGER,
    is_active               BOOLEAN DEFAULT TRUE,

    -- Audit fields
    _loaded_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Foreign key constraints
    FOREIGN KEY (campaign_key) REFERENCES common.dim_campaign(campaign_key),
    FOREIGN KEY (channel_key) REFERENCES common.dim_channel(channel_key)
);

-- ============================================
-- INDEXES FOR QUERY PERFORMANCE
-- ============================================

-- fct_ad_performance indexes
CREATE INDEX IF NOT EXISTS idx_fct_ad_perf_date ON marketing_mart.fct_ad_performance(date_key);
CREATE INDEX IF NOT EXISTS idx_fct_ad_perf_campaign ON marketing_mart.fct_ad_performance(campaign_key);
CREATE INDEX IF NOT EXISTS idx_fct_ad_perf_channel ON marketing_mart.fct_ad_performance(channel_key);

-- fct_web_sessions indexes
CREATE INDEX IF NOT EXISTS idx_fct_web_sess_date ON marketing_mart.fct_web_sessions(session_date_key);
CREATE INDEX IF NOT EXISTS idx_fct_web_sess_channel ON marketing_mart.fct_web_sessions(channel_key);
CREATE INDEX IF NOT EXISTS idx_fct_web_sess_campaign ON marketing_mart.fct_web_sessions(campaign_key);
CREATE INDEX IF NOT EXISTS idx_fct_web_sess_landing ON marketing_mart.fct_web_sessions(landing_page_key);
CREATE INDEX IF NOT EXISTS idx_fct_web_sess_converted ON marketing_mart.fct_web_sessions(is_converted);

-- fct_marketing_funnel indexes
CREATE INDEX IF NOT EXISTS idx_fct_funnel_date ON marketing_mart.fct_marketing_funnel(date_key);
CREATE INDEX IF NOT EXISTS idx_fct_funnel_channel ON marketing_mart.fct_marketing_funnel(channel_key);

-- fct_channel_roi indexes
CREATE INDEX IF NOT EXISTS idx_fct_roi_channel ON marketing_mart.fct_channel_roi(channel_key);

-- ============================================
-- VIEWS FOR COMMON ANALYSES
-- ============================================

-- View: Web sessions with dimension attributes (star schema flattened)
CREATE OR REPLACE VIEW marketing_mart.v_sessions_detail AS
SELECT
    f.session_id,
    f.user_id,
    f.pageviews,
    f.conversions,
    f.is_converted,
    f.is_attributed,
    f.utm_source,
    f.utm_campaign,
    -- Date attributes
    d.date_actual AS session_date,
    d.year_actual,
    d.quarter_name,
    d.month_name,
    d.day_name,
    d.is_weekend,
    -- Channel attributes
    c.channel_name,
    c.channel_category,
    c.channel_group,
    c.is_paid,
    -- Landing page attributes
    lp.landing_page_path,
    lp.page_category,
    lp.page_type,
    lp.is_conversion_page,
    lp.is_high_intent
FROM marketing_mart.fct_web_sessions f
LEFT JOIN common.dim_date d ON f.session_date_key = d.date_key
LEFT JOIN common.dim_channel c ON f.channel_key = c.channel_key
LEFT JOIN common.dim_landing_page lp ON f.landing_page_key = lp.landing_page_key;

-- View: Channel performance summary for Marketing
CREATE OR REPLACE VIEW marketing_mart.v_channel_performance AS
SELECT
    c.channel_name,
    c.channel_category,
    c.channel_group,
    c.is_paid,
    -- Ad metrics
    SUM(f.spend_usd) AS total_spend,
    SUM(f.impressions) AS total_impressions,
    SUM(f.clicks) AS total_clicks,
    -- Web metrics
    SUM(f.sessions) AS total_sessions,
    SUM(f.conversions) AS total_conversions,
    -- Sales metrics
    SUM(f.opportunities) AS total_opportunities,
    SUM(f.closed_won_opps) AS total_closed_won,
    SUM(f.closed_won_revenue) AS total_revenue,
    -- Calculated efficiency metrics
    CASE WHEN SUM(f.impressions) > 0 THEN ROUND(SUM(f.clicks)::DECIMAL / SUM(f.impressions), 6) END AS overall_ctr,
    CASE WHEN SUM(f.clicks) > 0 THEN ROUND(SUM(f.spend_usd) / SUM(f.clicks), 2) END AS overall_cpc,
    CASE WHEN SUM(f.impressions) > 0 THEN ROUND(SUM(f.spend_usd) / SUM(f.impressions) * 1000, 2) END AS overall_cpm,
    CASE WHEN SUM(f.conversions) > 0 THEN ROUND(SUM(f.spend_usd) / SUM(f.conversions), 2) END AS cost_per_conversion,
    CASE WHEN SUM(f.closed_won_opps) > 0 THEN ROUND(SUM(f.spend_usd) / SUM(f.closed_won_opps), 2) END AS overall_cac,
    CASE WHEN SUM(f.spend_usd) > 0 THEN ROUND(SUM(f.closed_won_revenue) / SUM(f.spend_usd), 2) END AS overall_roas,
    CASE WHEN SUM(f.spend_usd) > 0 THEN ROUND((SUM(f.closed_won_revenue) - SUM(f.spend_usd)) / SUM(f.spend_usd) * 100, 2) END AS roi_percentage
FROM marketing_mart.fct_marketing_funnel f
JOIN common.dim_channel c ON f.channel_key = c.channel_key
GROUP BY c.channel_name, c.channel_category, c.channel_group, c.is_paid
ORDER BY total_revenue DESC;

-- View: Weekly funnel trends
CREATE OR REPLACE VIEW marketing_mart.v_weekly_funnel_trends AS
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
    SUM(f.closed_won_revenue) AS weekly_revenue,
    -- Week-over-week calculations would need LAG function
    CASE WHEN SUM(f.spend_usd) > 0 THEN ROUND(SUM(f.closed_won_revenue) / SUM(f.spend_usd), 2) END AS weekly_roas
FROM marketing_mart.fct_marketing_funnel f
JOIN common.dim_date d ON f.date_key = d.date_key
JOIN common.dim_channel c ON f.channel_key = c.channel_key
GROUP BY d.year_actual, d.week_of_year, c.channel_name
ORDER BY d.year_actual, d.week_of_year, c.channel_name;

-- View: Landing page performance
CREATE OR REPLACE VIEW marketing_mart.v_landing_page_performance AS
SELECT
    lp.landing_page_path,
    lp.page_name,
    lp.page_category,
    lp.page_type,
    lp.is_conversion_page,
    lp.is_high_intent,
    COUNT(*) AS total_sessions,
    COUNT(DISTINCT f.user_id) AS unique_users,
    SUM(f.pageviews) AS total_pageviews,
    SUM(f.conversions) AS total_conversions,
    SUM(CASE WHEN f.is_converted THEN 1 ELSE 0 END) AS converted_sessions,
    ROUND(AVG(f.pageviews), 2) AS avg_pageviews_per_session,
    ROUND(SUM(CASE WHEN f.is_converted THEN 1 ELSE 0 END)::DECIMAL / COUNT(*) * 100, 2) AS conversion_rate_pct
FROM marketing_mart.fct_web_sessions f
JOIN common.dim_landing_page lp ON f.landing_page_key = lp.landing_page_key
GROUP BY lp.landing_page_path, lp.page_name, lp.page_category, lp.page_type, lp.is_conversion_page, lp.is_high_intent
ORDER BY total_sessions DESC;

-- View: Campaign comparison
CREATE OR REPLACE VIEW marketing_mart.v_campaign_comparison AS
SELECT
    cp.campaign_id,
    cp.campaign_name,
    cp.campaign_type,
    c.channel_name,
    c.channel_category,
    f.total_spend_usd,
    f.total_impressions,
    f.total_clicks,
    f.total_sessions,
    f.total_conversions,
    f.avg_ctr,
    f.avg_cpc,
    f.cost_per_conversion,
    f.conversion_rate,
    f.days_active,
    f.is_active
FROM marketing_mart.fct_campaign_performance f
JOIN common.dim_campaign cp ON f.campaign_key = cp.campaign_key
JOIN common.dim_channel c ON f.channel_key = c.channel_key
ORDER BY f.total_spend_usd DESC;

-- View: Full funnel visualization data
CREATE OR REPLACE VIEW marketing_mart.v_funnel_visualization AS
SELECT
    c.channel_name,
    'Impressions' AS funnel_stage,
    1 AS stage_order,
    SUM(f.impressions) AS stage_value
FROM marketing_mart.fct_marketing_funnel f
JOIN common.dim_channel c ON f.channel_key = c.channel_key
GROUP BY c.channel_name

UNION ALL

SELECT
    c.channel_name,
    'Clicks' AS funnel_stage,
    2 AS stage_order,
    SUM(f.clicks) AS stage_value
FROM marketing_mart.fct_marketing_funnel f
JOIN common.dim_channel c ON f.channel_key = c.channel_key
GROUP BY c.channel_name

UNION ALL

SELECT
    c.channel_name,
    'Sessions' AS funnel_stage,
    3 AS stage_order,
    SUM(f.sessions) AS stage_value
FROM marketing_mart.fct_marketing_funnel f
JOIN common.dim_channel c ON f.channel_key = c.channel_key
GROUP BY c.channel_name

UNION ALL

SELECT
    c.channel_name,
    'Conversions' AS funnel_stage,
    4 AS stage_order,
    SUM(f.conversions) AS stage_value
FROM marketing_mart.fct_marketing_funnel f
JOIN common.dim_channel c ON f.channel_key = c.channel_key
GROUP BY c.channel_name

UNION ALL

SELECT
    c.channel_name,
    'Opportunities' AS funnel_stage,
    5 AS stage_order,
    SUM(f.opportunities) AS stage_value
FROM marketing_mart.fct_marketing_funnel f
JOIN common.dim_channel c ON f.channel_key = c.channel_key
GROUP BY c.channel_name

UNION ALL

SELECT
    c.channel_name,
    'Closed Won' AS funnel_stage,
    6 AS stage_order,
    SUM(f.closed_won_opps) AS stage_value
FROM marketing_mart.fct_marketing_funnel f
JOIN common.dim_channel c ON f.channel_key = c.channel_key
GROUP BY c.channel_name

ORDER BY channel_name, stage_order;

-- ============================================
-- TABLE COMMENTS
-- ============================================

COMMENT ON TABLE marketing_mart.fct_ad_performance IS 'Transaction fact table for daily campaign-level ad performance metrics';
COMMENT ON TABLE marketing_mart.fct_web_sessions IS 'Transaction fact table for session-level web analytics';
COMMENT ON TABLE marketing_mart.fct_marketing_funnel IS 'Aggregated fact table for daily channel-level funnel metrics';
COMMENT ON TABLE marketing_mart.fct_channel_roi IS 'Periodic snapshot of channel ROI and efficiency metrics';
COMMENT ON TABLE marketing_mart.fct_campaign_performance IS 'Aggregated campaign performance summary';
