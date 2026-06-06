# Customer Segmentation & Retention Analysis

Analysing customer behaviour for a UK-based online retailer to identify high-value segments, flag churn risk, and track retention patterns across acquisition cohorts.

| Metric | Value |
|---|---|
| Total Customers | 4,338 |
| Total Revenue | £8.91M |
| Churn Rate | 33.4% |
| Avg Customer LTV | £2.05K |
| Avg Month 1 Retention | 20.62% |

---

##  Executive Summary

This project uses transactional data from a UK-based online retailer (December 2010 – December 2011) to answer three core business questions:

- **Who are our most valuable customers** and what share of revenue do they drive?
- **Which customers are at risk of churning** and how much revenue is at stake?
- **When do customers drop off** and which acquisition cohorts perform best?

Using SQL Server for data preparation and Power BI for visualisation, the analysis segments 4,338 customers using RFM (Recency, Frequency, Monetary) scoring, tracks cohort retention month-by-month, and surfaces £1.04M in revenue at risk from churned customers.

The dashboard consists of 3 report pages — Overview, Customer Segmentation, and Cohort Retention — with 18 custom DAX measures and an interactive tooltip page.

---

##  Business Problem

A UK-based online retailer has no visibility into which customers are most valuable, which are disengaging, or whether new customers are being retained after their first purchase.

Specific problems this analysis addresses:

- No customer segmentation — all customers treated the same regardless of purchase behaviour
- No churn visibility — the business cannot identify at-risk customers before they are lost
- No cohort tracking — no way to measure whether acquisition quality is improving or declining over time
- Revenue concentration risk — if top customers churn, revenue impact is disproportionate

**Business goal:** Identify high-value segments, quantify churn risk, and surface actionable retention insights to prioritise re-engagement efforts.

---

##  Methodology

### Tools
| Layer | Tool |
|---|---|
| Data storage | SQL Server (SSMS) |
| Data preparation | SQL — T-SQL |
| Visualisation | Power BI Desktop |
| Measures | DAX  |
| Source data | UCI Online Retail Dataset |

### Step 1 — Data Cleaning
Removed null CustomerIDs, cancelled orders (InvoiceNo starting with `C`), and rows with negative quantities or zero prices. Created a `TotalPrice` derived column.

```sql
SELECT
    InvoiceNo, StockCode, Description, Quantity,
    InvoiceDate, UnitPrice, CustomerID, Country,
    Quantity * UnitPrice AS TotalPrice
INTO online_retail_clean
FROM online_retail
WHERE CustomerID IS NOT NULL
    AND Quantity > 0
    AND UnitPrice > 0
    AND InvoiceNo NOT LIKE 'C%';
```

### Step 2 — RFM Calculation
Recency, Frequency, and Monetary values were calculated per customer. The reference date was set dynamically as one day after the last transaction — making the query reusable across any date range.

```sql
SELECT
    CustomerID,
    MAX(InvoiceDate)                                                AS last_purchase_date,
    COUNT(DISTINCT InvoiceNo)                                       AS frequency,
    ROUND(SUM(TotalPrice), 2)                                       AS monetary,
    DATEDIFF(day, MAX(InvoiceDate),
        DATEADD(day, 1, (SELECT MAX(InvoiceDate)
                         FROM online_retail_clean)))                AS recency_days
INTO rfm
FROM online_retail_clean
GROUP BY CustomerID;
```

### Step 3 — RFM Scoring & Segmentation
Each customer was scored 1–5 on each RFM dimension using `NTILE` window functions, then assigned a segment label and churn flag.

```sql
-- Scoring
NTILE(5) OVER (ORDER BY recency_days ASC)  AS r_score,
NTILE(5) OVER (ORDER BY frequency DESC)   AS f_score,
NTILE(5) OVER (ORDER BY monetary DESC)    AS m_score,

-- Segment labels
CASE
    WHEN r_score >= 4 AND f_score >= 4  THEN 'Champion'
    WHEN r_score >= 3 AND f_score >= 3  THEN 'Loyal Customer'
    WHEN r_score >= 3 AND f_score < 3   THEN 'Potential Loyalist'
    WHEN r_score >= 2 AND f_score >= 2  THEN 'Needs Attention'
    WHEN r_score <= 2 AND f_score >= 3  THEN 'At Risk'
    WHEN r_score = 1                    THEN 'Lost Customer'
    ELSE 'New Customer'
END AS rfm_segment,

-- Churn label: no purchase in last 90 days
CASE WHEN recency_days > 90 THEN 'Churned' ELSE 'Active' END AS churn_label
```

