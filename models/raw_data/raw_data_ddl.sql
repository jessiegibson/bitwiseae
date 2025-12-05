-- ============================================
-- RAW DATA SCHEMA DDL
-- Landing zone for source data files
-- ============================================

-- Create schema
CREATE SCHEMA IF NOT EXISTS raw_data;

-- ============================================
-- RAW SOURCE TABLES
-- These tables mirror the structure of source CSV files
-- No transformations applied - pure landing zone
-- ============================================

-- Raw Table: ad_spend
-- Source: data/ad_spend.csv
-- Grain: One row per date + campaign_id
CREATE OR REPLACE TABLE raw_data.ad_spend (
    date            DATE,
    campaign_id     VARCHAR(100),
    channel         VARCHAR(50),
    utm_source      VARCHAR(50),
    utm_campaign    VARCHAR(100),
    spend_usd       DECIMAL(12, 2),
    clicks          INTEGER,
    impressions     INTEGER,
    -- Metadata
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file    VARCHAR(255) DEFAULT 'ad_spend.csv'
);

-- Raw Table: web_analytics
-- Source: data/web_analytics.csv
-- Grain: One row per session_id
CREATE OR REPLACE TABLE raw_data.web_analytics (
    session_id      VARCHAR(50),
    user_id         VARCHAR(50),
    session_date    DATE,
    landing_page    VARCHAR(255),
    utm_source      VARCHAR(50),
    utm_campaign    VARCHAR(100),
    pageviews       INTEGER,
    conversions     INTEGER,
    -- Metadata
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file    VARCHAR(255) DEFAULT 'web_analytics.csv'
);

-- Raw Table: salesforce_opportunities
-- Source: data/salesforce_opportunities.csv
-- Grain: One row per opportunity_id
CREATE OR REPLACE TABLE raw_data.salesforce_opportunities (
    opportunity_id  VARCHAR(50),
    account_id      VARCHAR(50),
    created_date    DATE,
    stage           VARCHAR(50),
    amount_usd      DECIMAL(12, 2),
    source          VARCHAR(50),
    owner_region    VARCHAR(50),
    -- Metadata
    _loaded_at      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    _source_file    VARCHAR(255) DEFAULT 'salesforce_opportunities.csv'
);

-- ============================================
-- DATA LOADING SCRIPTS
-- Copy commands to load from CSV files
-- ============================================

-- Load ad_spend
-- COPY INTO raw_data.ad_spend (date, campaign_id, channel, utm_source, utm_campaign, spend_usd, clicks, impressions)
-- FROM @your_stage/ad_spend.csv
-- FILE_FORMAT = (TYPE = 'CSV' SKIP_HEADER = 1);

-- Load web_analytics
-- COPY INTO raw_data.web_analytics (session_id, user_id, session_date, landing_page, utm_source, utm_campaign, pageviews, conversions)
-- FROM @your_stage/web_analytics.csv
-- FILE_FORMAT = (TYPE = 'CSV' SKIP_HEADER = 1);

-- Load salesforce_opportunities
-- COPY INTO raw_data.salesforce_opportunities (opportunity_id, account_id, created_date, stage, amount_usd, source, owner_region)
-- FROM @your_stage/salesforce_opportunities.csv
-- FILE_FORMAT = (TYPE = 'CSV' SKIP_HEADER = 1);
