# Bitwise - Analytics Engineer



## Project Overview

This is an analytics engineer take-home exercise focused on building a GTM (Go-To-Market) funnel data mart. The goal is to connect paid advertising performance with web analytics and Salesforce opportunities to provide Marketing and Sales teams with clear insights into channel effectiveness and ROI.

## Project output
I imported the raw data into Snowflake where I used Snowflake native notebooks to create the tables, execute the data modeling and create the metrics for the output in the [Bitwise Asset Management - Analytics Engineer Deck](https://docs.google.com/presentation/d/1R38NrmnNKqf7zKejovsRivEW7ywHMLqtR5xaMuZWbsg/edit?usp=sharing)

I used Claude Code to Vibe Code examples of Dashboards that you can see on Slides 11-14, 16-19. If the slide has an orange star, the data has not been validated, but using the image to show an example of what the dashboard would look like.

## Data Architecture

I chose to use Star Schema to build models for Marketing and Sales. 

Look here for [Dimensional Model Guide](https://github.com/jessiegibson/bitwiseae/blob/main/DIMENSIONAL_MODEL_GUIDE.md) for detailed information on the dimensional models that were built. 



### Source Data Files (in `data/`)

1. **ad_spend.csv** - Daily advertising performance at campaign level
   - Grain: One row per date + campaign_id
   - Key fields: date, campaign_id, channel, utm_source, utm_campaign, spend_usd, clicks, impressions
   - Channels: Google Ads, Meta, LinkedIn, Twitter

2. **web_analytics.csv** - Session-level web analytics
   - Grain: One row per session_id
   - Key fields: session_id, user_id, session_date, landing_page, utm_source, utm_campaign, pageviews, conversions
   - Note: Some sessions have NULL UTM values (direct/untracked traffic)

3. **salesforce_opportunities.csv** - Opportunity-level CRM data
   - Grain: One row per opportunity_id
   - Key fields: opportunity_id, account_id, created_date, stage, amount_usd, source, owner_region
   - Stages: Closed Won, Closed Lost, Pipeline, Proposal
   - Note: amount_usd is 0 for Closed Lost opportunities

### Critical Join Logic

**Ad Spend → Web Analytics:**
- Join on: `ad_spend.utm_source` = `web_analytics.utm_source` AND `ad_spend.utm_campaign` = `web_analytics.utm_campaign`
- Note: Date alignment may require window/range joins (session_date close to ad date)

**Web Analytics → Salesforce:**
- No direct join key provided - attribution logic needed
- Conceptual: `web_analytics.utm_source` maps to `salesforce_opportunities.source` via channel mapping
- Time lag exists between web session and opportunity creation

**Ad Spend → Salesforce:**
- High-level attribution: `ad_spend.channel` maps to `salesforce_opportunities.source`
- Example mappings: "Google Ads" → "Google Ads", "Meta" → "Meta", "LinkedIn" → "LinkedIn"

## Key Business Requirements

### Exercise Deliverables Structure

The take-home is organized into 5 steps:

1. **Frame the problem** - Define key business questions for Marketing/Sales
2. **Propose dimensional model** - Design fact/dimension tables with diagram and grain explanation
3. **Implement in code** - Build funnel table/queries showing: spend, clicks, sessions, conversions, closed-won opps, revenue, ROI by channel
4. **Define core GTM metrics** - Document metric definitions with SQL/pseudo-SQL
5. **Show outputs & story** - Create 2-3 visualizations with narrative for stakeholders

### Important Metrics to Consider

- **ROI by channel** = (Revenue - Spend) / Spend
- **Cost per opportunity** = Total Spend / Number of Opportunities
- **Funnel conversion rates** - Clicks → Sessions → Conversions → Opportunities → Closed Won
Impression -> Click -> Page View -> Conversion -> Closed Won
- **Customer Acquisition Cost (CAC)** = Spend / Closed Won Opportunities
- **Channel efficiency metrics** - CTR, CPC, conversion rate
- **Pipeline Velocity** - (total opportunities x avg deal size x win rate)/length of sales cycle

## Data Quality & Attribution Challenges

### Known Limitations

1. **Attribution gaps**: No direct session-to-opportunity linkage
2. **Time lag**: Marketing activity → Web session → Opportunity creation may span days/weeks
3. **NULL UTMs**: Direct and organic traffic lacks UTM parameters
4. **Multi-touch attribution**: Data doesn't support last-touch, first-touch, or multi-touch models without assumptions

### Attribution Approach Options

- **Last-touch**: Attribute opportunity to most recent session's source
- **First-touch**: Attribute to first session's source
- **Rule-based**: Match `salesforce_opportunities.source` directly to `ad_spend.channel`
- **Time-window**: Opportunities created within X days of web activity

## Development Approach

### Recommended Tools

- **SQL**: Most appropriate for dimensional modeling and metric calculations
- **dbt**: If building production-style models with tests and documentation
- **Python/Pandas**: For exploratory analysis, data validation, or quick prototyping
- **Jupyter notebooks**: For iterative analysis and visualization

### Analysis Flow

1. **Data profiling** - Understand data quality, cardinality, date ranges
2. **Join validation** - Test UTM matching between ad_spend and web_analytics
3. **Channel mapping** - Create explicit channel dimension with standardized names
4. **Funnel construction** - Build metrics at channel/campaign grain
5. **Attribution logic** - Document assumptions for opportunity → marketing source
6. **ROI calculation** - Connect closed-won revenue back to spend
7. **Visualization** - Create stakeholder-friendly views

### SQL Implementation Pattern

When building the funnel model, follow this structure:

```sql
-- Stage 1: Channel dimension with standardized names
-- Stage 2: Ad performance aggregation
-- Stage 3: Web analytics aggregation with UTM joins
-- Stage 4: Opportunity aggregation by source
-- Stage 5: Funnel fact table joining all stages
```

Ensure grain consistency: likely **channel + time period** (daily or aggregated)

## Common Queries You'll Need

- **Channel performance**: Aggregate spend, clicks, impressions by channel
- **Web funnel**: Sessions, conversions by UTM source/campaign
- **Opportunity pipeline**: Count and revenue by source and stage
- **ROI calculation**: Revenue from Closed Won opportunities / Total ad spend by matching source
- **Conversion metrics**: Click-through rate, session conversion rate, opportunity conversion rate

## What to Prioritize

Given limited time, focus on:

1. **Clear dimensional model** - Well-documented grain and join logic
2. **Core funnel metrics** - Spend → Clicks → Sessions → Conversions → Revenue
3. **ROI by channel** - Critical for Marketing/Sales decision-making
4. **Simple but insightful visualizations** - Tables or charts showing channel effectiveness
5. **Transparent assumptions** - Document attribution logic and data quality limitations

## What's Out of Scope

- Production engineering (Docker, CI/CD, orchestration)
- Advanced multi-touch attribution models
- Real-time data pipelines
- Sophisticated ML/predictive models
- Complete testing frameworks (though basic validation is good)

## Stakeholder Communication

When presenting findings:

- **For Head of Sales Ops**: Focus on opportunity volume, conversion rates, pipeline health by source
- **For Head of Growth**: Focus on channel ROI, CAC, spend efficiency, scale opportunities, CTR, CPM, CPC
- **Use plain language**: Avoid jargon, explain technical terms
- **Show trade-offs**: Be explicit about attribution assumptions and limitations
- **Actionable insights**: "LinkedIn has highest ROI" → "Recommend increasing LinkedIn budget by X%"

## Next Steps 
- **Look at Customer Type** : break down metrics by different customer type. 
- **Mutli-touch** Attribution: Leverage multi-touch attribution to get a better idea as to
