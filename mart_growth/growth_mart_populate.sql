-- ============================================
-- GROWTH/MARKETING MART - DATA POPULATION SCRIPTS
-- ============================================
-- This file contains all INSERT/transformation logic
-- to populate the Growth/Marketing Mart dimensional model
-- Focus: Ad performance, web analytics, funnel metrics, and ROI
-- ============================================

-- ============================================
-- Populate dim_date (if not already populated from sales_mart)
-- ============================================
INSERT INTO growth_mart.dim_date
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
)
WHERE NOT EXISTS (SELECT 1 FROM growth_mart.dim_date LIMIT 1);

-- ============================================
-- Populate dim_channel (dynamic from source data)
-- Derives distinct channels from ad_spend, web_analytics, and salesforce
-- ============================================
INSERT INTO growth_mart.dim_channel (channel_name, channel_category, utm_source, is_paid)
WITH all_channels AS (
    -- From ad_spend (paid channels with utm_source mapping)
    SELECT DISTINCT
        channel AS channel_name,
        utm_source,
        TRUE AS is_paid
    FROM ad_spend

    UNION

    -- From web_analytics (map utm_source to channel)
    SELECT DISTINCT
        CASE
            WHEN utm_source = 'google' THEN 'Google Ads'
            WHEN utm_source = 'facebook' THEN 'Meta'
            WHEN utm_source = 'linkedin' THEN 'LinkedIn'
            WHEN utm_source = 'twitter' THEN 'Twitter'
            WHEN utm_source IS NULL THEN 'Direct'
            ELSE 'Other'
        END AS channel_name,
        utm_source,
        CASE WHEN utm_source IS NOT NULL THEN TRUE ELSE FALSE END AS is_paid
    FROM web_analytics
    WHERE utm_source NOT IN (SELECT DISTINCT utm_source FROM ad_spend WHERE utm_source IS NOT NULL)
       OR utm_source IS NULL

    UNION

    -- From salesforce opportunities (non-paid sources)
    SELECT DISTINCT
        source AS channel_name,
        NULL AS utm_source,
        FALSE AS is_paid
    FROM salesforce_opportunities
    WHERE source NOT IN (SELECT DISTINCT channel FROM ad_spend)
)
SELECT DISTINCT
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
-- Populate dim_campaign (from ad_spend)
-- ============================================
INSERT INTO growth_mart.dim_campaign (campaign_id, utm_campaign, channel_key, campaign_name)
SELECT DISTINCT
    a.campaign_id,
    a.utm_campaign,
    c.channel_key,
    REPLACE(REPLACE(a.campaign_id, 'CAMP_', ''), '_', ' ') AS campaign_name
FROM ad_spend a
LEFT JOIN growth_mart.dim_channel c ON a.channel = c.channel_name;

-- ============================================
-- Populate dim_landing_page (from web_analytics)
-- ============================================
INSERT INTO growth_mart.dim_landing_page (landing_page_path, page_category)
SELECT DISTINCT
    landing_page AS landing_page_path,
    CASE
        WHEN landing_page = '/pricing' THEN 'Pricing'
        WHEN landing_page = '/demo' THEN 'Demo'
        WHEN landing_page = '/enterprise' THEN 'Enterprise'
        WHEN landing_page = '/solutions' THEN 'Solutions'
        WHEN landing_page = '/blog' THEN 'Blog'
        WHEN landing_page = '/' THEN 'Homepage'
        ELSE 'Other'
    END AS page_category
FROM web_analytics;

-- ============================================
-- Populate dim_utm (UTM parameter combinations)
-- ============================================
INSERT INTO growth_mart.dim_utm (utm_source, utm_campaign, channel_key)
SELECT DISTINCT
    COALESCE(a.utm_source, w.utm_source) AS utm_source,
    COALESCE(a.utm_campaign, w.utm_campaign) AS utm_campaign,
    c.channel_key
FROM ad_spend a
FULL OUTER JOIN (
    SELECT DISTINCT utm_source, utm_campaign
    FROM web_analytics
    WHERE utm_source IS NOT NULL
) w ON a.utm_source = w.utm_source AND a.utm_campaign = w.utm_campaign
LEFT JOIN growth_mart.dim_channel c ON COALESCE(a.utm_source, w.utm_source) = c.utm_source;

