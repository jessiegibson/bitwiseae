-- ============================================
-- SALES MART DDL
-- Data Mart for GTM Funnel Analytics
-- ============================================

-- Create schema (if not exists)
CREATE SCHEMA IF NOT EXISTS sales_mart;

-- ============================================
-- RAW/STAGING TABLES
-- ============================================

-- Table: ad_spend (raw)
CREATE OR REPLACE TABLE sales_mart.stg_ad_spend (
    date            DATE,
    campaign_id     VARCHAR(100),
    channel         VARCHAR(50),
    utm_source      VARCHAR(50),
    utm_campaign    VARCHAR(100),
    spend_usd       DECIMAL(12, 2),
    clicks          INTEGER,
    impressions     INTEGER
);

-- Table: salesforce_opportunities (raw)
CREATE OR REPLACE TABLE sales_mart.stg_salesforce_opportunities (
    opportunity_id  VARCHAR(50),
    account_id      VARCHAR(50),
    created_date    DATE,
    stage           VARCHAR(50),
    amount_usd      DECIMAL(12, 2),
    source          VARCHAR(50),
    owner_region    VARCHAR(50)
);

-- Table: web_analytics (raw)
CREATE OR REPLACE TABLE sales_mart.stg_web_analytics (
    session_id      VARCHAR(50),
    user_id         VARCHAR(50),
    session_date    DATE,
    landing_page    VARCHAR(255),
    utm_source      VARCHAR(50),
    utm_campaign    VARCHAR(100),
    pageviews       INTEGER,
    conversions     INTEGER
);

-- ============================================
-- DIMENSION TABLES
-- ============================================

-- Dimension: dim_date
CREATE OR REPLACE TABLE sales_mart.dim_date (
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
CREATE OR REPLACE TABLE sales_mart.dim_channel (
    channel_key         INTEGER PRIMARY KEY AUTOINCREMENT,
    channel_name        VARCHAR(50) NOT NULL,     -- e.g., 'Google Ads', 'LinkedIn', 'Meta'
    channel_category    VARCHAR(50),              -- e.g., 'Paid Search', 'Paid Social', 'Organic', 'Direct'
    utm_source          VARCHAR(50),              -- e.g., 'google', 'linkedin', 'facebook'
    is_paid             BOOLEAN
);

-- Dimension: dim_campaign
CREATE OR REPLACE TABLE sales_mart.dim_campaign (
    campaign_key        INTEGER PRIMARY KEY AUTOINCREMENT,
    campaign_id         VARCHAR(100) NOT NULL,    -- Natural key from ad_spend
    utm_campaign        VARCHAR(100),
    channel_key         INTEGER,                  -- FK to dim_channel
    campaign_name       VARCHAR(255),             -- Derived/friendly name
    FOREIGN KEY (channel_key) REFERENCES sales_mart.dim_channel(channel_key)
);

-- Dimension: dim_deal_stage
CREATE OR REPLACE TABLE sales_mart.dim_deal_stage (
    stage_key           INTEGER PRIMARY KEY AUTOINCREMENT,
    stage_name          VARCHAR(50) NOT NULL,     -- 'Pipeline', 'Proposal', 'Closed Won', 'Closed Lost'
    stage_category      VARCHAR(50),              -- 'Open', 'Closed'
    is_closed           BOOLEAN,
    is_won              BOOLEAN,
    stage_order         INTEGER                   -- For sorting in reports
);

-- Dimension: dim_sales_region
-- Note: Source data only has region, not individual sales rep details
CREATE OR REPLACE TABLE sales_mart.dim_sales_region (
    region_key          INTEGER PRIMARY KEY AUTOINCREMENT,
    region_name         VARCHAR(50) NOT NULL,     -- 'North America', 'Europe', 'APAC'
    region_code         VARCHAR(10)
);

-- ============================================
-- FACT TABLES
-- ============================================

-- Fact: fct_opportunities
-- Grain: One row per opportunity
CREATE OR REPLACE TABLE sales_mart.fct_opportunities (
    opportunity_key     INTEGER PRIMARY KEY AUTOINCREMENT,
    opportunity_id      VARCHAR(50) NOT NULL,     -- Natural key from Salesforce
    account_id          VARCHAR(50),

    -- Dimension Foreign Keys
    created_date_key    INTEGER NOT NULL,         -- FK to dim_date
    channel_key         INTEGER,                  -- FK to dim_channel (derived from source)
    stage_key           INTEGER NOT NULL,         -- FK to dim_deal_stage
    region_key          INTEGER,                  -- FK to dim_sales_region

    -- Measures
    amount_usd          DECIMAL(12, 2),

    -- Audit
    loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    FOREIGN KEY (created_date_key) REFERENCES sales_mart.dim_date(date_key),
    FOREIGN KEY (channel_key) REFERENCES sales_mart.dim_channel(channel_key),
    FOREIGN KEY (stage_key) REFERENCES sales_mart.dim_deal_stage(stage_key),
    FOREIGN KEY (region_key) REFERENCES sales_mart.dim_sales_region(region_key)
);

-- Fact: fct_closed_deals
-- Grain: One row per closed-won opportunity
CREATE OR REPLACE TABLE sales_mart.fct_closed_deals (
    closed_deal_key     INTEGER PRIMARY KEY AUTOINCREMENT,
    opportunity_id      VARCHAR(50) NOT NULL,     -- Natural key from Salesforce
    account_id          VARCHAR(50),

    -- Dimension Foreign Keys
    closed_date_key     INTEGER NOT NULL,         -- FK to dim_date
    channel_key         INTEGER,                  -- FK to dim_channel
    region_key          INTEGER,                  -- FK to dim_sales_region

    -- Measures
    deal_amount_usd     DECIMAL(12, 2),

    -- Audit
    loaded_at           TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    FOREIGN KEY (closed_date_key) REFERENCES sales_mart.dim_date(date_key),
    FOREIGN KEY (channel_key) REFERENCES sales_mart.dim_channel(channel_key),
    FOREIGN KEY (region_key) REFERENCES sales_mart.dim_sales_region(region_key)
);
