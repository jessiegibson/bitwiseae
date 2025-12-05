-- ============================================
-- SALES MART DDL
-- Fact tables for Sales/Revenue Analytics
-- References common dimension tables
-- ============================================

-- Create schema
CREATE SCHEMA IF NOT EXISTS sales_mart;

-- ============================================
-- FACT: fct_opportunities
-- Grain: One row per opportunity
-- All opportunities regardless of stage
-- ============================================

CREATE OR REPLACE TABLE sales_mart.fct_opportunities (
    -- Surrogate key
    opportunity_sk          INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Natural key
    opportunity_id          VARCHAR(50) NOT NULL UNIQUE,
    account_id              VARCHAR(50),

    -- Dimension Foreign Keys (referencing common schema)
    created_date_key        INTEGER NOT NULL,         -- FK to common.dim_date
    channel_key             INTEGER,                  -- FK to common.dim_channel
    stage_key               INTEGER NOT NULL,         -- FK to common.dim_deal_stage
    region_key              INTEGER,                  -- FK to common.dim_region

    -- Degenerate dimensions (attributes at grain level)
    source_original         VARCHAR(50),              -- Original source value from CRM

    -- Measures
    amount_usd              DECIMAL(14, 2) NOT NULL DEFAULT 0,

    -- Derived flags (for easier filtering)
    is_closed               BOOLEAN NOT NULL DEFAULT FALSE,
    is_won                  BOOLEAN NOT NULL DEFAULT FALSE,

    -- Audit fields
    _loaded_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _updated_at             TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Foreign key constraints
    FOREIGN KEY (created_date_key) REFERENCES common.dim_date(date_key),
    FOREIGN KEY (channel_key) REFERENCES common.dim_channel(channel_key),
    FOREIGN KEY (stage_key) REFERENCES common.dim_deal_stage(stage_key),
    FOREIGN KEY (region_key) REFERENCES common.dim_region(region_key)
);

-- ============================================
-- FACT: fct_closed_deals
-- Grain: One row per closed-won opportunity
-- Subset of opportunities for revenue analysis
-- ============================================

CREATE OR REPLACE TABLE sales_mart.fct_closed_deals (
    -- Surrogate key
    closed_deal_sk          INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Natural key
    opportunity_id          VARCHAR(50) NOT NULL UNIQUE,
    account_id              VARCHAR(50),

    -- Dimension Foreign Keys (referencing common schema)
    closed_date_key         INTEGER NOT NULL,         -- FK to common.dim_date
    channel_key             INTEGER,                  -- FK to common.dim_channel
    region_key              INTEGER,                  -- FK to common.dim_region

    -- Measures
    deal_amount_usd         DECIMAL(14, 2) NOT NULL DEFAULT 0,

    -- Audit fields
    _loaded_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Foreign key constraints
    FOREIGN KEY (closed_date_key) REFERENCES common.dim_date(date_key),
    FOREIGN KEY (channel_key) REFERENCES common.dim_channel(channel_key),
    FOREIGN KEY (region_key) REFERENCES common.dim_region(region_key)
);

-- ============================================
-- FACT: fct_pipeline_snapshot
-- Grain: One row per opportunity per snapshot date
-- For tracking pipeline changes over time
-- ============================================

CREATE OR REPLACE TABLE sales_mart.fct_pipeline_snapshot (
    -- Surrogate key
    snapshot_sk             INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Snapshot date
    snapshot_date_key       INTEGER NOT NULL,         -- FK to common.dim_date

    -- Opportunity reference
    opportunity_id          VARCHAR(50) NOT NULL,

    -- Dimension Foreign Keys
    channel_key             INTEGER,                  -- FK to common.dim_channel
    stage_key               INTEGER NOT NULL,         -- FK to common.dim_deal_stage
    region_key              INTEGER,                  -- FK to common.dim_region

    -- Measures at snapshot time
    amount_usd              DECIMAL(14, 2) NOT NULL DEFAULT 0,
    days_in_stage           INTEGER,
    days_since_created      INTEGER,

    -- Audit fields
    _loaded_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Foreign key constraints
    FOREIGN KEY (snapshot_date_key) REFERENCES common.dim_date(date_key),
    FOREIGN KEY (channel_key) REFERENCES common.dim_channel(channel_key),
    FOREIGN KEY (stage_key) REFERENCES common.dim_deal_stage(stage_key),
    FOREIGN KEY (region_key) REFERENCES common.dim_region(region_key)
);

