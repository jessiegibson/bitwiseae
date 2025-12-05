# Analytics Engineer - Take Home Exercise

Marketing and Sales want a clear and trustworthy view of how paid channels drive web traffic and impact our sales pipeline.

We’ve shared three CSVs with this exercise:
- `ad_spend.csv` — ad performance by channel/campaign
- `web_analytics.csv` — web sessions and conversions
- `salesforce_opportunities.csv` — opportunities and revenue

They’re simplified, but roughly represent the kinds of data you’d see in a GTM stack.

## The scenario

In a few hours, show us how you’d start building a GTM funnel mart, what insights you'd surface from it, and how you'd communicate this back to stakeholders.

We’re especially interested in your decisions about:
- Data modeling and architecture
- How you define and connect stages of the GTM funnel
- What insights you think are important and how you’d communicate this back to stakeholders

### What to do

You don’t need to build a full production system. Focus on the parts that best showcase your judgment and approach.

We’d like you to:
1. Frame the problem & key questions — Briefly describe (a few bullet points is fine):
   - What business questions you think Marketing / Sales care about first
   - Which parts of the on (e.g., channel performance, conversion to opps, ROI)
2. Propose a dimensional model — Design a simple data model that could power ongoing GTM reporting.   
   For example:
   - 1–2 fact tables (e.g., channel funnel, opportunities)
   - A few key dimensions (e.g., date, channel, campaign)  
   Please include:
   - A diagram or sketch (screenshot / drawn / tool of your choice)
   - A short explanation of grains (what a “row” represents) and how tables join
3. Implement part of the model in code  
   Using any tools you like (SQL, dbt-style SQL, a notebook, etc.), implement a slice of your model. For example:
   - Build a “funnel” table/view that rolls up, by channel:
     - spend, clicks, sessions, conversions, closed-won opps, revenue, and ROI
   - Or build a set of queries that clearly demonstrate how you’d get those metrics. 
   - What you’d prioritize next if you had more time (e.g., tests, new sources, modeling changes; a few bullet points is fine)
4. Define core GTM metrics  
   Choose a handful of metrics you think are most important for GTM leadership (e.g., ROI by channel, cost per opportunity, funnel conversion rates). For each:
   - Name and definition of metric
   - How you would calculate it (in SQL or pseudo-SQL)
5. Show us the outputs & story  
   Create 2–3 simple views of the data (tables or charts) that you’d show to Marketing/Sales to explain what’s happening. These don’t need to be perfect; screenshots from a notebook, BI tool, or spreadsheet are fine, could even build a quick AI dashboard prototype.  
   Alongside the visuals, include a short narrative covering:
   - The key insights you've uncovered from the data
   - Any assumptions or limitations of your analysis
   
You do not need to over-engineer environment setup (Docker, CI, etc.). We care more about your thinking, modeling decisions, and visualization.

### What to submit

Please submit your final output in a public git repository (github preferrred), which should contain:

- Your code:
  - SQL files, dbt project, or notebook(s) — (step 3,4)
- A short technical write-up
    - Architectural decisions and rationale — (step 1)
    - Dimensional model diagram — (step 2)
    - Metric definitions — (step 2)
    - What you’d prioritize next if you had more time — (step 3)
- A brief narrative for the Head of Sales Operations and Head of Growth
  - A short summary of your insights (can be video or written) - (step 4)
  - 2-3 key views (charts, tables, dashboards) — (step 5)
