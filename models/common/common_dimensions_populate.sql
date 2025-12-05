-- ============================================
-- COMMON DIMENSIONS - POPULATION SCRIPTS
-- Populate shared dimension tables from staging data
-- ============================================

-- ============================================
-- Populate dim_date
-- Generate a date dimension for the relevant date range
-- ============================================

INSERT INTO common.dim_date
SELECT
    TO_NUMBER(TO_CHAR(date_actual, 'YYYYMMDD')) AS date_key,
    date_actual,

    -- Day attributes
    DAYOFWEEK(date_actual) AS day_of_week,
    DAYOFWEEKISO(date_actual) AS day_of_week_iso,
    DAYNAME(date_actual) AS day_name,
    LEFT(DAYNAME(date_actual), 3) AS day_name_short,
    DAY(date_actual) AS day_of_month,
    DAYOFYEAR(date_actual) AS day_of_year,

    -- Week attributes
    WEEKOFYEAR(date_actual) AS week_of_year,
    WEEKISO(date_actual) AS week_of_year_iso,
    DATE_TRUNC('WEEK', date_actual)::DATE AS week_start_date,
    DATEADD(DAY, 6, DATE_TRUNC('WEEK', date_actual))::DATE AS week_end_date,

    -- Month attributes
    MONTH(date_actual) AS month_actual,
    MONTHNAME(date_actual) AS month_name,
    LEFT(MONTHNAME(date_actual), 3) AS month_name_short,
    DATE_TRUNC('MONTH', date_actual)::DATE AS month_start_date,
    LAST_DAY(date_actual) AS month_end_date,

    -- Quarter attributes
    QUARTER(date_actual) AS quarter_actual,
    'Q' || QUARTER(date_actual) AS quarter_name,
    DATE_TRUNC('QUARTER', date_actual)::DATE AS quarter_start_date,
    LAST_DAY(DATEADD(MONTH, 2, DATE_TRUNC('QUARTER', date_actual))) AS quarter_end_date,

    -- Year attributes
    YEAR(date_actual) AS year_actual,
    TO_CHAR(date_actual, 'YYYY-MM') AS year_month,
    YEAR(date_actual) || '-Q' || QUARTER(date_actual) AS year_quarter,

    -- Fiscal period (assuming calendar year = fiscal year)
    YEAR(date_actual) AS fiscal_year,
    QUARTER(date_actual) AS fiscal_quarter,

    -- Flags
    CASE WHEN DAYOFWEEK(date_actual) IN (0, 6) THEN TRUE ELSE FALSE END AS is_weekend,
    CASE WHEN DAYOFWEEK(date_actual) NOT IN (0, 6) THEN TRUE ELSE FALSE END AS is_weekday,
    CASE WHEN DAY(date_actual) = 1 THEN TRUE ELSE FALSE END AS is_month_start,
    CASE WHEN date_actual = LAST_DAY(date_actual) THEN TRUE ELSE FALSE END AS is_month_end,
    CASE WHEN date_actual = DATE_TRUNC('QUARTER', date_actual) THEN TRUE ELSE FALSE END AS is_quarter_start,
    CASE WHEN date_actual = LAST_DAY(DATEADD(MONTH, 2, DATE_TRUNC('QUARTER', date_actual))) THEN TRUE ELSE FALSE END AS is_quarter_end,
    CASE WHEN date_actual = DATE_TRUNC('YEAR', date_actual) THEN TRUE ELSE FALSE END AS is_year_start,
    CASE WHEN MONTH(date_actual) = 12 AND DAY(date_actual) = 31 THEN TRUE ELSE FALSE END AS is_year_end

FROM (
    -- Generate dates from 2024-01-01 to 2026-12-31 (3 years)
    SELECT DATEADD(DAY, SEQ4(), '2024-01-01')::DATE AS date_actual
    FROM TABLE(GENERATOR(ROWCOUNT => 1096))  -- ~3 years of dates
)
WHERE NOT EXISTS (SELECT 1 FROM common.dim_date LIMIT 1);

-- ============================================
-- Populate dim_channel
-- Derive channels from staging data
-- ============================================

