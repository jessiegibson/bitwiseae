-- ============================================
-- SALES MART - POPULATION SCRIPTS
-- Populate fact tables from staging data
-- References common dimension tables
-- ============================================

-- ============================================
-- TRUNCATE TABLES (for full refresh)
-- Uncomment if doing full reload
-- ============================================
-- TRUNCATE TABLE sales_mart.fct_opportunities;
-- TRUNCATE TABLE sales_mart.fct_closed_deals;
-- TRUNCATE TABLE sales_mart.fct_sales_summary;

-- ============================================
-- Populate fct_opportunities
-- Grain: One row per opportunity
-- Source: staging.stg_salesforce_opportunities
-- ============================================

INSERT INTO sales_mart.fct_opportunities (
    opportunity_id,
    account_id,
    created_date_key,
    channel_key,
    stage_key,
    region_key,
    source_original,
    amount_usd,
    is_closed,
    is_won
)
SELECT
    o.opportunity_id,
    o.account_id,
    -- Date key (YYYYMMDD format)
    TO_NUMBER(TO_CHAR(o.created_date, 'YYYYMMDD')) AS created_date_key,
    -- Channel lookup via source_normalized
    c.channel_key,
    -- Stage lookup via stage name
    s.stage_key,
    -- Region lookup via normalized region
    r.region_key,
    -- Original source for audit
    o.source AS source_original,
    -- Amount
    o.amount_usd,
    -- Derived flags
    o.is_closed,
    o.is_won
FROM staging.stg_salesforce_opportunities o
LEFT JOIN common.dim_channel c
    ON o.source_normalized = c.channel_name
LEFT JOIN common.dim_deal_stage s
    ON LOWER(REPLACE(o.stage, ' ', '_')) = s.stage_code
LEFT JOIN common.dim_region r
    ON o.owner_region_normalized = r.region_name;

