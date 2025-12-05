-- ============================================
-- STAGING SCHEMA DDL
-- Cleaned and standardized data from raw sources
-- ============================================

-- Create schema
CREATE SCHEMA IF NOT EXISTS staging;

-- ============================================
-- STAGING TABLES
-- Light transformations: type casting, null handling,
-- standardization of values, deduplication
-- ============================================

-- Staging Table: stg_ad_spend
-- Source: raw_data.ad_spend
-- Transformations: standardize channel names, clean UTM values
CREATE OR REPLACE TABLE staging.stg_ad_spend (
    date                DATE NOT NULL,
    campaign_id         VARCHAR(100) NOT NULL,
    channel             VARCHAR(50) NOT NULL,
    channel_normalized  VARCHAR(50) NOT NULL,       -- Standardized channel name
    utm_source          VARCHAR(50),
    utm_source_lower    VARCHAR(50),                -- Lowercase for consistent joining
    utm_campaign        VARCHAR(100),
    utm_campaign_lower  VARCHAR(100),               -- Lowercase for consistent joining
    spend_usd           DECIMAL(12, 2) NOT NULL DEFAULT 0,
    clicks              INTEGER NOT NULL DEFAULT 0,
    impressions         INTEGER NOT NULL DEFAULT 0,
    -- Derived fields
    ctr                 DECIMAL(10, 6),             -- Click-through rate
    cpc                 DECIMAL(10, 4),             -- Cost per click
    cpm                 DECIMAL(10, 4),             -- Cost per mille (thousand impressions)
    -- Metadata
    _loaded_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Staging Table: stg_web_analytics
-- Source: raw_data.web_analytics
-- Transformations: standardize UTM values, derive channel from utm_source
CREATE OR REPLACE TABLE staging.stg_web_analytics (
    session_id          VARCHAR(50) NOT NULL,
    user_id             VARCHAR(50),
    session_date        DATE NOT NULL,
    landing_page        VARCHAR(255),
    landing_page_path   VARCHAR(255),               -- Cleaned path only
    utm_source          VARCHAR(50),
    utm_source_lower    VARCHAR(50),                -- Lowercase for consistent joining
    utm_campaign        VARCHAR(100),
    utm_campaign_lower  VARCHAR(100),               -- Lowercase for consistent joining
    channel_derived     VARCHAR(50),                -- Channel derived from utm_source
    pageviews           INTEGER NOT NULL DEFAULT 0,
    conversions         INTEGER NOT NULL DEFAULT 0,
    -- Derived flags
    is_converted        BOOLEAN,                    -- TRUE if conversions > 0
    is_attributed       BOOLEAN,                    -- TRUE if UTM params present
    -- Metadata
    _loaded_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- Staging Table: stg_salesforce_opportunities
-- Source: raw_data.salesforce_opportunities
-- Transformations: standardize source/channel, categorize stages
CREATE OR REPLACE TABLE staging.stg_salesforce_opportunities (
    opportunity_id      VARCHAR(50) NOT NULL,
    account_id          VARCHAR(50),
    created_date        DATE NOT NULL,
    stage               VARCHAR(50) NOT NULL,
    stage_category      VARCHAR(20),                -- 'Open' or 'Closed'
    is_closed           BOOLEAN,
    is_won              BOOLEAN,
    amount_usd          DECIMAL(12, 2) NOT NULL DEFAULT 0,
    source              VARCHAR(50),
    source_normalized   VARCHAR(50),                -- Standardized to match channel names
    owner_region        VARCHAR(50),
    owner_region_normalized VARCHAR(50),            -- Standardized region name
    -- Metadata
    _loaded_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================
-- CHANNEL MAPPING REFERENCE TABLE
-- Central mapping for utm_source -> channel
-- ============================================

CREATE OR REPLACE TABLE staging.ref_channel_mapping (
    utm_source          VARCHAR(50) PRIMARY KEY,
    channel_name        VARCHAR(50) NOT NULL,
    channel_category    VARCHAR(50) NOT NULL,
    is_paid             BOOLEAN NOT NULL
);

-- Populate channel mapping reference
INSERT INTO staging.ref_channel_mapping (utm_source, channel_name, channel_category, is_paid)
VALUES
    ('google', 'Google Ads', 'Paid Search', TRUE),
    ('facebook', 'Meta', 'Paid Social', TRUE),
    ('linkedin', 'LinkedIn', 'Paid Social', TRUE),
    ('twitter', 'Twitter', 'Paid Social', TRUE),
    ('bing', 'Bing Ads', 'Paid Search', TRUE),
    ('organic', 'Organic', 'Organic', FALSE),
    ('direct', 'Direct', 'Direct', FALSE),
    (NULL, 'Direct', 'Direct', FALSE);

-- ============================================
-- REGION MAPPING REFERENCE TABLE
-- Standardize region names
-- ============================================

CREATE OR REPLACE TABLE staging.ref_region_mapping (
    region_raw          VARCHAR(50) PRIMARY KEY,
    region_normalized   VARCHAR(50) NOT NULL,
    region_code         VARCHAR(10) NOT NULL
);

INSERT INTO staging.ref_region_mapping (region_raw, region_normalized, region_code)
VALUES
    ('North America', 'North America', 'NA'),
    ('NA', 'North America', 'NA'),
    ('US', 'North America', 'NA'),
    ('Europe', 'Europe', 'EU'),
    ('EU', 'Europe', 'EU'),
    ('EMEA', 'Europe', 'EU'),
    ('APAC', 'APAC', 'APAC'),
    ('Asia Pacific', 'APAC', 'APAC'),
    ('Asia', 'APAC', 'APAC');

-- ============================================
-- STAGING POPULATION SCRIPTS
-- Transform raw data into staging tables
-- ============================================

-- Populate stg_ad_spend
INSERT INTO staging.stg_ad_spend
SELECT
    r.date,
    r.campaign_id,
    r.channel,
    -- Normalize channel name (trim, proper case)
    TRIM(r.channel) AS channel_normalized,
    r.utm_source,
    LOWER(TRIM(r.utm_source)) AS utm_source_lower,
    r.utm_campaign,
    LOWER(TRIM(r.utm_campaign)) AS utm_campaign_lower,
    COALESCE(r.spend_usd, 0) AS spend_usd,
    COALESCE(r.clicks, 0) AS clicks,
    COALESCE(r.impressions, 0) AS impressions,
    -- Calculate CTR
    CASE
        WHEN COALESCE(r.impressions, 0) > 0
        THEN ROUND((COALESCE(r.clicks, 0)::DECIMAL / r.impressions), 6)
        ELSE 0
    END AS ctr,
    -- Calculate CPC
    CASE
        WHEN COALESCE(r.clicks, 0) > 0
        THEN ROUND(COALESCE(r.spend_usd, 0) / r.clicks, 4)
        ELSE 0
    END AS cpc,
    -- Calculate CPM
    CASE
        WHEN COALESCE(r.impressions, 0) > 0
        THEN ROUND((COALESCE(r.spend_usd, 0) / r.impressions) * 1000, 4)
        ELSE 0
    END AS cpm,
    CURRENT_TIMESTAMP() AS _loaded_at
FROM raw_data.ad_spend r;

-- Populate stg_web_analytics
INSERT INTO staging.stg_web_analytics
SELECT
    r.session_id,
    r.user_id,
    r.session_date,
    r.landing_page,
    -- Extract clean path (remove query params if any)
    SPLIT_PART(r.landing_page, '?', 1) AS landing_page_path,
    r.utm_source,
    LOWER(TRIM(r.utm_source)) AS utm_source_lower,
    r.utm_campaign,
    LOWER(TRIM(r.utm_campaign)) AS utm_campaign_lower,
    -- Derive channel from utm_source
    CASE
        WHEN LOWER(TRIM(r.utm_source)) = 'google' THEN 'Google Ads'
        WHEN LOWER(TRIM(r.utm_source)) = 'facebook' THEN 'Meta'
        WHEN LOWER(TRIM(r.utm_source)) = 'linkedin' THEN 'LinkedIn'
        WHEN LOWER(TRIM(r.utm_source)) = 'twitter' THEN 'Twitter'
        WHEN r.utm_source IS NULL THEN 'Direct'
        ELSE 'Other'
    END AS channel_derived,
    COALESCE(r.pageviews, 0) AS pageviews,
    COALESCE(r.conversions, 0) AS conversions,
    -- Derived flags
    CASE WHEN COALESCE(r.conversions, 0) > 0 THEN TRUE ELSE FALSE END AS is_converted,
    CASE WHEN r.utm_source IS NOT NULL THEN TRUE ELSE FALSE END AS is_attributed,
    CURRENT_TIMESTAMP() AS _loaded_at
FROM raw_data.web_analytics r;

-- Populate stg_salesforce_opportunities
INSERT INTO staging.stg_salesforce_opportunities
SELECT
    r.opportunity_id,
    r.account_id,
    r.created_date,
    r.stage,
    -- Categorize stage
    CASE
        WHEN r.stage IN ('Closed Won', 'Closed Lost') THEN 'Closed'
        ELSE 'Open'
    END AS stage_category,
    CASE
        WHEN r.stage IN ('Closed Won', 'Closed Lost') THEN TRUE
        ELSE FALSE
    END AS is_closed,
    CASE
        WHEN r.stage = 'Closed Won' THEN TRUE
        ELSE FALSE
    END AS is_won,
    COALESCE(r.amount_usd, 0) AS amount_usd,
    r.source,
    -- Normalize source to match channel naming
    TRIM(r.source) AS source_normalized,
    r.owner_region,
    -- Normalize region
    COALESCE(rm.region_normalized, TRIM(r.owner_region)) AS owner_region_normalized,
    CURRENT_TIMESTAMP() AS _loaded_at
FROM raw_data.salesforce_opportunities r
LEFT JOIN staging.ref_region_mapping rm
    ON TRIM(r.owner_region) = rm.region_raw;

-- ============================================
-- STAGING VIEWS FOR VALIDATION
-- ============================================

-- View: Data quality check for ad_spend
CREATE OR REPLACE VIEW staging.v_stg_ad_spend_quality AS
SELECT
    'ad_spend' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT campaign_id) AS distinct_campaigns,
    COUNT(DISTINCT channel_normalized) AS distinct_channels,
    SUM(CASE WHEN utm_source IS NULL THEN 1 ELSE 0 END) AS null_utm_source,
    SUM(CASE WHEN spend_usd = 0 THEN 1 ELSE 0 END) AS zero_spend_rows,
    MIN(date) AS min_date,
    MAX(date) AS max_date
FROM staging.stg_ad_spend;

-- View: Data quality check for web_analytics
CREATE OR REPLACE VIEW staging.v_stg_web_analytics_quality AS
SELECT
    'web_analytics' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT session_id) AS distinct_sessions,
    COUNT(DISTINCT user_id) AS distinct_users,
    SUM(CASE WHEN utm_source IS NULL THEN 1 ELSE 0 END) AS unattributed_sessions,
    SUM(CASE WHEN is_converted THEN 1 ELSE 0 END) AS converted_sessions,
    MIN(session_date) AS min_date,
    MAX(session_date) AS max_date
FROM staging.stg_web_analytics;

-- View: Data quality check for salesforce_opportunities
CREATE OR REPLACE VIEW staging.v_stg_opportunities_quality AS
SELECT
    'salesforce_opportunities' AS table_name,
    COUNT(*) AS total_rows,
    COUNT(DISTINCT opportunity_id) AS distinct_opportunities,
    COUNT(DISTINCT account_id) AS distinct_accounts,
    SUM(CASE WHEN is_won THEN 1 ELSE 0 END) AS closed_won_count,
    SUM(CASE WHEN is_won THEN amount_usd ELSE 0 END) AS closed_won_revenue,
    MIN(created_date) AS min_date,
    MAX(created_date) AS max_date
FROM staging.stg_salesforce_opportunities;