INSERT INTO common.dim_channel (
    channel_id,
    channel_name,
    channel_category,
    channel_group,
    utm_source,
    is_paid,
    is_digital,
    sort_order
)
WITH all_channels AS (
    -- From ad_spend (paid channels)
    SELECT DISTINCT
        LOWER(REPLACE(channel_normalized, ' ', '_')) AS channel_id,
        channel_normalized AS channel_name,
        utm_source_lower AS utm_source,
        TRUE AS is_paid
    FROM staging.stg_ad_spend

    UNION

    -- From web analytics (derived channels including direct)
    SELECT DISTINCT
        LOWER(REPLACE(channel_derived, ' ', '_')) AS channel_id,
        channel_derived AS channel_name,
        utm_source_lower AS utm_source,
        CASE WHEN utm_source_lower IS NOT NULL THEN TRUE ELSE FALSE END AS is_paid
    FROM staging.stg_web_analytics
    WHERE channel_derived NOT IN (SELECT DISTINCT channel_normalized FROM staging.stg_ad_spend)

    UNION

    -- From salesforce opportunities (non-paid sources)
    SELECT DISTINCT
        LOWER(REPLACE(source_normalized, ' ', '_')) AS channel_id,
        source_normalized AS channel_name,
        NULL AS utm_source,
        FALSE AS is_paid
    FROM staging.stg_salesforce_opportunities
    WHERE source_normalized NOT IN (SELECT DISTINCT channel_normalized FROM staging.stg_ad_spend)
      AND source_normalized IS NOT NULL
)
SELECT DISTINCT
    channel_id,
    channel_name,
    -- Categorize channels
    CASE
        WHEN channel_name = 'Google Ads' THEN 'Paid Search'
        WHEN channel_name IN ('LinkedIn', 'Meta', 'Twitter', 'Facebook') THEN 'Paid Social'
        WHEN channel_name = 'Organic' THEN 'Organic Search'
        WHEN channel_name = 'Direct' THEN 'Direct'
        WHEN channel_name = 'Email' THEN 'Email'
        WHEN channel_name = 'Referral' THEN 'Referral'
        ELSE 'Other'
    END AS channel_category,
    -- Higher level grouping
    CASE
        WHEN is_paid THEN 'Paid'
        WHEN channel_name = 'Organic' THEN 'Organic'
        WHEN channel_name = 'Direct' THEN 'Direct'
        ELSE 'Other'
    END AS channel_group,
    utm_source,
    is_paid,
    TRUE AS is_digital,
    -- Sort order for reports
    CASE
        WHEN channel_name = 'Google Ads' THEN 1
        WHEN channel_name = 'Meta' THEN 2
        WHEN channel_name = 'LinkedIn' THEN 3
        WHEN channel_name = 'Twitter' THEN 4
        WHEN channel_name = 'Organic' THEN 5
        WHEN channel_name = 'Direct' THEN 6
        ELSE 99
    END AS sort_order
FROM all_channels
WHERE channel_name IS NOT NULL;

-- ============================================
-- Populate dim_campaign
-- Derive campaigns from ad_spend via staging
-- ============================================

INSERT INTO common.dim_campaign (
    campaign_id,
    campaign_name,
    channel_key,
    utm_campaign,
    utm_source,
    campaign_type,
    campaign_objective,
    start_date,
    end_date,
    is_active
)
SELECT DISTINCT
    a.campaign_id,
    -- Generate human-readable name from campaign_id
    INITCAP(REPLACE(REPLACE(REPLACE(a.campaign_id, 'CAMP_', ''), '_', ' '), '-', ' ')) AS campaign_name,
    c.channel_key,
    a.utm_campaign_lower AS utm_campaign,
    a.utm_source_lower AS utm_source,
    -- Derive campaign type from campaign_id/name
    CASE
        WHEN LOWER(a.campaign_id) LIKE '%brand%' THEN 'Brand'
        WHEN LOWER(a.campaign_id) LIKE '%retarget%' OR LOWER(a.campaign_id) LIKE '%remarket%' THEN 'Retargeting'
        WHEN LOWER(a.campaign_id) LIKE '%prospect%' OR LOWER(a.campaign_id) LIKE '%acquisition%' THEN 'Prospecting'
        WHEN LOWER(a.campaign_id) LIKE '%conversion%' THEN 'Conversion'
        ELSE 'Performance'
    END AS campaign_type,
    -- Derive objective from campaign type
    CASE
        WHEN LOWER(a.campaign_id) LIKE '%brand%' OR LOWER(a.campaign_id) LIKE '%awareness%' THEN 'Awareness'
        WHEN LOWER(a.campaign_id) LIKE '%consideration%' OR LOWER(a.campaign_id) LIKE '%engagement%' THEN 'Consideration'
        ELSE 'Conversion'
    END AS campaign_objective,
    MIN(a.date) AS start_date,
    MAX(a.date) AS end_date,
    TRUE AS is_active
