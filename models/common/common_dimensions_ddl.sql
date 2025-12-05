-- ============================================
-- COMMON DIMENSIONS SCHEMA DDL
-- Shared dimension tables used across all marts
-- ============================================

-- Create schema
CREATE SCHEMA IF NOT EXISTS common;

-- ============================================
-- DIMENSION: dim_date
-- Standard date dimension for time-based analysis
-- Used by: sales_mart, marketing_mart
-- ============================================

CREATE OR REPLACE TABLE common.dim_date (
    date_key            INTEGER PRIMARY KEY,          -- YYYYMMDD format (surrogate key)
    date_actual         DATE NOT NULL UNIQUE,         -- Actual date value

    -- Day attributes
    day_of_week         INTEGER,                      -- 0=Sunday, 6=Saturday
    day_of_week_iso     INTEGER,                      -- 1=Monday, 7=Sunday (ISO standard)
    day_name            VARCHAR(10),                  -- 'Monday', 'Tuesday', etc.
    day_name_short      VARCHAR(3),                   -- 'Mon', 'Tue', etc.
    day_of_month        INTEGER,                      -- 1-31
    day_of_year         INTEGER,                      -- 1-366

    -- Week attributes
    week_of_year        INTEGER,                      -- 1-53
    week_of_year_iso    INTEGER,                      -- ISO week number
    week_start_date     DATE,                         -- Monday of the week
    week_end_date       DATE,                         -- Sunday of the week

    -- Month attributes
    month_actual        INTEGER,                      -- 1-12
    month_name          VARCHAR(10),                  -- 'January', 'February', etc.
    month_name_short    VARCHAR(3),                   -- 'Jan', 'Feb', etc.
    month_start_date    DATE,                         -- First day of month
    month_end_date      DATE,                         -- Last day of month

    -- Quarter attributes
    quarter_actual      INTEGER,                      -- 1-4
    quarter_name        VARCHAR(10),                  -- 'Q1', 'Q2', 'Q3', 'Q4'
    quarter_start_date  DATE,                         -- First day of quarter
    quarter_end_date    DATE,                         -- Last day of quarter

    -- Year attributes
    year_actual         INTEGER,                      -- e.g., 2025
    year_month          VARCHAR(7),                   -- 'YYYY-MM' format
    year_quarter        VARCHAR(7),                   -- 'YYYY-Q#' format

    -- Fiscal period (assuming calendar year = fiscal year)
    fiscal_year         INTEGER,
    fiscal_quarter      INTEGER,

    -- Flags
    is_weekend          BOOLEAN,
    is_weekday          BOOLEAN,
    is_month_start      BOOLEAN,
    is_month_end        BOOLEAN,
    is_quarter_start    BOOLEAN,
    is_quarter_end      BOOLEAN,
    is_year_start       BOOLEAN,
    is_year_end         BOOLEAN
);

-- ============================================
-- DIMENSION: dim_channel
-- Marketing channel dimension with UTM mapping
-- Used by: sales_mart, marketing_mart
-- ============================================

CREATE OR REPLACE TABLE common.dim_channel (
    channel_key         INTEGER PRIMARY KEY AUTOINCREMENT,  -- Surrogate key
    channel_id          VARCHAR(50) NOT NULL UNIQUE,        -- Business key (e.g., 'google_ads')
    channel_name        VARCHAR(50) NOT NULL,               -- Display name (e.g., 'Google Ads')
    channel_category    VARCHAR(50) NOT NULL,               -- 'Paid Search', 'Paid Social', 'Organic', 'Direct'
    channel_group       VARCHAR(50),                        -- Higher level grouping: 'Paid', 'Organic', 'Direct'

    -- UTM mapping for attribution
    utm_source          VARCHAR(50),                        -- e.g., 'google', 'facebook', 'linkedin'

    -- Channel characteristics
    is_paid             BOOLEAN NOT NULL DEFAULT FALSE,
    is_digital          BOOLEAN NOT NULL DEFAULT TRUE,

    -- Display order for reports
    sort_order          INTEGER,

    -- Metadata
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================
-- DIMENSION: dim_campaign
-- Campaign dimension with channel relationship
-- Used by: sales_mart, marketing_mart
-- ============================================

CREATE OR REPLACE TABLE common.dim_campaign (
    campaign_key        INTEGER PRIMARY KEY AUTOINCREMENT,  -- Surrogate key
    campaign_id         VARCHAR(100) NOT NULL UNIQUE,       -- Natural key from ad platforms
    campaign_name       VARCHAR(255),                       -- Human-readable name

    -- Channel relationship
    channel_key         INTEGER NOT NULL,                   -- FK to dim_channel

    -- UTM parameters
    utm_campaign        VARCHAR(100),                       -- UTM campaign parameter
    utm_source          VARCHAR(50),                        -- UTM source (redundant but useful)

    -- Campaign attributes (can be expanded)
    campaign_type       VARCHAR(50),                        -- 'Brand', 'Performance', 'Retargeting', etc.
    campaign_objective  VARCHAR(50),                        -- 'Awareness', 'Consideration', 'Conversion'

    -- Date range
    start_date          DATE,
    end_date            DATE,

    -- Status
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,

    -- Metadata
    created_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),

    FOREIGN KEY (channel_key) REFERENCES common.dim_channel(channel_key)
);