-- ============================================
-- Populate fct_ad_performance
-- Grain: One row per date + campaign
-- ============================================
INSERT INTO growth_mart.fct_ad_performance (
    date_key,
    campaign_key,
    channel_key,
    spend_usd,
    clicks,
    impressions,
    ctr,
    cpc,
    cpm
)
SELECT
    TO_NUMBER(TO_CHAR(a.date, 'YYYYMMDD')) AS date_key,
    cp.campaign_key,
    c.channel_key,
    a.spend_usd,
    a.clicks,
    a.impressions,
    -- CTR: Click-through rate (clicks / impressions)
    CASE
        WHEN a.impressions > 0 THEN ROUND((a.clicks::DECIMAL / a.impressions) * 100, 4)
        ELSE 0
    END AS ctr,
    -- CPC: Cost per click (spend / clicks)
    CASE
        WHEN a.clicks > 0 THEN ROUND(a.spend_usd / a.clicks, 2)
        ELSE 0
    END AS cpc,
    -- CPM: Cost per thousand impressions (spend / impressions * 1000)
    CASE
        WHEN a.impressions > 0 THEN ROUND((a.spend_usd / a.impressions) * 1000, 2)
        ELSE 0
    END AS cpm
FROM ad_spend a
LEFT JOIN growth_mart.dim_channel c ON a.channel = c.channel_name
LEFT JOIN growth_mart.dim_campaign cp ON a.campaign_id = cp.campaign_id;

-- ============================================
-- Populate fct_web_sessions
-- Grain: One row per session
-- ============================================
INSERT INTO growth_mart.fct_web_sessions (
    session_id,
    user_id,
    session_date_key,
    channel_key,
    landing_page_key,
    utm_key,
    pageviews,
    conversions,
    is_converted
)
SELECT
    w.session_id,
    w.user_id,
    TO_NUMBER(TO_CHAR(w.session_date, 'YYYYMMDD')) AS session_date_key,
    c.channel_key,
    lp.landing_page_key,
    u.utm_key,
    w.pageviews,
    w.conversions,
    CASE WHEN w.conversions > 0 THEN TRUE ELSE FALSE END AS is_converted
FROM web_analytics w
LEFT JOIN growth_mart.dim_channel c ON w.utm_source = c.utm_source
LEFT JOIN growth_mart.dim_landing_page lp ON w.landing_page = lp.landing_page_path
LEFT JOIN growth_mart.dim_utm u ON w.utm_source = u.utm_source AND w.utm_campaign = u.utm_campaign;