FROM staging.stg_ad_spend a
LEFT JOIN common.dim_channel c
    ON a.channel_normalized = c.channel_name
GROUP BY
    a.campaign_id,
    a.utm_campaign_lower,
    a.utm_source_lower,
    a.channel_normalized,
    c.channel_key;

-- ============================================
-- Populate dim_landing_page
-- Derive landing pages from web analytics
-- ============================================

INSERT INTO common.dim_landing_page (
    landing_page_path,
    page_name,
    page_category,
    page_type,
    is_conversion_page,
    is_high_intent
)
SELECT DISTINCT
    landing_page_path,
    -- Generate page name from path
    CASE
        WHEN landing_page_path = '/' THEN 'Homepage'
        ELSE INITCAP(REPLACE(REPLACE(landing_page_path, '/', ''), '-', ' '))
    END AS page_name,
    -- Categorize pages
    CASE
        WHEN landing_page_path IN ('/', '/home') THEN 'Homepage'
        WHEN landing_page_path LIKE '/blog%' THEN 'Content'
        WHEN landing_page_path IN ('/pricing', '/demo', '/signup', '/contact', '/request-demo') THEN 'Conversion'
        WHEN landing_page_path LIKE '/product%' OR landing_page_path LIKE '/feature%' THEN 'Product'
        WHEN landing_page_path LIKE '/solution%' OR landing_page_path = '/enterprise' THEN 'Solutions'
        WHEN landing_page_path LIKE '/resource%' OR landing_page_path LIKE '/whitepaper%' THEN 'Resources'
        WHEN landing_page_path LIKE '/about%' OR landing_page_path LIKE '/company%' THEN 'Company'
        ELSE 'Other'
    END AS page_category,
    -- Page type
    CASE
        WHEN landing_page_path = '/' THEN 'Homepage'
        WHEN landing_page_path LIKE '/blog%' THEN 'Blog'
        WHEN landing_page_path = '/pricing' THEN 'Pricing'
        WHEN landing_page_path IN ('/demo', '/request-demo') THEN 'Demo'
        WHEN landing_page_path LIKE '/product%' OR landing_page_path LIKE '/feature%' THEN 'Feature'
        ELSE 'Landing'
    END AS page_type,
    -- Conversion page flag
    CASE
        WHEN landing_page_path IN ('/pricing', '/demo', '/signup', '/contact', '/request-demo', '/enterprise')
        THEN TRUE
        ELSE FALSE
    END AS is_conversion_page,
    -- High intent flag
    CASE
        WHEN landing_page_path IN ('/pricing', '/demo', '/signup', '/request-demo', '/enterprise', '/contact')
        THEN TRUE
        ELSE FALSE
    END AS is_high_intent
FROM staging.stg_web_analytics
WHERE landing_page_path IS NOT NULL;

-- ============================================
-- Populate dim_region
-- Derive regions from salesforce opportunities
-- ============================================