-- ============================================
-- AGGREGATE FACT: fct_sales_summary
-- Grain: One row per date + channel + region
-- Pre-aggregated for dashboard performance
-- ============================================

CREATE OR REPLACE TABLE sales_mart.fct_sales_summary (
    -- Surrogate key
    sales_summary_sk        INTEGER PRIMARY KEY AUTOINCREMENT,

    -- Dimension Foreign Keys
    date_key                INTEGER NOT NULL,         -- FK to common.dim_date
    channel_key             INTEGER,                  -- FK to common.dim_channel
    region_key              INTEGER,                  -- FK to common.dim_region

    -- Opportunity counts by stage
    total_opportunities     INTEGER DEFAULT 0,
    pipeline_opportunities  INTEGER DEFAULT 0,
    proposal_opportunities  INTEGER DEFAULT 0,
    closed_won_count        INTEGER DEFAULT 0,
    closed_lost_count       INTEGER DEFAULT 0,

    -- Revenue measures
    total_pipeline_value    DECIMAL(14, 2) DEFAULT 0,
    closed_won_revenue      DECIMAL(14, 2) DEFAULT 0,
    closed_lost_value       DECIMAL(14, 2) DEFAULT 0,

    -- Calculated metrics
    win_rate                DECIMAL(10, 4),           -- closed_won / (closed_won + closed_lost)
    avg_deal_size           DECIMAL(14, 2),           -- closed_won_revenue / closed_won_count

    -- Audit fields
    _loaded_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    -- Foreign key constraints
    FOREIGN KEY (date_key) REFERENCES common.dim_date(date_key),
    FOREIGN KEY (channel_key) REFERENCES common.dim_channel(channel_key),
    FOREIGN KEY (region_key) REFERENCES common.dim_region(region_key)
);

-- ============================================
-- INDEXES FOR QUERY PERFORMANCE
-- ============================================

-- fct_opportunities indexes
CREATE INDEX IF NOT EXISTS idx_fct_opp_created_date ON sales_mart.fct_opportunities(created_date_key);
CREATE INDEX IF NOT EXISTS idx_fct_opp_channel ON sales_mart.fct_opportunities(channel_key);
CREATE INDEX IF NOT EXISTS idx_fct_opp_stage ON sales_mart.fct_opportunities(stage_key);
CREATE INDEX IF NOT EXISTS idx_fct_opp_region ON sales_mart.fct_opportunities(region_key);
CREATE INDEX IF NOT EXISTS idx_fct_opp_is_won ON sales_mart.fct_opportunities(is_won);

-- fct_closed_deals indexes
CREATE INDEX IF NOT EXISTS idx_fct_closed_date ON sales_mart.fct_closed_deals(closed_date_key);
CREATE INDEX IF NOT EXISTS idx_fct_closed_channel ON sales_mart.fct_closed_deals(channel_key);
CREATE INDEX IF NOT EXISTS idx_fct_closed_region ON sales_mart.fct_closed_deals(region_key);

-- fct_sales_summary indexes
CREATE INDEX IF NOT EXISTS idx_fct_sales_sum_date ON sales_mart.fct_sales_summary(date_key);
CREATE INDEX IF NOT EXISTS idx_fct_sales_sum_channel ON sales_mart.fct_sales_summary(channel_key);

-- ============================================
-- VIEWS FOR COMMON ANALYSES
-- ============================================

-- View: Opportunities with dimension attributes (star schema flattened)
CREATE OR REPLACE VIEW sales_mart.v_opportunities_detail AS
SELECT
    f.opportunity_id,
    f.account_id,
    f.amount_usd,
    f.is_closed,
    f.is_won,
    -- Date attributes
    d.date_actual AS created_date,
    d.year_actual AS created_year,
    d.quarter_name AS created_quarter,
    d.month_name AS created_month,
    d.week_of_year AS created_week,
    -- Channel attributes
    c.channel_name,
    c.channel_category,
    c.channel_group,
    c.is_paid AS is_paid_channel,
    -- Stage attributes
    s.stage_name,
    s.stage_category,
    s.is_active_pipeline,
    s.probability_default,
    -- Region attributes
    r.region_name,
    r.region_code,
    r.super_region
