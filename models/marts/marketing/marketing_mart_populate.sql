-- ============================================
-- MARKETING MART - POPULATION SCRIPTS
-- Populate fact tables from staging data
-- References common dimension tables
-- ============================================

-- ============================================
-- TRUNCATE TABLES (for full refresh)
-- Uncomment if doing full reload
-- ============================================
-- TRUNCATE TABLE marketing_mart.fct_ad_performance;
-- TRUNCATE TABLE marketing_mart.fct_web_sessions;
-- TRUNCATE TABLE marketing_mart.fct_marketing_funnel;
-- TRUNCATE TABLE marketing_mart.fct_channel_roi;
-- TRUNCATE TABLE marketing_mart.fct_campaign_performance;

-- ============================================
-- Populate fct_ad_performance
-- Grain: One row per date + campaign
-- Source: staging.stg_ad_spend
-- ============================================

INSERT INTO marketing_mart.fct_ad_performance (
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
    -- Pre-calculated metrics
    a.ctr,
    a.cpc,
    a.cpm
FROM staging.stg_ad_spend a
LEFT JOIN common.dim_channel c
    ON a.channel_normalized = c.channel_name
LEFT JOIN common.dim_campaign cp
    ON a.campaign_id = cp.campaign_id;

-- ============================================
-- Populate fct_web_sessions
-- Grain: One row per session
-- Source: staging.stg_web_analytics
-- ============================================

INSERT INTO marketing_mart.fct_web_sessions (
    session_id,
    user_id,
    session_date_key,
    channel_key,
    campaign_key,
    landing_page_key,
    utm_source,
    utm_campaign,
    pageviews,
    conversions,
    is_converted,
    is_attributed,
    is_bounce
)
SELECT
    w.session_id,
    w.user_id,
    TO_NUMBER(TO_CHAR(w.session_date, 'YYYYMMDD')) AS session_date_key,
    c.channel_key,
    cp.campaign_key,
    lp.landing_page_key,
    w.utm_source,
    w.utm_campaign,
    w.pageviews,
    w.conversions,
    w.is_converted,
    w.is_attributed,
    CASE WHEN w.pageviews = 1 THEN TRUE ELSE FALSE END AS is_bounce
FROM staging.stg_web_analytics w
LEFT JOIN common.dim_channel c
    ON w.channel_derived = c.channel_name
LEFT JOIN common.dim_campaign cp
    ON w.utm_campaign_lower = cp.utm_campaign
    AND w.utm_source_lower = cp.utm_source
LEFT JOIN common.dim_landing_page lp
    ON w.landing_page_path = lp.landing_page_path;

-- ============================================
-- Populate fct_marketing_funnel
-- Grain: One row per date + channel
-- Source: Aggregated from ad_spend, web_analytics, salesforce
-- ============================================

INSERT INTO marketing_mart.fct_marketing_funnel (
    date_key,
    channel_key,
    -- Ad metrics
    spend_usd,
    impressions,
    clicks,
    -- Web metrics
    sessions,
    unique_users,
    total_pageviews,
    conversions,
    bounces,
    -- Sales metrics
    opportunities,
    pipeline_value_usd,
    closed_won_opps,
    closed_won_revenue,
    closed_lost_opps,
    -- Efficiency metrics
    ctr,
    cpc,
    cpm,
    cost_per_session,
    cost_per_conversion,
    cost_per_opportunity,
    cac,
    -- Conversion rates
    click_to_session_rate,
    session_conversion_rate,
    bounce_rate,
    opp_win_rate,
    -- ROI metrics
    revenue_per_click,
    roas,
    roi
)
WITH ad_metrics AS (
    -- Aggregate ad spend metrics by date and channel
    SELECT
        TO_NUMBER(TO_CHAR(date, 'YYYYMMDD')) AS date_key,
        channel_normalized AS channel,
        SUM(spend_usd) AS spend_usd,
        SUM(impressions) AS impressions,
        SUM(clicks) AS clicks
    FROM staging.stg_ad_spend
    GROUP BY TO_NUMBER(TO_CHAR(date, 'YYYYMMDD')), channel_normalized
),
web_metrics AS (
    -- Aggregate web session metrics by date and channel
    SELECT
        TO_NUMBER(TO_CHAR(session_date, 'YYYYMMDD')) AS date_key,
        channel_derived AS channel,
        COUNT(DISTINCT session_id) AS sessions,
        COUNT(DISTINCT user_id) AS unique_users,
        SUM(pageviews) AS total_pageviews,
        SUM(conversions) AS conversions,
        SUM(CASE WHEN pageviews = 1 THEN 1 ELSE 0 END) AS bounces
    FROM staging.stg_web_analytics
    GROUP BY TO_NUMBER(TO_CHAR(session_date, 'YYYYMMDD')), channel_derived
),
sales_metrics AS (
    -- Aggregate opportunity metrics by date and channel
    SELECT
        TO_NUMBER(TO_CHAR(created_date, 'YYYYMMDD')) AS date_key,
        source_normalized AS channel,
        COUNT(*) AS opportunities,
        SUM(CASE WHEN NOT is_closed THEN amount_usd ELSE 0 END) AS pipeline_value_usd,
        SUM(CASE WHEN is_won THEN 1 ELSE 0 END) AS closed_won_opps,
        SUM(CASE WHEN is_won THEN amount_usd ELSE 0 END) AS closed_won_revenue,
        SUM(CASE WHEN is_closed AND NOT is_won THEN 1 ELSE 0 END) AS closed_lost_opps
    FROM staging.stg_salesforce_opportunities
    GROUP BY TO_NUMBER(TO_CHAR(created_date, 'YYYYMMDD')), source_normalized
),
combined AS (
    SELECT
        COALESCE(a.date_key, w.date_key, s.date_key) AS date_key,
        COALESCE(a.channel, w.channel, s.channel) AS channel,
        -- Ad metrics
        COALESCE(a.spend_usd, 0) AS spend_usd,
        COALESCE(a.impressions, 0) AS impressions,
        COALESCE(a.clicks, 0) AS clicks,
        -- Web metrics
        COALESCE(w.sessions, 0) AS sessions,
        COALESCE(w.unique_users, 0) AS unique_users,
        COALESCE(w.total_pageviews, 0) AS total_pageviews,
        COALESCE(w.conversions, 0) AS conversions,
        COALESCE(w.bounces, 0) AS bounces,
        -- Sales metrics
        COALESCE(s.opportunities, 0) AS opportunities,
        COALESCE(s.pipeline_value_usd, 0) AS pipeline_value_usd,
        COALESCE(s.closed_won_opps, 0) AS closed_won_opps,
        COALESCE(s.closed_won_revenue, 0) AS closed_won_revenue,
        COALESCE(s.closed_lost_opps, 0) AS closed_lost_opps
    FROM ad_metrics a
    FULL OUTER JOIN web_metrics w
        ON a.date_key = w.date_key AND a.channel = w.channel
    FULL OUTER JOIN sales_metrics s
        ON COALESCE(a.date_key, w.date_key) = s.date_key
        AND COALESCE(a.channel, w.channel) = s.channel
)
SELECT
    cm.date_key,
    c.channel_key,
    -- Ad metrics
    cm.spend_usd,
    cm.impressions,
    cm.clicks,
    -- Web metrics
    cm.sessions,
    cm.unique_users,
    cm.total_pageviews,
    cm.conversions,
    cm.bounces,
    -- Sales metrics
    cm.opportunities,
    cm.pipeline_value_usd,
    cm.closed_won_opps,
    cm.closed_won_revenue,
    cm.closed_lost_opps,
    -- CTR: clicks / impressions
    CASE
        WHEN cm.impressions > 0
        THEN ROUND(cm.clicks::DECIMAL / cm.impressions, 6)
        ELSE NULL
    END AS ctr,
    -- CPC: spend / clicks
    CASE
        WHEN cm.clicks > 0
        THEN ROUND(cm.spend_usd / cm.clicks, 4)
        ELSE NULL
    END AS cpc,
    -- CPM: spend / impressions * 1000
    CASE
        WHEN cm.impressions > 0
        THEN ROUND((cm.spend_usd / cm.impressions) * 1000, 4)
        ELSE NULL
    END AS cpm,
    -- Cost per session
    CASE
        WHEN cm.sessions > 0
        THEN ROUND(cm.spend_usd / cm.sessions, 4)
        ELSE NULL
    END AS cost_per_session,
    -- Cost per conversion
    CASE
        WHEN cm.conversions > 0
        THEN ROUND(cm.spend_usd / cm.conversions, 4)
        ELSE NULL
    END AS cost_per_conversion,
    -- Cost per opportunity
    CASE
        WHEN cm.opportunities > 0
        THEN ROUND(cm.spend_usd / cm.opportunities, 4)
        ELSE NULL
    END AS cost_per_opportunity,
    -- CAC: spend / closed_won_opps
    CASE
        WHEN cm.closed_won_opps > 0
        THEN ROUND(cm.spend_usd / cm.closed_won_opps, 4)
        ELSE NULL
    END AS cac,
    -- Click to session rate
    CASE
        WHEN cm.clicks > 0
        THEN ROUND(cm.sessions::DECIMAL / cm.clicks, 6)
        ELSE NULL
    END AS click_to_session_rate,
    -- Session conversion rate
    CASE
        WHEN cm.sessions > 0
        THEN ROUND(cm.conversions::DECIMAL / cm.sessions, 6)
        ELSE NULL
    END AS session_conversion_rate,
    -- Bounce rate
    CASE
        WHEN cm.sessions > 0
        THEN ROUND(cm.bounces::DECIMAL / cm.sessions, 6)
        ELSE NULL
    END AS bounce_rate,
    -- Opportunity win rate
    CASE
        WHEN cm.opportunities > 0
        THEN ROUND(cm.closed_won_opps::DECIMAL / cm.opportunities, 6)
        ELSE NULL
    END AS opp_win_rate,
    -- Revenue per click
    CASE
        WHEN cm.clicks > 0
        THEN ROUND(cm.closed_won_revenue / cm.clicks, 4)
        ELSE NULL
    END AS revenue_per_click,
    -- ROAS: closed_won_revenue / spend
    CASE
        WHEN cm.spend_usd > 0
        THEN ROUND(cm.closed_won_revenue / cm.spend_usd, 4)
        ELSE NULL
    END AS roas,
    -- ROI: (revenue - spend) / spend
    CASE
        WHEN cm.spend_usd > 0
        THEN ROUND((cm.closed_won_revenue - cm.spend_usd) / cm.spend_usd, 4)
        ELSE NULL
    END AS roi
FROM combined cm
LEFT JOIN common.dim_channel c
    ON cm.channel = c.channel_name
WHERE cm.channel IS NOT NULL;

-- ============================================
-- Populate fct_channel_roi
-- Grain: One row per channel (all-time aggregate)
-- Source: Aggregated from all sources
-- ============================================

INSERT INTO marketing_mart.fct_channel_roi (
    channel_key,
    period_start_date,
    period_end_date,
    period_type,
    -- Marketing metrics
    total_spend_usd,
    total_impressions,
    total_clicks,
    total_sessions,
    total_conversions,
    -- Sales metrics
    total_opportunities,
    total_closed_won,
    total_closed_lost,
    total_pipeline_value,
    total_closed_won_revenue,
    -- Efficiency metrics
    avg_ctr,
    avg_cpc,
    avg_cpm,
    -- ROI metrics
    roi_percentage,
    roas,
    cac,
    cost_per_opportunity,
    cost_per_conversion,
    ltv_to_cac_ratio,
    -- Conversion rates
    click_to_session_rate,
    session_to_conversion_rate,
    conversion_to_opp_rate,
    opp_to_closed_won_rate
)
WITH marketing_totals AS (
    SELECT
        channel_normalized AS channel,
        MIN(date) AS period_start_date,
        MAX(date) AS period_end_date,
        SUM(spend_usd) AS total_spend_usd,
        SUM(impressions) AS total_impressions,
        SUM(clicks) AS total_clicks
    FROM staging.stg_ad_spend
    GROUP BY channel_normalized
),
web_totals AS (
    SELECT
        channel_derived AS channel,
        COUNT(DISTINCT session_id) AS total_sessions,
        SUM(conversions) AS total_conversions
    FROM staging.stg_web_analytics
    GROUP BY channel_derived
),
sales_totals AS (
    SELECT
        source_normalized AS channel,
        COUNT(*) AS total_opportunities,
        SUM(CASE WHEN is_won THEN 1 ELSE 0 END) AS total_closed_won,
        SUM(CASE WHEN is_closed AND NOT is_won THEN 1 ELSE 0 END) AS total_closed_lost,
        SUM(CASE WHEN NOT is_closed THEN amount_usd ELSE 0 END) AS total_pipeline_value,
        SUM(CASE WHEN is_won THEN amount_usd ELSE 0 END) AS total_closed_won_revenue
    FROM staging.stg_salesforce_opportunities
    GROUP BY source_normalized
)
SELECT
    c.channel_key,
    -- Period
    m.period_start_date,
    m.period_end_date,
    'all_time' AS period_type,
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
    -- Efficiency metrics
    CASE
        WHEN COALESCE(m.total_impressions, 0) > 0
        THEN ROUND(COALESCE(m.total_clicks, 0)::DECIMAL / m.total_impressions, 6)
        ELSE NULL
    END AS avg_ctr,
    CASE
        WHEN COALESCE(m.total_clicks, 0) > 0
        THEN ROUND(COALESCE(m.total_spend_usd, 0) / m.total_clicks, 4)
        ELSE NULL
    END AS avg_cpc,
    CASE
        WHEN COALESCE(m.total_impressions, 0) > 0
        THEN ROUND((COALESCE(m.total_spend_usd, 0) / m.total_impressions) * 1000, 4)
        ELSE NULL
    END AS avg_cpm,
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
    -- Cost per Opportunity
    CASE
        WHEN COALESCE(s.total_opportunities, 0) > 0
        THEN ROUND(COALESCE(m.total_spend_usd, 0) / s.total_opportunities, 2)
        ELSE NULL
    END AS cost_per_opportunity,
    -- Cost per Conversion
    CASE
        WHEN COALESCE(w.total_conversions, 0) > 0
        THEN ROUND(COALESCE(m.total_spend_usd, 0) / w.total_conversions, 2)
        ELSE NULL
    END AS cost_per_conversion,
    -- LTV to CAC ratio (using avg deal size as proxy for LTV)
    CASE
        WHEN COALESCE(s.total_closed_won, 0) > 0 AND COALESCE(m.total_spend_usd, 0) > 0
        THEN ROUND(
            (COALESCE(s.total_closed_won_revenue, 0) / s.total_closed_won) /
            (COALESCE(m.total_spend_usd, 0) / s.total_closed_won),
            2
        )
        ELSE NULL
    END AS ltv_to_cac_ratio,
    -- Conversion rates
    CASE
        WHEN COALESCE(m.total_clicks, 0) > 0
        THEN ROUND(COALESCE(w.total_sessions, 0)::DECIMAL / m.total_clicks, 4)
        ELSE NULL
    END AS click_to_session_rate,
    CASE
        WHEN COALESCE(w.total_sessions, 0) > 0
        THEN ROUND(COALESCE(w.total_conversions, 0)::DECIMAL / w.total_sessions, 4)
        ELSE NULL
    END AS session_to_conversion_rate,
    CASE
        WHEN COALESCE(w.total_conversions, 0) > 0
        THEN ROUND(COALESCE(s.total_opportunities, 0)::DECIMAL / w.total_conversions, 4)
        ELSE NULL
    END AS conversion_to_opp_rate,
    CASE
        WHEN COALESCE(s.total_opportunities, 0) > 0
        THEN ROUND(COALESCE(s.total_closed_won, 0)::DECIMAL / s.total_opportunities, 4)
        ELSE NULL
    END AS opp_to_closed_won_rate
FROM marketing_totals m
FULL OUTER JOIN web_totals w ON m.channel = w.channel
FULL OUTER JOIN sales_totals s ON COALESCE(m.channel, w.channel) = s.channel
LEFT JOIN common.dim_channel c ON COALESCE(m.channel, w.channel, s.channel) = c.channel_name
WHERE COALESCE(m.channel, w.channel, s.channel) IS NOT NULL;

-- ============================================
-- Populate fct_campaign_performance
-- Grain: One row per campaign (aggregate)
-- Source: Aggregated from ad_spend and web_analytics
-- ============================================

INSERT INTO marketing_mart.fct_campaign_performance (
    campaign_key,
    channel_key,
    period_start_date,
    period_end_date,
    total_spend_usd,
    total_impressions,
    total_clicks,
    total_sessions,
    total_conversions,
    avg_ctr,
    avg_cpc,
    avg_cpm,
    conversion_rate,
    cost_per_conversion,
    days_active,
    is_active
)
WITH ad_campaign_totals AS (
    SELECT
        campaign_id,
        channel_normalized AS channel,
        MIN(date) AS period_start_date,
        MAX(date) AS period_end_date,
        SUM(spend_usd) AS total_spend_usd,
        SUM(impressions) AS total_impressions,
        SUM(clicks) AS total_clicks,
        DATEDIFF(DAY, MIN(date), MAX(date)) + 1 AS days_active
    FROM staging.stg_ad_spend
    GROUP BY campaign_id, channel_normalized
),
web_campaign_totals AS (
    SELECT
        utm_campaign_lower AS utm_campaign,
        utm_source_lower AS utm_source,
        COUNT(DISTINCT session_id) AS total_sessions,
        SUM(conversions) AS total_conversions
    FROM staging.stg_web_analytics
    WHERE utm_campaign IS NOT NULL
    GROUP BY utm_campaign_lower, utm_source_lower
)
SELECT
    cp.campaign_key,
    c.channel_key,
    a.period_start_date,
    a.period_end_date,
    a.total_spend_usd,
    a.total_impressions,
    a.total_clicks,
    COALESCE(w.total_sessions, 0) AS total_sessions,
    COALESCE(w.total_conversions, 0) AS total_conversions,
    -- CTR
    CASE
        WHEN a.total_impressions > 0
        THEN ROUND(a.total_clicks::DECIMAL / a.total_impressions, 6)
        ELSE NULL
    END AS avg_ctr,
    -- CPC
    CASE
        WHEN a.total_clicks > 0
        THEN ROUND(a.total_spend_usd / a.total_clicks, 4)
        ELSE NULL
    END AS avg_cpc,
    -- CPM
    CASE
        WHEN a.total_impressions > 0
        THEN ROUND((a.total_spend_usd / a.total_impressions) * 1000, 4)
        ELSE NULL
    END AS avg_cpm,
    -- Conversion rate
    CASE
        WHEN COALESCE(w.total_sessions, 0) > 0
        THEN ROUND(COALESCE(w.total_conversions, 0)::DECIMAL / w.total_sessions, 6)
        ELSE NULL
    END AS conversion_rate,
    -- Cost per conversion
    CASE
        WHEN COALESCE(w.total_conversions, 0) > 0
        THEN ROUND(a.total_spend_usd / w.total_conversions, 4)
        ELSE NULL
    END AS cost_per_conversion,
    a.days_active,
    CASE WHEN a.period_end_date >= CURRENT_DATE() - 7 THEN TRUE ELSE FALSE END AS is_active
FROM ad_campaign_totals a
LEFT JOIN common.dim_campaign cp ON a.campaign_id = cp.campaign_id
LEFT JOIN common.dim_channel c ON a.channel = c.channel_name
LEFT JOIN web_campaign_totals w
    ON cp.utm_campaign = w.utm_campaign
    AND cp.utm_source = w.utm_source
WHERE cp.campaign_key IS NOT NULL;

-- ============================================
-- VALIDATION QUERIES
-- Run after population to verify data integrity
-- ============================================

-- Verify fct_ad_performance row count
-- SELECT
--     'staging' AS source, COUNT(*) AS row_count
-- FROM staging.stg_ad_spend
-- UNION ALL
-- SELECT
--     'fct_ad_performance', COUNT(*)
-- FROM marketing_mart.fct_ad_performance;

-- Verify fct_web_sessions row count
-- SELECT
--     'staging' AS source, COUNT(*) AS row_count
-- FROM staging.stg_web_analytics
-- UNION ALL
-- SELECT
--     'fct_web_sessions', COUNT(*)
-- FROM marketing_mart.fct_web_sessions;

-- Verify spend totals match
-- SELECT
--     'staging' AS source,
--     SUM(spend_usd) AS total_spend
-- FROM staging.stg_ad_spend
-- UNION ALL
-- SELECT
--     'fct_ad_performance',
--     SUM(spend_usd)
-- FROM marketing_mart.fct_ad_performance;

-- Check for NULL dimension keys
-- SELECT
--     SUM(CASE WHEN channel_key IS NULL THEN 1 ELSE 0 END) AS null_channel_count,
--     SUM(CASE WHEN campaign_key IS NULL THEN 1 ELSE 0 END) AS null_campaign_count,
--     SUM(CASE WHEN landing_page_key IS NULL THEN 1 ELSE 0 END) AS null_landing_page_count
-- FROM marketing_mart.fct_web_sessions;

-- Verify funnel metrics
-- SELECT
--     SUM(spend_usd) AS total_spend,
--     SUM(clicks) AS total_clicks,
--     SUM(sessions) AS total_sessions,
--     SUM(conversions) AS total_conversions,
--     SUM(closed_won_opps) AS total_closed_won,
--     SUM(closed_won_revenue) AS total_revenue
-- FROM marketing_mart.fct_marketing_funnel;

-- ============================================
-- INCREMENTAL LOAD PATTERN (for future use)
-- ============================================

-- -- For incremental ad performance loads
-- MERGE INTO marketing_mart.fct_ad_performance target
-- USING (
--     SELECT
--         TO_NUMBER(TO_CHAR(a.date, 'YYYYMMDD')) AS date_key,
--         cp.campaign_key,
--         c.channel_key,
--         a.spend_usd,
--         a.clicks,
--         a.impressions,
--         a.ctr,
--         a.cpc,
--         a.cpm
--     FROM staging.stg_ad_spend a
--     LEFT JOIN common.dim_channel c ON a.channel_normalized = c.channel_name
--     LEFT JOIN common.dim_campaign cp ON a.campaign_id = cp.campaign_id
--     WHERE a._loaded_at >= DATEADD(DAY, -1, CURRENT_TIMESTAMP())
-- ) source
-- ON target.date_key = source.date_key
--    AND target.campaign_key = source.campaign_key
-- WHEN MATCHED THEN UPDATE SET
--     target.spend_usd = source.spend_usd,
--     target.clicks = source.clicks,
--     target.impressions = source.impressions,
--     target.ctr = source.ctr,
--     target.cpc = source.cpc,
--     target.cpm = source.cpm,
--     target._loaded_at = CURRENT_TIMESTAMP()
-- WHEN NOT MATCHED THEN INSERT (
--     date_key, campaign_key, channel_key, spend_usd, clicks, impressions, ctr, cpc, cpm
-- ) VALUES (
--     source.date_key, source.campaign_key, source.channel_key, source.spend_usd,
--     source.clicks, source.impressions, source.ctr, source.cpc, source.cpm
-- );

-- ============================================
-- POST-LOAD STATISTICS UPDATE
-- ============================================

-- ANALYZE marketing_mart.fct_ad_performance;
-- ANALYZE marketing_mart.fct_web_sessions;
-- ANALYZE marketing_mart.fct_marketing_funnel;
-- ANALYZE marketing_mart.fct_channel_roi;
-- ANALYZE marketing_mart.fct_campaign_performance;
