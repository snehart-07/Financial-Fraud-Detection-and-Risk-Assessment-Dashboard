/* =====================================================================
   Fraud Risk Analytics - business questions (MySQL 8)

   Q1  Monthly fraud trend
   Q2  Country risk ranking
   Q3  Channel exposure
   Q4  Top customers by fraudulent value
   Q5  Repeat-fraud customers (2+ frauds)
   Q6  Customer transaction velocity
   Q7  Rapid vs. normal transactions
   Q8  Behavioural risk-score effectiveness
   Q9  Fraud value concentration
   ML  customer_ml_features build + export

   Note: is_fraud is a 0/1 flag, so amount * is_fraud is the fraudulent
   share of a row's amount (exact DECIMAL arithmetic).
   ===================================================================== */

USE financial_fraud_analytics;


-- Q1 ------------------------------------------------------------------
-- Monthly fraud trend
WITH monthly AS (
    SELECT
        transaction_year,
        transaction_month,
        COUNT(*)                AS txn_count,
        SUM(is_fraud)           AS fraud_count,
        SUM(amount)             AS gross_value,
        SUM(amount * is_fraud)  AS fraud_value
    FROM transactions
    GROUP BY transaction_year, transaction_month
)
SELECT
    transaction_year,
    transaction_month,
    txn_count                                   AS total_transactions,
    fraud_count                                 AS fraud_transactions,
    ROUND(fraud_count * 100.0 / txn_count, 2)   AS fraud_rate,
    ROUND(gross_value, 2)                       AS total_transaction_value,
    ROUND(fraud_value, 2)                       AS fraudulent_transaction_value
FROM monthly
ORDER BY transaction_year, transaction_month;


-- Q2 ------------------------------------------------------------------
-- Country risk ranking (ranked on the 2-dp fraud rate)
SELECT
    country,
    total_transactions,
    fraud_transactions,
    fraud_rate,
    fraudulent_value,
    RANK() OVER by_rate AS fraud_rate_rank
FROM (
    SELECT
        country,
        COUNT(*)                                    AS total_transactions,
        SUM(is_fraud)                               AS fraud_transactions,
        ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 2)  AS fraud_rate,
        ROUND(SUM(amount * is_fraud), 2)            AS fraudulent_value
    FROM transactions
    GROUP BY country
) AS country_stats
WINDOW by_rate AS (ORDER BY fraud_rate DESC)
ORDER BY fraud_rate_rank;


-- Q3 ------------------------------------------------------------------
-- Channel exposure
SELECT
    channel,
    total_transactions,
    fraud_transactions,
    ROUND(fraud_transactions * 100.0 / total_transactions, 2)  AS fraud_rate,
    ROUND(gross_value, 2)                                      AS total_value,
    ROUND(fraud_value, 2)                                      AS fraudulent_value
FROM (
    SELECT
        channel,
        COUNT(*)                AS total_transactions,
        SUM(is_fraud)           AS fraud_transactions,
        SUM(amount)             AS gross_value,
        SUM(amount * is_fraud)  AS fraud_value
    FROM transactions
    GROUP BY channel
) AS channel_stats
ORDER BY fraud_rate DESC;


-- Q4 ------------------------------------------------------------------
-- Top 25 customers by fraudulent value (ranked on the 2-dp value)
WITH per_customer AS (
    SELECT
        customer_id,
        COUNT(*)                            AS total_transactions,
        SUM(is_fraud)                       AS fraud_transactions,
        ROUND(SUM(amount), 2)               AS total_transaction_value,
        ROUND(SUM(amount * is_fraud), 2)    AS fraudulent_value
    FROM transactions
    GROUP BY customer_id
)
SELECT
    customer_id,
    total_transactions,
    fraud_transactions,
    ROUND(fraud_transactions * 100.0 / total_transactions, 2)  AS fraud_rate,
    total_transaction_value,
    fraudulent_value,
    RANK() OVER (ORDER BY fraudulent_value DESC)                AS fraud_value_rank
FROM per_customer
ORDER BY fraud_value_rank
LIMIT 25;


-- Q5 ------------------------------------------------------------------
-- Repeat-fraud customers: two or more fraudulent transactions
WITH fraud_only AS (
    SELECT customer_id, amount
    FROM transactions
    WHERE is_fraud = 1
),
repeat_offenders AS (
    SELECT
        customer_id,
        COUNT(*)        AS fraud_transactions,
        SUM(amount)     AS fraud_total,
        AVG(amount)     AS fraud_avg,
        MAX(amount)     AS fraud_max
    FROM fraud_only
    GROUP BY customer_id
    HAVING COUNT(*) > 1
)
SELECT
    customer_id,
    fraud_transactions,
    ROUND(fraud_total, 2)                       AS fraudulent_value,
    ROUND(fraud_avg, 2)                         AS average_fraud_amount,
    ROUND(fraud_max, 2)                         AS largest_fraud_amount,
    RANK() OVER (ORDER BY fraud_total DESC)     AS fraud_exposure_rank