INSERT INTO common.dim_region (
    region_code,
    region_name,
    super_region,
    timezone_primary,
    sort_order
)
SELECT DISTINCT
    -- Generate region code
    CASE
        WHEN owner_region_normalized = 'North America' THEN 'NA'
        WHEN owner_region_normalized = 'Europe' THEN 'EU'
        WHEN owner_region_normalized = 'APAC' THEN 'APAC'
        WHEN owner_region_normalized = 'EMEA' THEN 'EMEA'
        WHEN owner_region_normalized = 'LATAM' THEN 'LATAM'
        ELSE UPPER(LEFT(owner_region_normalized, 4))
    END AS region_code,
    owner_region_normalized AS region_name,
    -- Super region
    CASE
        WHEN owner_region_normalized IN ('North America', 'LATAM') THEN 'Americas'
        WHEN owner_region_normalized IN ('Europe', 'EMEA') THEN 'EMEA'
        WHEN owner_region_normalized = 'APAC' THEN 'APJ'
        ELSE 'Global'
    END AS super_region,
    -- Primary timezone
    CASE
        WHEN owner_region_normalized = 'North America' THEN 'America/New_York'
        WHEN owner_region_normalized = 'Europe' THEN 'Europe/London'
        WHEN owner_region_normalized = 'APAC' THEN 'Asia/Singapore'
        ELSE 'UTC'
    END AS timezone_primary,
    -- Sort order
    CASE
        WHEN owner_region_normalized = 'North America' THEN 1
        WHEN owner_region_normalized = 'Europe' THEN 2
        WHEN owner_region_normalized = 'APAC' THEN 3
        ELSE 99
    END AS sort_order
FROM staging.stg_salesforce_opportunities
WHERE owner_region_normalized IS NOT NULL;

-- ============================================
-- Populate dim_deal_stage
-- Static reference data for opportunity stages
-- ============================================

INSERT INTO common.dim_deal_stage (
    stage_code,
    stage_name,
    stage_category,
    stage_group,
    is_closed,
    is_won,
    is_active_pipeline,
    stage_order,
    probability_default
)
VALUES
    ('pipeline', 'Pipeline', 'Open', 'Early', FALSE, FALSE, TRUE, 1, 25.00),
    ('proposal', 'Proposal', 'Open', 'Late', FALSE, FALSE, TRUE, 2, 50.00),
    ('negotiation', 'Negotiation', 'Open', 'Late', FALSE, FALSE, TRUE, 3, 75.00),
    ('closed_won', 'Closed Won', 'Closed', 'Closed', TRUE, TRUE, FALSE, 4, 100.00),
    ('closed_lost', 'Closed Lost', 'Closed', 'Closed', TRUE, FALSE, FALSE, 5, 0.00);

-- ============================================
-- VALIDATION QUERIES
-- Run after population to verify data integrity
-- ============================================

-- Verify dim_date population
-- SELECT MIN(date_actual), MAX(date_actual), COUNT(*) FROM common.dim_date;

-- Verify dim_channel population
-- SELECT * FROM common.dim_channel ORDER BY sort_order;

-- Verify dim_campaign population
-- SELECT
--     c.channel_name,
--     COUNT(*) AS campaign_count
-- FROM common.dim_campaign cp
-- JOIN common.dim_channel c ON cp.channel_key = c.channel_key
-- GROUP BY c.channel_name;

-- Verify dim_landing_page population
-- SELECT page_category, COUNT(*) FROM common.dim_landing_page GROUP BY page_category;

-- Verify dim_region population
-- SELECT * FROM common.dim_region ORDER BY sort_order;

-- Verify dim_deal_stage population
-- SELECT * FROM common.dim_deal_stage ORDER BY stage_order;

-- ============================================
-- DATA QUALITY CHECKS
-- ============================================

-- Check for orphaned campaigns (no matching channel)
-- SELECT campaign_id FROM common.dim_campaign WHERE channel_key IS NULL;

-- Check for duplicate channels
-- SELECT channel_name, COUNT(*) FROM common.dim_channel GROUP BY channel_name HAVING COUNT(*) > 1;

-- Check date dimension coverage
-- SELECT
--     'ad_spend' AS source,
--     MIN(date) AS min_date,
--     MAX(date) AS max_date,
--     COUNT(*) AS row_count
-- FROM staging.stg_ad_spend
-- UNION ALL
-- SELECT
--     'web_analytics',
--     MIN(session_date),
--     MAX(session_date),
--     COUNT(*)
-- FROM staging.stg_web_analytics
-- UNION ALL
-- SELECT
--     'opportunities',
--     MIN(created_date),
--     MAX(created_date),
--     COUNT(*)
-- FROM staging.stg_salesforce_opportunities;
