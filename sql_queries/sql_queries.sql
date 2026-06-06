
-- ============================================================
-- STEP 1: DATA CLEANING
-- Removes invalid records from the raw dataset and creates
-- a clean working table for all downstream analysis.
-- Exclusions:
--   - NULL CustomerIDs (cannot do customer-level analysis)
--   - Negative or zero quantities (returns and adjustments)
--   - Zero unit prices (admin/test rows)
--   - Cancelled orders (InvoiceNo starting with 'C')
-- Derived column: TotalPrice = Quantity * UnitPrice
-- ============================================================

SELECT
    InvoiceNo,
    Quantity,
    InvoiceDate,
    UnitPrice,
    CustomerID,
    Quantity * UnitPrice AS TotalPrice
INTO online_retail
FROM OnlineRetail
WHERE
    CustomerID IS NOT NULL
    AND Quantity > 0
    AND UnitPrice > 0
    AND InvoiceNo NOT LIKE 'C%';



-- ============================================================
-- STEP 2: RFM CALCULATION
-- Computes three behavioural metrics per customer:
--   - Recency:   days since last purchase (lower = more recent)
--   - Frequency: number of distinct invoices (orders placed)
--   - Monetary:  total spend across all transactions
--
-- Reference date is set dynamically as one day after the
-- last transaction in the dataset so the query remains
-- reusable without manual date updates.
-- ============================================================

SELECT
    CustomerID,
    MAX(InvoiceDate)                                        AS last_purchase_date,
    COUNT(DISTINCT InvoiceNo)                               AS frequency,
    ROUND(SUM(TotalPrice), 2)                               AS monetary,
    DATEDIFF(day, 
            MAX(InvoiceDate), 
            DATEADD(day, 1, (SELECT MAX(InvoiceDate) FROM online_retail))
            ) AS recency_days
INTO rfm
FROM online_retail
GROUP BY CustomerID;



-- ============================================================
-- STEP 3: RFM SCORING AND SEGMENTATION
-- Scores each customer 1-5 on each RFM dimension using
-- NTILE window functions:
--   - R score: higher score = purchased more recently
--   - F score: higher score = purchases more frequently
--   - M score: higher score = spends more
--
-- Scores are combined into a 3-digit rfm_score string
-- (e.g. 555 = top customer across all dimensions).
--
-- Segment labels are assigned using conditional logic
-- based on R and F score combinations. M score is used
-- for revenue analysis but not segment assignment since
-- recency and frequency are stronger behavioural signals.
--
-- Churn label: customers with no purchase in the last
-- 90 days are flagged as churned (1), others as active (0).
-- ============================================================

WITH rfm_scores AS (
    SELECT
        CustomerID,
        last_purchase_date,
        recency_days,
        frequency,
        monetary,
        -- Lower recency_days = better = higher score
        NTILE(5) OVER (ORDER BY recency_days DESC)  AS r_score,
        -- Higher frequency = better = higher score
        NTILE(5) OVER (ORDER BY frequency ASC)    AS f_score,
        -- Higher monetary = better = higher score
        NTILE(5) OVER (ORDER BY monetary ASC)     AS m_score
    FROM rfm
),

rfm_segments AS (
    SELECT
        *,
        -- Concatenate scores into a single reference string
        CAST(r_score AS VARCHAR) + 
        CAST(f_score AS VARCHAR) + 
        CAST(m_score AS VARCHAR)          AS rfm_score,

        -- Average spend per order
        ROUND((monetary / frequency), 2)  AS avg_order_value,

        -- Segment assignment based on R and F score thresholds
        -- Priority order matters: more specific conditions first
        CASE
            WHEN r_score = 5 AND f_score = 5 AND m_score = 5 
                THEN 'Champion'                     -- Top performers across all dimensions
            WHEN r_score >= 4 AND f_score >= 4 
                THEN 'Loyal Customer'               -- High recency and frequency
            WHEN r_score >= 3 AND f_score >= 3  
                THEN 'Potential Loyalist'           -- Moderate engagement, growth potential
            WHEN r_score >= 4 AND f_score <= 2 
                THEN 'New Customer'                 -- Recent but low frequency (early stage)
            WHEN r_score <= 2 AND f_score >= 3 
                THEN 'At Risk'                      -- Previously frequent, now disengaging
            WHEN r_score = 1 AND f_score = 1            
                THEN 'Lost Customer'                -- Long inactive, low historical engagement
            ELSE 'Needs Attention'
        END AS rfm_segment

    FROM rfm_scores
)

SELECT
    CustomerID,
    last_purchase_date,
    recency_days,
    frequency,
    monetary,
    avg_order_value,
    r_score,
    f_score,
    m_score,
    rfm_score,
    rfm_segment,

    -- Churn flag: 1 = churned (>90 days inactive), 0 = active
    CASE
        WHEN recency_days > 90 THEN 1
        ELSE 0
    END AS churned

INTO customer_segments
FROM rfm_segments;




-- ============================================================
-- STEP 4: COHORT RETENTION TABLE
-- Tracks each customer's monthly purchasing activity from
-- the month they first purchased (their acquisition cohort).
--
-- Three CTEs:
--   first_purchase:    identifies each customer's cohort month
--   monthly_activity:  aggregates revenue per customer per month
--   cohort_data:       joins the two and calculates month number
--                      (months elapsed since acquisition)
--
-- month_number = 0 means the acquisition month itself.
-- month_number = 1 means one month after acquisition, etc.
--
-- monthly_revenue is included to enable cohort revenue
-- analysis in Power BI without needing additional joins.
-- ============================================================


WITH first_purchase AS (
    -- Identify each customer's first purchase month
    -- DATEFROMPARTS normalises to the 1st of the month
    -- so all cohort comparisons are on a clean monthly grain
    SELECT
        CustomerID,
        DATEFROMPARTS(
            YEAR(MIN(InvoiceDate)),
            MONTH(MIN(InvoiceDate)),
            1
        )                          AS cohort_month
    FROM online_retail_clean
    GROUP BY CustomerID
),

monthly_activity AS (
    -- Aggregate all transactions to one row per customer
    -- per calendar month, summing revenue for that month
    SELECT
        CustomerID,
        DATEFROMPARTS(
            YEAR(InvoiceDate),
            MONTH(InvoiceDate),
            1
        )                                    AS activity_month,
        SUM(TotalPrice)                      AS monthly_revenue
    FROM online_retail
    GROUP BY 
        CustomerID,
        DATEFROMPARTS(
            YEAR(InvoiceDate),
            MONTH(InvoiceDate),
            1
        )
),

cohort_data AS (
    -- Join acquisition month to all subsequent activity months
    -- DATEDIFF calculates how many months after acquisition
    -- each activity occurred (month_number)
    SELECT
        f.CustomerID,
        f.cohort_month,
        DATEDIFF(month, f.cohort_month, m.activity_month) AS month_number,
        m.monthly_revenue
    FROM first_purchase f
    JOIN monthly_activity m ON f.CustomerID = m.CustomerID
)

SELECT
    CustomerID,
    cohort_month,
    month_number,
    monthly_revenue
INTO cohort_data
FROM cohort_data;