-- ============================================
-- Populate fct_closed_deals
-- Grain: One row per closed-won opportunity
-- Source: staging.stg_salesforce_opportunities (filtered)
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
    -- Using created_date as closed_date (source doesn't have separate close date)
    TO_NUMBER(TO_CHAR(o.created_date, 'YYYYMMDD')) AS closed_date_key,
    c.channel_key,
    r.region_key,
    o.amount_usd AS deal_amount_usd
FROM staging.stg_salesforce_opportunities o
LEFT JOIN common.dim_channel c
    ON o.source_normalized = c.channel_name
LEFT JOIN common.dim_region r
    ON o.owner_region_normalized = r.region_name
WHERE o.is_won = TRUE;

-- ============================================
-- Populate fct_sales_summary
-- Grain: One row per date + channel + region
-- Pre-aggregated from opportunities
-- ============================================

INSERT INTO sales_mart.fct_sales_summary (
    date_key,
    channel_key,
    region_key,
    total_opportunities,
    pipeline_opportunities,
    proposal_opportunities,
    closed_won_count,
    closed_lost_count,
    total_pipeline_value,
    closed_won_revenue,
    closed_lost_value,
    win_rate,
    avg_deal_size
)
WITH opportunity_aggregates AS (
    SELECT
        TO_NUMBER(TO_CHAR(o.created_date, 'YYYYMMDD')) AS date_key,
        c.channel_key,
        r.region_key,
        -- Counts by stage
        COUNT(*) AS total_opportunities,
        SUM(CASE WHEN o.stage = 'Pipeline' THEN 1 ELSE 0 END) AS pipeline_opportunities,
        SUM(CASE WHEN o.stage = 'Proposal' THEN 1 ELSE 0 END) AS proposal_opportunities,
        SUM(CASE WHEN o.is_won THEN 1 ELSE 0 END) AS closed_won_count,
        SUM(CASE WHEN o.is_closed AND NOT o.is_won THEN 1 ELSE 0 END) AS closed_lost_count,
        -- Revenue measures
        SUM(CASE WHEN NOT o.is_closed THEN o.amount_usd ELSE 0 END) AS total_pipeline_value,
        SUM(CASE WHEN o.is_won THEN o.amount_usd ELSE 0 END) AS closed_won_revenue,
        SUM(CASE WHEN o.is_closed AND NOT o.is_won THEN o.amount_usd ELSE 0 END) AS closed_lost_value
    FROM staging.stg_salesforce_opportunities o
    LEFT JOIN common.dim_channel c
        ON o.source_normalized = c.channel_name
    LEFT JOIN common.dim_region r
        ON o.owner_region_normalized = r.region_name
    GROUP BY
        TO_NUMBER(TO_CHAR(o.created_date, 'YYYYMMDD')),
        c.channel_key,
        r.region_key
)
SELECT
    date_key,
    channel_key,
    region_key,
    total_opportunities,
    pipeline_opportunities,
    proposal_opportunities,
    closed_won_count,
    closed_lost_count,
    total_pipeline_value,
    closed_won_revenue,
    closed_lost_value,
    -- Win rate: closed_won / (closed_won + closed_lost)
    CASE
        WHEN (closed_won_count + closed_lost_count) > 0
        THEN ROUND(closed_won_count::DECIMAL / (closed_won_count + closed_lost_count), 4)
        ELSE NULL
    END AS win_rate,
    -- Average deal size
    CASE
        WHEN closed_won_count > 0
        THEN ROUND(closed_won_revenue / closed_won_count, 2)
        ELSE NULL
    END AS avg_deal_size
FROM opportunity_aggregates;

-- ============================================
-- Populate fct_pipeline_snapshot (current snapshot)
-- Grain: One row per opportunity per snapshot date
-- This would typically run daily via scheduled job
-- ============================================

INSERT INTO sales_mart.fct_pipeline_snapshot (
    snapshot_date_key,
    opportunity_id,
    channel_key,
    stage_key,
    region_key,
    amount_usd,
    days_in_stage,
    days_since_created
)
SELECT
    -- Current date as snapshot date
    TO_NUMBER(TO_CHAR(CURRENT_DATE(), 'YYYYMMDD')) AS snapshot_date_key,
    o.opportunity_id,
    c.channel_key,
    s.stage_key,
    r.region_key,
    o.amount_usd,
    -- Days in stage (would need stage change history for accuracy, using 0 as placeholder)
    0 AS days_in_stage,
    -- Days since created
    DATEDIFF(DAY, o.created_date, CURRENT_DATE()) AS days_since_created
FROM staging.stg_salesforce_opportunities o
LEFT JOIN common.dim_channel c
    ON o.source_normalized = c.channel_name
LEFT JOIN common.dim_deal_stage s
    ON LOWER(REPLACE(o.stage, ' ', '_')) = s.stage_code
LEFT JOIN common.dim_region r
    ON o.owner_region_normalized = r.region_name
-- Only include open opportunities in pipeline snapshot
WHERE o.is_closed = FALSE;

-- ============================================
-- VALIDATION QUERIES
-- Run after population to verify data integrity
-- ============================================

-- Verify fct_opportunities row count matches staging
-- SELECT
--     'staging' AS source, COUNT(*) AS row_count
-- FROM staging.stg_salesforce_opportunities
-- UNION ALL
-- SELECT
--     'fct_opportunities', COUNT(*)
-- FROM sales_mart.fct_opportunities;

-- Verify revenue totals match
-- SELECT
--     'staging' AS source,
--     SUM(CASE WHEN is_won THEN amount_usd ELSE 0 END) AS closed_won_revenue
-- FROM staging.stg_salesforce_opportunities
-- UNION ALL
-- SELECT
--     'fct_closed_deals',
--     SUM(deal_amount_usd)
-- FROM sales_mart.fct_closed_deals;

-- Check for NULL dimension keys (orphaned records)
-- SELECT
--     SUM(CASE WHEN channel_key IS NULL THEN 1 ELSE 0 END) AS null_channel_count,
--     SUM(CASE WHEN stage_key IS NULL THEN 1 ELSE 0 END) AS null_stage_count,
--     SUM(CASE WHEN region_key IS NULL THEN 1 ELSE 0 END) AS null_region_count
-- FROM sales_mart.fct_opportunities;

-- Verify aggregations in fct_sales_summary
-- SELECT
--     SUM(total_opportunities) AS total_opps,
--     SUM(closed_won_count) AS total_won,
--     SUM(closed_won_revenue) AS total_revenue
-- FROM sales_mart.fct_sales_summary;

-- ============================================
-- INCREMENTAL LOAD PATTERN (for future use)
-- Use this pattern for daily incremental loads
-- ============================================

-- -- Merge pattern for incremental opportunity updates
-- MERGE INTO sales_mart.fct_opportunities target
-- USING (
--     SELECT
--         o.opportunity_id,
--         o.account_id,
--         TO_NUMBER(TO_CHAR(o.created_date, 'YYYYMMDD')) AS created_date_key,
--         c.channel_key,
--         s.stage_key,
--         r.region_key,
--         o.source AS source_original,
--         o.amount_usd,
--         o.is_closed,
--         o.is_won
--     FROM staging.stg_salesforce_opportunities o
--     LEFT JOIN common.dim_channel c ON o.source_normalized = c.channel_name
--     LEFT JOIN common.dim_deal_stage s ON LOWER(REPLACE(o.stage, ' ', '_')) = s.stage_code
--     LEFT JOIN common.dim_region r ON o.owner_region_normalized = r.region_name
--     WHERE o._loaded_at >= DATEADD(DAY, -1, CURRENT_TIMESTAMP())  -- Last 24 hours
-- ) source
-- ON target.opportunity_id = source.opportunity_id
-- WHEN MATCHED THEN UPDATE SET
--     target.stage_key = source.stage_key,
--     target.amount_usd = source.amount_usd,
--     target.is_closed = source.is_closed,
--     target.is_won = source.is_won,
--     target._updated_at = CURRENT_TIMESTAMP()
-- WHEN NOT MATCHED THEN INSERT (
--     opportunity_id, account_id, created_date_key, channel_key, stage_key,
--     region_key, source_original, amount_usd, is_closed, is_won
-- ) VALUES (
--     source.opportunity_id, source.account_id, source.created_date_key, source.channel_key,
--     source.stage_key, source.region_key, source.source_original, source.amount_usd,
--     source.is_closed, source.is_won
-- );

-- ============================================
-- POST-LOAD STATISTICS UPDATE
-- Run after load to update query optimization stats
-- ============================================

-- ANALYZE sales_mart.fct_opportunities;
-- ANALYZE sales_mart.fct_closed_deals;
-- ANALYZE sales_mart.fct_sales_summary;
-- ANALYZE sales_mart.fct_pipeline_snapshot;