-- ============================================
-- Populate fct_marketing_funnel
-- Grain: One row per date + channel (aggregated daily metrics)
-- This is the key table for funnel and ROI analysis
-- ============================================
INSERT INTO growth_mart.fct_marketing_funnel (
    date_key,
    channel_key,
    -- Ad metrics
    total_spend_usd,
    total_impressions,
    total_clicks,
    -- Web metrics
    total_sessions,
    total_pageviews,
    total_conversions,
    unique_users,
    -- Calculated efficiency metrics
    avg_ctr,
    avg_cpc,
    avg_cpm,
    session_conversion_rate,
    cost_per_conversion
)
WITH ad_metrics AS (
    -- Aggregate ad spend metrics by date and channel
    SELECT
        TO_NUMBER(TO_CHAR(date, 'YYYYMMDD')) AS date_key,
        channel,
        SUM(spend_usd) AS total_spend_usd,
        SUM(impressions) AS total_impressions,
        SUM(clicks) AS total_clicks
    FROM ad_spend
    GROUP BY TO_NUMBER(TO_CHAR(date, 'YYYYMMDD')), channel
),
web_metrics AS (
    -- Aggregate web session metrics by date and channel
    SELECT
        TO_NUMBER(TO_CHAR(session_date, 'YYYYMMDD')) AS date_key,
        CASE
            WHEN utm_source = 'google' THEN 'Google Ads'
            WHEN utm_source = 'facebook' THEN 'Meta'
            WHEN utm_source = 'linkedin' THEN 'LinkedIn'
            WHEN utm_source = 'twitter' THEN 'Twitter'
            WHEN utm_source IS NULL THEN 'Direct'
            ELSE 'Other'
        END AS channel,
        COUNT(DISTINCT session_id) AS total_sessions,
        SUM(pageviews) AS total_pageviews,
        SUM(conversions) AS total_conversions,
        COUNT(DISTINCT user_id) AS unique_users
    FROM web_analytics
    GROUP BY TO_NUMBER(TO_CHAR(session_date, 'YYYYMMDD')),
             CASE
                 WHEN utm_source = 'google' THEN 'Google Ads'
                 WHEN utm_source = 'facebook' THEN 'Meta'
                 WHEN utm_source = 'linkedin' THEN 'LinkedIn'
                 WHEN utm_source = 'twitter' THEN 'Twitter'
                 WHEN utm_source IS NULL THEN 'Direct'
                 ELSE 'Other'
             END
)
SELECT
    COALESCE(a.date_key, w.date_key) AS date_key,
    c.channel_key,
    -- Ad metrics
    COALESCE(a.total_spend_usd, 0) AS total_spend_usd,
    COALESCE(a.total_impressions, 0) AS total_impressions,
    COALESCE(a.total_clicks, 0) AS total_clicks,
    -- Web metrics
    COALESCE(w.total_sessions, 0) AS total_sessions,
    COALESCE(w.total_pageviews, 0) AS total_pageviews,
    COALESCE(w.total_conversions, 0) AS total_conversions,
    COALESCE(w.unique_users, 0) AS unique_users,
    -- Calculated efficiency metrics
    CASE
        WHEN COALESCE(a.total_impressions, 0) > 0
        THEN ROUND((COALESCE(a.total_clicks, 0)::DECIMAL / a.total_impressions) * 100, 4)
        ELSE 0
    END AS avg_ctr,
    CASE
        WHEN COALESCE(a.total_clicks, 0) > 0
        THEN ROUND(COALESCE(a.total_spend_usd, 0) / a.total_clicks, 2)
        ELSE 0
    END AS avg_cpc,
    CASE
        WHEN COALESCE(a.total_impressions, 0) > 0
        THEN ROUND((COALESCE(a.total_spend_usd, 0) / a.total_impressions) * 1000, 2)
        ELSE 0
    END AS avg_cpm,
    CASE
        WHEN COALESCE(w.total_sessions, 0) > 0
        THEN ROUND((COALESCE(w.total_conversions, 0)::DECIMAL / w.total_sessions) * 100, 2)
        ELSE 0
    END AS session_conversion_rate,
    CASE
        WHEN COALESCE(w.total_conversions, 0) > 0
        THEN ROUND(COALESCE(a.total_spend_usd, 0) / w.total_conversions, 2)
        ELSE 0
    END AS cost_per_conversion
FROM ad_metrics a
FULL OUTER JOIN web_metrics w ON a.date_key = w.date_key AND a.channel = w.channel
LEFT JOIN growth_mart.dim_channel c ON COALESCE(a.channel, w.channel) = c.channel_name;