FROM repeat_offenders
ORDER BY fraud_exposure_rank;


-- Q6 ------------------------------------------------------------------
-- Customer transaction velocity (24h rolling count), top 25
WITH velocity AS (
    SELECT
        customer_id,
        COUNT(*)                            AS total_transactions,
        COUNT(DISTINCT DATE(transaction_date)) AS active_days,
        SUM(amount)                         AS gross_value,
        AVG(transaction_count_24h)          AS avg_24h,
        MAX(transaction_count_24h)          AS max_24h
    FROM transactions
    GROUP BY customer_id
)
SELECT
    customer_id,
    total_transactions,
    active_days,
    ROUND(gross_value, 2)                   AS total_transaction_value,
    ROUND(avg_24h, 2)                       AS average_24h_transaction_count,
    max_24h                                 AS maximum_24h_transaction_count,
    RANK() OVER (ORDER BY max_24h DESC)     AS velocity_rank
FROM velocity
ORDER BY velocity_rank
LIMIT 25;


-- Q7 ------------------------------------------------------------------
-- Rapid (<= 5 min since previous) vs. normal transactions
SELECT
    is_rapid_transaction,
    COUNT(*)                                    AS total_transactions,
    SUM(is_fraud)                               AS fraud_transactions,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 2)  AS fraud_rate,
    ROUND(SUM(amount), 2)                       AS total_transaction_value,
    ROUND(SUM(amount * is_fraud), 2)            AS fraudulent_value
FROM transactions
GROUP BY is_rapid_transaction
ORDER BY is_rapid_transaction DESC;


-- Q8 ------------------------------------------------------------------
-- Does a higher behavioural risk score mean a higher fraud rate?
SELECT
    behavioural_risk_score,
    COUNT(*)                                    AS total_transactions,
    SUM(is_fraud)                               AS fraud_transactions,
    ROUND(SUM(is_fraud) * 100.0 / COUNT(*), 2)  AS fraud_rate,
    ROUND(AVG(amount), 2)                       AS average_transaction_amount,
    ROUND(SUM(amount), 2)                       AS total_transaction_value,
    ROUND(SUM(amount * is_fraud), 2)            AS fraudulent_value
FROM transactions
GROUP BY behavioural_risk_score
ORDER BY behavioural_risk_score;


-- Q9 ------------------------------------------------------------------
-- Fraud value concentration: share of all fraud value held by each of
-- the top 25 customers (ranking includes every customer, zero-fraud
-- customers are filtered out afterwards)
WITH customer_fraud_value AS (
    SELECT customer_id, SUM(amount * is_fraud) AS fraud_value
    FROM transactions
    GROUP BY customer_id
),
ranked AS (
    SELECT
        customer_id,
        fraud_value,
        RANK() OVER (ORDER BY fraud_value DESC) AS fraud_rank,
        SUM(fraud_value) OVER ()                AS portfolio_fraud_value
    FROM customer_fraud_value
)
SELECT
    customer_id,
    ROUND(fraud_value, 2)                                               AS fraudulent_value,
    fraud_rank,
    ROUND(fraud_value * 100.0 / NULLIF(portfolio_fraud_value, 0), 2)    AS percentage_of_total_fraud_value
FROM ranked
WHERE fraud_value > 0
ORDER BY fraud_rank
LIMIT 25;


-- ML ------------------------------------------------------------------
-- Customer-level feature table consumed by Notebooks/Fraud_Detection_ML.ipynb
DROP TABLE IF EXISTS customer_ml_features;

CREATE TABLE customer_ml_features AS
SELECT
    customer_id,
    -- activity
    COUNT(*)                                AS total_transactions,
    COUNT(DISTINCT DATE(transaction_date))  AS active_days,
    -- monetary
    SUM(amount)                             AS total_transaction_value,
    AVG(amount)                             AS average_transaction_amount,
    MAX(amount)                             AS maximum_transaction_amount,
    -- label history (target source, excluded from model features)
    SUM(is_fraud)                           AS historical_fraud_transactions,
    AVG(is_fraud)                           AS historical_fraud_rate,
    -- velocity
    AVG(transaction_count_24h)              AS average_transaction_velocity,
    MAX(transaction_count_24h)              AS maximum_transaction_velocity,
    -- behaviour counts
    SUM(is_rapid_transaction)               AS rapid_transaction_count,
    SUM(is_amount_anomaly)                  AS amount_anomaly_count,
    SUM(is_international)                   AS international_transaction_count,
    SUM(is_digital)                         AS digital_transaction_count,
    -- behavioural risk
    AVG(behavioural_risk_score)             AS average_behavioural_risk_score,
    MAX(behavioural_risk_score)             AS maximum_behavioural_risk_score
FROM transactions
GROUP BY customer_id;

-- sanity check + preview
SELECT COUNT(*) AS customer_count FROM customer_ml_features;
SELECT * FROM customer_ml_features LIMIT 10;

-- full extract -> Dataset/Processed/customer_ml_features.csv
SELECT * FROM customer_ml_features;