FROM sales_mart.fct_opportunities f
LEFT JOIN common.dim_date d ON f.created_date_key = d.date_key
LEFT JOIN common.dim_channel c ON f.channel_key = c.channel_key
LEFT JOIN common.dim_deal_stage s ON f.stage_key = s.stage_key
LEFT JOIN common.dim_region r ON f.region_key = r.region_key;

-- View: Channel performance summary for Sales
CREATE OR REPLACE VIEW sales_mart.v_channel_performance AS
SELECT
    c.channel_name,
    c.channel_category,
    c.is_paid,
    COUNT(*) AS total_opportunities,
    SUM(CASE WHEN f.is_won THEN 1 ELSE 0 END) AS closed_won_count,
    SUM(CASE WHEN f.is_closed AND NOT f.is_won THEN 1 ELSE 0 END) AS closed_lost_count,
    SUM(CASE WHEN NOT f.is_closed THEN 1 ELSE 0 END) AS open_pipeline_count,
    SUM(CASE WHEN f.is_won THEN f.amount_usd ELSE 0 END) AS total_revenue,
    SUM(CASE WHEN NOT f.is_closed THEN f.amount_usd ELSE 0 END) AS pipeline_value,
    AVG(CASE WHEN f.is_won THEN f.amount_usd END) AS avg_won_deal_size,
    -- Win rate calculation
    CASE
        WHEN SUM(CASE WHEN f.is_closed THEN 1 ELSE 0 END) > 0
        THEN ROUND(SUM(CASE WHEN f.is_won THEN 1 ELSE 0 END)::DECIMAL /
             SUM(CASE WHEN f.is_closed THEN 1 ELSE 0 END) * 100, 2)
        ELSE NULL
    END AS win_rate_pct
FROM sales_mart.fct_opportunities f
LEFT JOIN common.dim_channel c ON f.channel_key = c.channel_key
GROUP BY c.channel_name, c.channel_category, c.is_paid
ORDER BY total_revenue DESC;

-- View: Regional performance summary
CREATE OR REPLACE VIEW sales_mart.v_regional_performance AS
SELECT
    r.region_name,
    r.super_region,
    COUNT(*) AS total_opportunities,
    SUM(CASE WHEN f.is_won THEN 1 ELSE 0 END) AS closed_won_count,
    SUM(CASE WHEN f.is_won THEN f.amount_usd ELSE 0 END) AS total_revenue,
    SUM(CASE WHEN NOT f.is_closed THEN f.amount_usd ELSE 0 END) AS pipeline_value,
    AVG(CASE WHEN f.is_won THEN f.amount_usd END) AS avg_deal_size,
    ROUND(SUM(CASE WHEN f.is_won THEN 1 ELSE 0 END)::DECIMAL /
          NULLIF(SUM(CASE WHEN f.is_closed THEN 1 ELSE 0 END), 0) * 100, 2) AS win_rate_pct
FROM sales_mart.fct_opportunities f
LEFT JOIN common.dim_region r ON f.region_key = r.region_key
GROUP BY r.region_name, r.super_region
ORDER BY total_revenue DESC;

-- View: Monthly revenue trends
CREATE OR REPLACE VIEW sales_mart.v_monthly_revenue_trend AS
SELECT
    d.year_actual,
    d.month_actual,
    d.month_name,
    d.year_month,
    c.channel_name,
    COUNT(*) AS opportunities_created,
    SUM(CASE WHEN f.is_won THEN 1 ELSE 0 END) AS deals_closed,
    SUM(CASE WHEN f.is_won THEN f.amount_usd ELSE 0 END) AS revenue
FROM sales_mart.fct_opportunities f
LEFT JOIN common.dim_date d ON f.created_date_key = d.date_key
LEFT JOIN common.dim_channel c ON f.channel_key = c.channel_key
GROUP BY d.year_actual, d.month_actual, d.month_name, d.year_month, c.channel_name
ORDER BY d.year_actual, d.month_actual, c.channel_name;

-- ============================================
-- TABLE COMMENTS
-- ============================================

COMMENT ON TABLE sales_mart.fct_opportunities IS 'Transaction fact table containing all opportunities at their current state';
COMMENT ON TABLE sales_mart.fct_closed_deals IS 'Subset of opportunities that are closed-won, optimized for revenue analysis';
COMMENT ON TABLE sales_mart.fct_pipeline_snapshot IS 'Periodic snapshot of pipeline for trend analysis';
COMMENT ON TABLE sales_mart.fct_sales_summary IS 'Pre-aggregated daily summary by channel and region';