-- ============================================
-- Populate fct_channel_roi
-- Grain: One row per channel (aggregated totals for ROI calculation)
-- Joins marketing data with closed deals for full-funnel ROI
-- ============================================
INSERT INTO growth_mart.fct_channel_roi (
    channel_key,
    -- Period (for filtering)
    period_start_date,
    period_end_date,
    -- Marketing metrics (totals)
    total_spend_usd,
    total_impressions,
    total_clicks,
    total_sessions,
    total_conversions,
    -- Sales metrics (from salesforce)
    total_opportunities,
    total_closed_won,
    total_closed_lost,
    total_pipeline_value,
    total_closed_won_revenue,
    -- ROI & efficiency metrics
    roi_percentage,
    roas,
    cac,
    cost_per_opportunity,
    opportunity_to_closed_won_rate
)
WITH marketing_totals AS (
    SELECT
        channel,
        MIN(date) AS period_start_date,
        MAX(date) AS period_end_date,
        SUM(spend_usd) AS total_spend_usd,
        SUM(impressions) AS total_impressions,
        SUM(clicks) AS total_clicks
    FROM ad_spend
    GROUP BY channel
),
web_totals AS (
    SELECT
        CASE
            WHEN utm_source = 'google' THEN 'Google Ads'
            WHEN utm_source = 'facebook' THEN 'Meta'
            WHEN utm_source = 'linkedin' THEN 'LinkedIn'
            WHEN utm_source = 'twitter' THEN 'Twitter'
            WHEN utm_source IS NULL THEN 'Direct'
            ELSE 'Other'
        END AS channel,
        COUNT(DISTINCT session_id) AS total_sessions,
        SUM(conversions) AS total_conversions
    FROM web_analytics
    GROUP BY CASE
                 WHEN utm_source = 'google' THEN 'Google Ads'
                 WHEN utm_source = 'facebook' THEN 'Meta'
                 WHEN utm_source = 'linkedin' THEN 'LinkedIn'
                 WHEN utm_source = 'twitter' THEN 'Twitter'
                 WHEN utm_source IS NULL THEN 'Direct'
                 ELSE 'Other'
             END
),
sales_totals AS (
    SELECT
        source AS channel,
        COUNT(*) AS total_opportunities,
        SUM(CASE WHEN stage = 'Closed Won' THEN 1 ELSE 0 END) AS total_closed_won,
        SUM(CASE WHEN stage = 'Closed Lost' THEN 1 ELSE 0 END) AS total_closed_lost,
        SUM(CASE WHEN stage IN ('Pipeline', 'Proposal') THEN amount_usd ELSE 0 END) AS total_pipeline_value,
        SUM(CASE WHEN stage = 'Closed Won' THEN amount_usd ELSE 0 END) AS total_closed_won_revenue
    FROM salesforce_opportunities
    GROUP BY source
)
SELECT
    c.channel_key,
    -- Period
    m.period_start_date,
    m.period_end_date,
    -- Marketing metrics
    COALESCE(m.total_spend_usd, 0) AS total_spend_usd,
    COALESCE(m.total_impressions, 0) AS total_impressions,
    COALESCE(m.total_clicks, 0) AS total_clicks,
    COALESCE(w.total_sessions, 0) AS total_sessions,
    COALESCE(w.total_conversions, 0) AS total_conversions,
    -- Sales metrics
    COALESCE(s.total_opportunities, 0) AS total_opportunities,
    COALESCE(s.total_closed_won, 0) AS total_closed_won,
    COALESCE(s.total_closed_lost, 0) AS total_closed_lost,
    COALESCE(s.total_pipeline_value, 0) AS total_pipeline_value,
    COALESCE(s.total_closed_won_revenue, 0) AS total_closed_won_revenue,
    -- ROI: (Revenue - Spend) / Spend * 100
    CASE
        WHEN COALESCE(m.total_spend_usd, 0) > 0
        THEN ROUND(((COALESCE(s.total_closed_won_revenue, 0) - m.total_spend_usd) / m.total_spend_usd) * 100, 2)
        ELSE NULL
    END AS roi_percentage,
    -- ROAS: Revenue / Spend
    CASE
        WHEN COALESCE(m.total_spend_usd, 0) > 0
        THEN ROUND(COALESCE(s.total_closed_won_revenue, 0) / m.total_spend_usd, 2)
        ELSE NULL
    END AS roas,
    -- CAC: Spend / Closed Won Opportunities
    CASE
        WHEN COALESCE(s.total_closed_won, 0) > 0
        THEN ROUND(COALESCE(m.total_spend_usd, 0) / s.total_closed_won, 2)
        ELSE NULL
    END AS cac,
    -- Cost per Opportunity: Spend / Total Opportunities
    CASE
        WHEN COALESCE(s.total_opportunities, 0) > 0
        THEN ROUND(COALESCE(m.total_spend_usd, 0) / s.total_opportunities, 2)
        ELSE NULL
    END AS cost_per_opportunity,
    -- Opportunity to Closed Won Rate
    CASE
        WHEN COALESCE(s.total_opportunities, 0) > 0
        THEN ROUND((COALESCE(s.total_closed_won, 0)::DECIMAL / s.total_opportunities) * 100, 2)
        ELSE NULL
    END AS opportunity_to_closed_won_rate
FROM marketing_totals m
FULL OUTER JOIN web_totals w ON m.channel = w.channel
FULL OUTER JOIN sales_totals s ON COALESCE(m.channel, w.channel) = s.channel
LEFT JOIN growth_mart.dim_channel c ON COALESCE(m.channel, w.channel, s.channel) = c.channel_name;