-- ============================================
-- DIMENSION: dim_landing_page
-- Landing page dimension for web analytics
-- Used by: marketing_mart
-- ============================================

CREATE OR REPLACE TABLE common.dim_landing_page (
    landing_page_key    INTEGER PRIMARY KEY AUTOINCREMENT,  -- Surrogate key
    landing_page_path   VARCHAR(255) NOT NULL UNIQUE,       -- URL path (e.g., '/pricing')

    -- Page categorization
    page_name           VARCHAR(100),                       -- Friendly name
    page_category       VARCHAR(50),                        -- 'Product', 'Content', 'Conversion', 'Homepage'
    page_type           VARCHAR(50),                        -- 'Landing', 'Blog', 'Feature', 'Pricing'

    -- Conversion flags
    is_conversion_page  BOOLEAN DEFAULT FALSE,              -- TRUE for demo, pricing, signup pages
    is_high_intent      BOOLEAN DEFAULT FALSE,              -- TRUE for bottom-funnel pages

    -- Metadata
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================
-- DIMENSION: dim_region
-- Sales region dimension
-- Used by: sales_mart
-- ============================================

CREATE OR REPLACE TABLE common.dim_region (
    region_key          INTEGER PRIMARY KEY AUTOINCREMENT,  -- Surrogate key
    region_code         VARCHAR(10) NOT NULL UNIQUE,        -- 'NA', 'EU', 'APAC'
    region_name         VARCHAR(50) NOT NULL,               -- 'North America', 'Europe', 'APAC'

    -- Geographic hierarchy (can be expanded)
    super_region        VARCHAR(50),                        -- 'Americas', 'EMEA', 'APJ'
    timezone_primary    VARCHAR(50),                        -- Primary timezone for region

    -- Business attributes
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    sort_order          INTEGER,

    -- Metadata
    created_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================
-- DIMENSION: dim_deal_stage
-- Opportunity stage dimension for sales pipeline
-- Used by: sales_mart
-- ============================================

CREATE OR REPLACE TABLE common.dim_deal_stage (
    stage_key           INTEGER PRIMARY KEY AUTOINCREMENT,  -- Surrogate key
    stage_code          VARCHAR(20) NOT NULL UNIQUE,        -- 'pipeline', 'proposal', 'closed_won', 'closed_lost'
    stage_name          VARCHAR(50) NOT NULL,               -- 'Pipeline', 'Proposal', 'Closed Won', 'Closed Lost'

    -- Stage categorization
    stage_category      VARCHAR(20) NOT NULL,               -- 'Open', 'Closed'
    stage_group         VARCHAR(20),                        -- 'Early', 'Mid', 'Late', 'Closed'

    -- Stage flags
    is_closed           BOOLEAN NOT NULL DEFAULT FALSE,
    is_won              BOOLEAN NOT NULL DEFAULT FALSE,
    is_active_pipeline  BOOLEAN NOT NULL DEFAULT TRUE,      -- TRUE for stages in active pipeline

    -- Funnel position (for ordering and reporting)
    stage_order         INTEGER NOT NULL,                   -- 1, 2, 3, 4 for funnel progression
    probability_default DECIMAL(5, 2),                      -- Default win probability (e.g., 25%, 50%, 75%)

    -- Metadata
    is_active           BOOLEAN NOT NULL DEFAULT TRUE,
    created_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    updated_at          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================
-- INDEXES FOR PERFORMANCE
-- ============================================

CREATE INDEX IF NOT EXISTS idx_dim_date_actual ON common.dim_date(date_actual);
CREATE INDEX IF NOT EXISTS idx_dim_date_year_month ON common.dim_date(year_actual, month_actual);
CREATE INDEX IF NOT EXISTS idx_dim_channel_utm_source ON common.dim_channel(utm_source);
CREATE INDEX IF NOT EXISTS idx_dim_campaign_channel ON common.dim_campaign(channel_key);
CREATE INDEX IF NOT EXISTS idx_dim_campaign_utm ON common.dim_campaign(utm_campaign);

-- ============================================
-- COMMENTS FOR DOCUMENTATION
-- ============================================

COMMENT ON TABLE common.dim_date IS 'Standard date dimension for all time-based analyses across marts';
COMMENT ON TABLE common.dim_channel IS 'Marketing channel dimension with UTM mapping for attribution';
COMMENT ON TABLE common.dim_campaign IS 'Campaign dimension linking ad platform campaigns to channels';
COMMENT ON TABLE common.dim_landing_page IS 'Landing page dimension for web session analysis';
COMMENT ON TABLE common.dim_region IS 'Sales region dimension for geographic analysis';
COMMENT ON TABLE common.dim_deal_stage IS 'Opportunity stage dimension for sales pipeline analysis';
