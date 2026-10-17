/* =====================================================================
   Fraud Risk Analytics - warehouse setup & load validation (MySQL 8)

   Run order
     1. Database
     2. Tables
     3. Load preparation  (reset + staging column type)
        -> import Dataset/Processed/financial_transactions_mysql.csv
     4. Post-load clean-up  (\N -> NULL, restore DATETIME)
     5. Integrity checks
   ===================================================================== */


-- ---------------------------------------------------------------------
-- 1. Database
-- ---------------------------------------------------------------------
CREATE DATABASE financial_fraud_analytics;
SHOW DATABASES;
USE financial_fraud_analytics;


-- ---------------------------------------------------------------------
-- 2. Tables
--    Column order of `transactions` mirrors the CSV extract exactly.
-- ---------------------------------------------------------------------
CREATE TABLE transactions (
    -- source attributes
    transaction_id                      VARCHAR(20)     NOT NULL,
    customer_id                         INT,
    transaction_date                    DATETIME,
    transaction_type                    VARCHAR(50),
    channel                             VARCHAR(30),
    country                             VARCHAR(50),
    amount                              DECIMAL(15,2),
    is_fraud                            TINYINT,
    -- calendar features
    transaction_year                    INT,
    transaction_month                   INT,
    transaction_day                     INT,
    day_of_week                         INT,
    day_name                            VARCHAR(20),
    is_weekend                          TINYINT,
    -- transaction risk flags
    is_high_value                       TINYINT,
    is_international                    TINYINT,
    is_digital                          TINYINT,
    is_atm                              TINYINT,
    log_amount                          DECIMAL(15,6),
    -- behavioural / velocity features
    transaction_count_24h               DECIMAL(15,4),
    previous_transaction_date           DATETIME,
    minutes_since_previous_transaction  DECIMAL(15,4),
    is_rapid_transaction                TINYINT,
    amount_z_score                      DECIMAL(15,6),
    is_amount_anomaly                   TINYINT,
    -- composite scores
    risk_score                          INT,
    behavioural_risk_score              INT,

    CONSTRAINT pk_transactions PRIMARY KEY (transaction_id)
);

CREATE TABLE customer_fraud_summary (
    customer_id                 INT             NOT NULL,
    total_transactions          INT,
    total_value                 DECIMAL(15,2),
    average_transaction_value   DECIMAL(15,2),
    maximum_transaction         DECIMAL(15,2),
    fraud_transactions          INT,
    fraud_rate                  DECIMAL(10,2),

    CONSTRAINT pk_customer_fraud_summary PRIMARY KEY (customer_id)
);

CREATE TABLE fraud_predictions (
    transaction_id      VARCHAR(20)     NOT NULL,
    fraud_probability   DECIMAL(10,6),
    fraud_prediction    TINYINT,
    risk_category       VARCHAR(30),
    model_version       VARCHAR(50),

    CONSTRAINT pk_fraud_predictions PRIMARY KEY (transaction_id),
    CONSTRAINT fk_fraud_predictions_transaction
        FOREIGN KEY (transaction_id) REFERENCES transactions (transaction_id)
);


-- ---------------------------------------------------------------------
-- 3. Load preparation
--    a) empty the table so a reload never duplicates rows
--    b) the extract encodes "no previous transaction" as the text \N,
--       so the column is staged as text for the import
-- ---------------------------------------------------------------------
SELECT COUNT(*) AS rows_before_reset FROM transactions;

SET SQL_SAFE_UPDATES = 0;
DELETE FROM transactions;
SET SQL_SAFE_UPDATES = 1;

SELECT COUNT(*) AS rows_after_reset FROM transactions;

ALTER TABLE transactions
    MODIFY COLUMN previous_transaction_date VARCHAR(30);

DESCRIBE transactions;

-- >>> import financial_transactions_mysql.csv into `transactions` here <<<

SELECT
    COUNT(*)                        AS loaded_rows,
    COUNT(DISTINCT transaction_id)  AS distinct_transaction_ids
FROM transactions;


-- ---------------------------------------------------------------------
-- 4. Post-load clean-up: text \N -> real NULL, then restore DATETIME
-- ---------------------------------------------------------------------
SET SQL_SAFE_UPDATES = 0;
UPDATE transactions
   SET previous_transaction_date = NULL
 WHERE previous_transaction_date = '\\N';
SET SQL_SAFE_UPDATES = 1;

SELECT COUNT(*) - COUNT(previous_transaction_date) AS missing_previous_dates
FROM transactions;

ALTER TABLE transactions
    MODIFY COLUMN previous_transaction_date DATETIME NULL;

DESCRIBE transactions;


-- ---------------------------------------------------------------------
-- 5. Integrity checks
-- ---------------------------------------------------------------------
SELECT
    COUNT(*)                                    AS total_transactions,
    COUNT(DISTINCT transaction_id)              AS unique_transactions,
    COUNT(*) - COUNT(previous_transaction_date) AS transactions_without_previous_date
FROM transactions;

SELECT is_fraud, COUNT(*) AS transaction_count
FROM transactions
GROUP BY is_fraud;

SELECT
    COUNT(*)                        AS total_transactions,
    COUNT(DISTINCT customer_id)     AS unique_customers,
    SUM(is_fraud)                   AS fraud_transactions
FROM transactions;
