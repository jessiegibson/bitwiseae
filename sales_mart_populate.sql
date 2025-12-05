-- ============================================
-- SALES MART - DATA POPULATION SCRIPTS
-- ============================================
-- This file contains all INSERT/transformation logic
-- to populate the Sales Mart dimensional model
-- ============================================

-- ============================================
-- Populate dim_date (for date range in your data)
-- ============================================
INSERT INTO sales_mart.dim_date
SELECT
    TO_NUMBER(TO_CHAR(date_actual, 'YYYYMMDD')) AS date_key,
    date_actual,
    DAYOFWEEK(date_actual) AS day_of_week,
    DAYNAME(date_actual) AS day_name,
    DAY(date_actual) AS day_of_month,
    DAYOFYEAR(date_actual) AS day_of_year,
    WEEKOFYEAR(date_actual) AS week_of_year,
    MONTH(date_actual) AS month_actual,
    MONTHNAME(date_actual) AS month_name,
    QUARTER(date_actual) AS quarter_actual,
    'Q' || QUARTER(date_actual) AS quarter_name,
    YEAR(date_actual) AS year_actual,
    CASE WHEN DAYOFWEEK(date_actual) IN (0, 6) THEN TRUE ELSE FALSE END AS is_weekend
FROM (
    SELECT DATEADD(DAY, SEQ4(), '2025-01-01')::DATE AS date_actual
    FROM TABLE(GENERATOR(ROWCOUNT => 365))
);

-- ============================================
-- Populate dim_channel (dynamic from source data)
-- Derives distinct channels from both ad_spend and salesforce_opportunities
-- ============================================
INSERT INTO sales_mart.dim_channel (channel_name, channel_category, utm_source, is_paid)
WITH all_channels AS (
    -- From ad_spend (paid channels with utm_source mapping)
    SELECT DISTINCT
        channel AS channel_name,
        utm_source,
        TRUE AS is_paid
    FROM ad_spend

    UNION

    -- From salesforce opportunities (includes non-paid sources)
    SELECT DISTINCT
        source AS channel_name,
        NULL AS utm_source,
        FALSE AS is_paid
    FROM salesforce_opportunities
    WHERE source NOT IN (SELECT DISTINCT channel FROM ad_spend)
)
SELECT
    channel_name,
    CASE
        WHEN channel_name = 'Google Ads' THEN 'Paid Search'
        WHEN channel_name IN ('LinkedIn', 'Meta', 'Twitter') THEN 'Paid Social'
        WHEN channel_name = 'Organic' THEN 'Organic'
        WHEN channel_name = 'Direct' THEN 'Direct'
        ELSE 'Other'
    END AS channel_category,
    utm_source,
    is_paid
FROM all_channels;

-- ============================================
-- Populate dim_deal_stage
-- ============================================
INSERT INTO sales_mart.dim_deal_stage (stage_name, stage_category, is_closed, is_won, stage_order)
VALUES
    ('Pipeline', 'Open', FALSE, FALSE, 1),
    ('Proposal', 'Open', FALSE, FALSE, 2),
    ('Closed Won', 'Closed', TRUE, TRUE, 3),
    ('Closed Lost', 'Closed', TRUE, FALSE, 4);

-- ============================================
-- Populate dim_sales_region
-- ============================================
INSERT INTO sales_mart.dim_sales_region (region_name, region_code)
VALUES
    ('North America', 'NA'),
    ('Europe', 'EU'),
    ('APAC', 'APAC');

-- ============================================
-- Populate dim_campaign (from ad_spend)
-- ============================================
INSERT INTO sales_mart.dim_campaign (campaign_id, utm_campaign, channel_key, campaign_name)
SELECT DISTINCT
    a.campaign_id,
    a.utm_campaign,
    c.channel_key,
    REPLACE(REPLACE(a.campaign_id, 'CAMP_', ''), '_', ' ') AS campaign_name
FROM ad_spend a
LEFT JOIN sales_mart.dim_channel c ON a.channel = c.channel_name;

-- ============================================
-- Populate fct_opportunities
-- Grain: One row per opportunity (all opportunities)
-- ============================================
INSERT INTO sales_mart.fct_opportunities (
    opportunity_id,
    account_id,
    created_date_key,
    channel_key,
    stage_key,
    region_key,
    amount_usd
)
SELECT
    o.opportunity_id,
    o.account_id,
    TO_NUMBER(TO_CHAR(o.created_date, 'YYYYMMDD')) AS created_date_key,
    c.channel_key,
    s.stage_key,
    r.region_key,
    o.amount_usd
FROM salesforce_opportunities o
LEFT JOIN sales_mart.dim_channel c ON o.source = c.channel_name
LEFT JOIN sales_mart.dim_deal_stage s ON o.stage = s.stage_name
LEFT JOIN sales_mart.dim_sales_region r ON o.owner_region = r.region_name;

-- ============================================
-- Populate fct_closed_deals (Closed Won only)
-- Grain: One row per closed-won opportunity
-- ============================================
INSERT INTO sales_mart.fct_closed_deals (
    opportunity_id,
    account_id,
    closed_date_key,
    channel_key,
    region_key,
    deal_amount_usd
)
SELECT
    o.opportunity_id,
    o.account_id,
    TO_NUMBER(TO_CHAR(o.created_date, 'YYYYMMDD')) AS closed_date_key,
    c.channel_key,
    r.region_key,
    o.amount_usd
FROM salesforce_opportunities o
LEFT JOIN sales_mart.dim_channel c ON o.source = c.channel_name
LEFT JOIN sales_mart.dim_sales_region r ON o.owner_region = r.region_name
WHERE o.stage = 'Closed Won';
