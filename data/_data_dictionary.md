# Data Dictionary

## 1. `ad_spend.csv`

**Description**  
Daily advertising performance at the campaign level across multiple channels.

| Column         | Type    | Description                                                                                   | Example            |
|----------------|---------|-----------------------------------------------------------------------------------------------|--------------------|
| `date`         | date    | Calendar date of the ad activity.                                                            | `2025-09-01`       |
| `campaign_id`  | string  | Unique identifier for the ad campaign in the ad platform.                                    | `CAMP_GA_BRAND_Q3` |
| `channel`      | string  | Human-readable marketing channel name.                                                       | `Google Ads`       |
| `utm_source`   | string  | UTM source used for tracking; often maps to the platform name.                               | `google`           |
| `utm_campaign` | string  | UTM campaign name or slug.                                                                   | `brand-q3`         |
| `spend_usd`    | numeric | Advertising spend in USD for this campaign on this date.                                     | `4000.00`          |
| `clicks`       | integer | Number of ad clicks recorded for this campaign on this date.                                 | `10000`            |
| `impressions`  | integer | Number of ad impressions recorded for this campaign on this date.                            | `180000`           |

**Key relationships / notes**

- `utm_source` and `utm_campaign` can be joined to `web_analytics_sessions` to connect ad activity to web sessions.
- `channel` aligns conceptually with `salesforce_opportunities.source` for high-level attribution.

---

## 2. `web_analytics_sessions.csv`

**Description**  
Session-level web analytics data representing site visits and conversion events.

| Column         | Type    | Description                                                                                | Example        |
|----------------|---------|--------------------------------------------------------------------------------------------|----------------|
| `session_id`   | string  | Unique identifier for a web session.                                                       | `S001`         |
| `user_id`      | string  | Pseudonymous identifier for the user or browser.                                          | `U001`         |
| `session_date` | date    | Calendar date on which the session occurred.                                              | `2025-09-01`   |
| `landing_page` | string  | URL path of the first page in the session.                                                | `/pricing`     |
| `utm_source`   | string  | UTM source captured on the session (if present).                                          | `google`       |
| `utm_campaign` | string  | UTM campaign captured on the session (if present).                                        | `brand-q3`     |
| `pageviews`    | integer | Total number of pageviews within the session.                                             | `4`            |
| `conversions`  | integer | Count of conversion events in the session (e.g., form submits, demo requests).           | `1`            |

**Key relationships / notes**

- `utm_source` and `utm_campaign` can be used to relate sessions back to `ad_spend`.
- Some sessions may have `NULL` UTM values (e.g., direct or untracked traffic).
- `utm_source` values like `google`, `linkedin`, `facebook` can be mapped to ad `channel`s (e.g., `Google Ads`, `LinkedIn`, `Meta`).

---

## 3. `salesforce_opportunities.csv`

**Description**  
Opportunity-level CRM data approximating a Salesforce Opportunities export.

| Column           | Type    | Description                                                                                 | Example         |
|------------------|---------|---------------------------------------------------------------------------------------------|-----------------|
| `opportunity_id` | string  | Unique identifier for the opportunity.                                                      | `OPP001`        |
| `account_id`     | string  | Identifier for the associated account.                                                      | `ACCT001`       |
| `created_date`   | date    | Date the opportunity was created.                                                           | `2025-09-05`    |
| `stage`          | string  | Current stage of the opportunity (e.g., pipeline vs closed).                                | `Closed Won`    |
| `amount_usd`     | numeric | Revenue amount associated with the opportunity (0 for lost or non-revenue stages).         | `25000.00`      |
| `source`         | string  | High-level source or channel attribution for the opportunity.                              | `Google Ads`    |
| `owner_region`   | string  | Region or territory of the opportunity owner.                                              | `North America` |

**Key relationships / notes**

- `source` conceptually aligns with `ad_spend.channel` for high-level attribution (e.g., `Google Ads`, `LinkedIn`, `Meta`, `Organic`, `Direct`).
- `stage` may include values such as `Closed Won`, `Closed Lost`, `Pipeline`; revenue/ROI analyses typically focus on `Closed Won`.
- Time-based analyses may use `created_date` alongside ad and web dates, with some lag between marketing activity and opportunity creation.