### Step 4 — Cohort Retention
Each customer's first purchase month was identified as their acquisition cohort. Monthly activity and revenue were tracked per customer to calculate month-by-month retention rates.

```sql
-- First purchase month (acquisition cohort)
SELECT CustomerID,
    DATEFROMPARTS(YEAR(MIN(InvoiceDate)), MONTH(MIN(InvoiceDate)), 1) AS cohort_month
FROM online_retail_clean
GROUP BY CustomerID

-- Month number since acquisition
DATEDIFF(month, f.cohort_month, m.activity_month) AS month_number
```

### Data Model
Three tables imported into Power BI with `customer_segments` as the central table:

```
online_retail_clean[CustomerID]  →  customer_segments[CustomerID]  (Many-to-one)
cohort_data[CustomerID]          →  customer_segments[CustomerID]  (Many-to-one)
```

---

##  Skills

| Category | Skills Demonstrated |
|---|---|
| SQL | Data cleaning, window functions (NTILE), CTEs, DATEDIFF, DATEADD, DATEFROMPARTS, conditional logic |
| Power BI | Data modelling, relationships, page navigation, conditional formatting, tooltip pages, matrix heatmap |
| DAX | CALCULATE, ALLSELECTED, REMOVEFILTERS, ALLEXCEPT, DIVIDE, TOPN, MAXX, FIRSTNONBLANK, filter context management |
| Analytics | RFM segmentation, cohort analysis, churn analysis, customer lifetime value |
| Storytelling | 3-page dashboard with business-framed insights, segment colour coding, heatmap visualisation |



---

##  Results & Business Recommendations

### Results

| Finding | Detail |
|---|---|
| Champions drive outsized revenue | 7.95% of customers → 43.72% of revenue (£3.9M) |
| Significant churn risk | 33.4% churn rate · £1.04M revenue at risk |
| Revenue concentration | Top 3 cohorts account for majority of total cohort revenue |
| Weak early retention | Avg Month 1 retention = 20.62% · 8 in 10 customers don't return |
| Declining acquisition quality | Cohorts from Jul–Nov 2011 show consistently lower M1 retention (11–18%) vs earlier cohorts (22–37%) |
| Stagnant net growth | Lost Customers (624) ≈ New Customers (478) — replacing churn not growing |

### Business Recommendations

**1. Protect Champions immediately**
Champions are only 7.95% of the base but generate 43.72% of revenue. A targeted VIP retention programme — early access, personalised outreach, loyalty incentives — would have the highest revenue impact per customer of any segment.

**2. Re-engage At Risk customers within 60 days**
At Risk customers (771, £0.9M) have purchase history but are showing disengagement signals. A time-limited re-engagement campaign (discount, personalised recommendation) targeting customers at 60 days of inactivity — before they cross the 90-day churn threshold — could recover a meaningful portion of this revenue.

**3. Focus on the first 30 days post-acquisition**
Average Month 1 retention is only 20.62% — the steepest drop in the entire customer lifecycle. An onboarding sequence (welcome email, product recommendations, follow-up at day 14) targeting new customers in their first 30 days would have the highest retention ROI.

**4. Investigate acquisition quality decline**
M1 retention for cohorts acquired in Jul–Nov 2011 dropped to 11–18%, well below the 22–37% seen in earlier cohorts. This warrants a review of acquisition channels, campaign quality, and product-market fit for customers acquired in the second half of 2011.

**5. Shift budget from acquisition to retention**
Lost Customers (624) and New Customers (478) are nearly equal — the business is replacing churned customers rather than growing. Shifting a portion of acquisition spend toward retention and re-engagement would improve net customer growth without increasing total spend.

---

##  Next Steps

- **Predictive churn model** — use Python (logistic regression or random forest) to predict churn probability per customer before the 90-day threshold, enabling proactive rather than reactive intervention
- **Marketing channel attribution** — connect acquisition channel data to cohort retention rates to identify which channels produce the highest LTV customers
- **Product-level analysis** — identify which product categories drive repeat purchase behaviour and correlate with Champion segment membership
- **Automated refresh** — connect Power BI to a live SQL Server database for automated monthly refresh of all three report pages



