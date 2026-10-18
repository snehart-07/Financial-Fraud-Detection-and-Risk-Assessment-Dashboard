# Fraud Risk Intelligence Platform

## Project Overview

A fraud analytics pipeline that takes a synthetic transaction ledger through feature engineering, MySQL analysis, machine-learning risk scoring and a Power BI monitoring dashboard.

The aim is to show how raw payment data can be turned into fraud signals, model-based risk tiers and a ranked queue that tells investigators where to look first.

## Business Problem

Banks and payment providers handle far more transactions than analysts can review by hand. Fraud is rare, so reviewing everything at random wastes effort on legitimate activity.

The project focuses on these questions:

- How large is fraud in count, rate and value?
- Which channels and countries carry the most fraud exposure?
- Which customers commit fraud repeatedly or behave unusually?
- Do burst activity and outlier amounts signal fraud?
- How well can a model rank fraud risk, and what drives it?
- Which decision threshold balances catching fraud against false alarms?
- Which transactions should be reviewed first, and how much money is at stake?

## Project Objectives

1. Simulate a reproducible ledger with rule-based fraud patterns.
2. Profile data quality: types, missing values, duplicates.
3. Engineer calendar, risk-flag, velocity and anomaly features.
4. Load the data into MySQL and validate the load.
5. Answer business questions with SQL.
6. Build a customer-level feature table for modelling.
7. Compare three classifiers suited to imbalanced data.
8. Tune the decision threshold.
9. Score every transaction and assign a risk tier.
10. Publish monitoring extracts and a Power BI dashboard.

## Technology Stack

| Layer | Tools |
|---|---|
| Language | Python 3 |
| Data wrangling | pandas, NumPy |
| Charts | Matplotlib |
| Warehouse | MySQL 8 |
| SQL techniques | CTEs, conditional aggregation, `HAVING`, `RANK()`, named windows |
| Modelling | scikit-learn |
| Class imbalance | imbalanced-learn |
| Dashboard | Power BI (DAX) |
| Environment | Jupyter Notebook, VS Code |
| Versioning | Git, GitHub |

## Dataset

The data is **synthetic** and generated in Python with a fixed seed (42), so it reproduces exactly.

| Property | Value |
|---|---|
| Transactions | 200,000 |
| Customers | ~30,000 (1,000 in the ML feature extract) |
| Period | Jan 2024 – Dec 2025 |
| Channels | POS, Online, Mobile, ATM, Branch |
| Countries | UK (home market) + 7 international |
| Fraud rate | 2.92% (5,831 transactions) |

Fraud labels come from three injected rules:

| Rule | Population | Fraud probability |
|---|---|---|
| Big-ticket | amount ≥ 99.5th percentile | 65% |
| Cross-border digital | Online / Mobile outside the UK | 8% |
| Large ATM cash-out | ATM withdrawal above 1,000 | 20% |

## Project Architecture

```text
 Synthetic ledger (seeded)
          │
          ▼
 Data-quality profile ── types · missing values · duplicates
          │
          ▼
 Feature engineering
          ├─ calendar features
          ├─ risk flags (high value · international · digital · ATM)
          ├─ velocity (24h count · gap since previous · rapid flag)
          └─ amount anomaly (Z-score)
          │
          ▼
 CSV extracts ──► MySQL warehouse
                       ├─ Q1–Q9 business queries
                       └─ customer_ml_features
          │
          ▼
 Customer models ── LR · RF · Balanced RF ── threshold sweep
          │
          ▼
 Transaction model ── probability · risk tier · exposure
          │
          ▼
 Power BI ── KPIs · risk mix · trend · channel · country · investigation queue
```

## 1. Data Preparation & Feature Engineering

All steps run in `Notebooks/Fraud_Detection_ML.ipynb`. Settings (paths, seed, business rules) are defined once in a config cell.

| Group | Features |
|---|---|
| Calendar | year, month, day, day of week, day name, weekend flag |
| Risk flags | high value (≥ P95), international (non-UK), digital (Online / Mobile), ATM channel |
| Transform | `log1p(amount)` |
| Velocity | rolling 24h transaction count per customer, minutes since previous transaction (999,999 if none), rapid flag (≤ 5 minutes) |
| Anomaly | amount Z-score, anomaly flag |
| Composite | `risk_score` = high value + international + digital + ATM |
| | `behavioural_risk_score` = high value + international + digital + rapid + anomaly |

## 2. Anomaly Detection

Amounts are standardised into a Z-score, and transactions with

```text
|z| >= 3
```

are flagged as amount anomalies. **3,095 transactions** are flagged, with a **23.2% fraud rate** against 2.6% for normal amounts.

## 3. MySQL Data Warehouse

`SQL/schema.sql` builds the `financial_fraud_analytics` database in five stages:

1. Create the database
2. Create the tables
3. Prepare the load (reset the table, stage the date column as text)
4. Clean up after the load (convert `\N` to `NULL`, restore `DATETIME`)
5. Run integrity checks

Tables:

```text
transactions             engineered transaction-level data
customer_fraud_summary   per-customer fraud profile
fraud_predictions        model scores (FK -> transactions)
customer_ml_features     built in business_queries.sql
```

Integrity checks cover row count, unique transaction IDs, unique customers, the fraud label split and rows with no previous transaction. The loaded table holds **200,000 rows with 200,000 distinct IDs**.

## 4. Advanced SQL Analytics

`SQL/business_queries.sql`:

| # | Question |
|---|---|
| Q1 | Monthly volume, fraud rate and fraud value |
| Q2 | Country ranking by fraud rate |
| Q3 | Channel exposure |
| Q4 | Top 25 customers by fraudulent value |
| Q5 | Repeat-fraud customers (2+ frauds) |
| Q6 | Customer velocity ranking |
| Q7 | Rapid vs. normal transactions |
| Q8 | Fraud rate by behavioural risk score |
| Q9 | Share of total fraud value held by the top customers |

Techniques: CTEs (including chained CTEs), derived tables, `GROUP BY` / `HAVING`, conditional aggregation with `SUM(amount * is_fraud)`, `RANK()`, `SUM() OVER ()` and named `WINDOW` clauses.

**Key findings**

- Mobile (5.54%) and Online (5.48%) fraud rates are about 17× those of POS (0.33%), ATM (0.29%) and Branch (0.32%).
- Every international market sits between 4.2% and 4.5%, against 0.35% in the UK.
- Digital + international transactions account for 92.3% of all fraud.
- Fraud rises with the behavioural risk score: 0% at scores 0–1, 7.6% at 2, 14.1% at 3 and 27.2% at 4.
- Velocity showed no signal: no transactions fall inside the 5-minute rapid window, and customers with 2+ transactions in 24 hours have a slightly *lower* fraud rate (2.6%).

## 5. Customer-Level Machine Learning Dataset

`customer_ml_features` is built in MySQL (one row per customer) and loaded by the notebook.

Model features (12):

```text
total_transactions                 total_transaction_value
average_transaction_amount         maximum_transaction_amount
average_transaction_velocity       maximum_transaction_velocity
rapid_transaction_count            amount_anomaly_count
international_transaction_count    digital_transaction_count
average_behavioural_risk_score     maximum_behavioural_risk_score
```

Target:

```text
fraud_target = 1  if the customer has at least one fraudulent transaction
fraud_target = 0  otherwise
```

`historical_fraud_transactions` and `historical_fraud_rate` are excluded because they are derived from the target and would leak it. The modelling sample has 1,000 customers, 18.7% of them fraudulent, split 80/20 with stratification.

## 6. Machine Learning Models

All three models share one settings dict, so the forests are directly comparable.

| Model | Configuration | Imbalance handling |
|---|---|---|
| Logistic Regression | standard-scaled inputs, `max_iter=1000` | `class_weight="balanced"` |
| Random Forest | 300 trees, depth 12, min split 10, min leaf 5 | `class_weight="balanced"` |
| Balanced Random Forest | same tree settings | undersampling inside each tree |

## 7. Model Evaluation

Test set: 200 customers, 37 of them fraudulent.

| Model | Accuracy | Precision | Recall | F1 | ROC-AUC | PR-AUC |
|---|---:|---:|---:|---:|---:|---:|
| Logistic Regression | 0.715 | 0.349 | 0.622 | 0.447 | 0.723 | 0.377 |
| **Random Forest** | **0.805** | **0.474** | 0.486 | **0.480** | **0.739** | **0.489** |
| Balanced Random Forest | 0.740 | 0.381 | **0.649** | **0.480** | 0.727 | 0.464 |

Random Forest is the selected model. It ties Balanced RF on F1 and has the highest PR-AUC, which is the most informative metric when positives are rare.

## 8. Model Explainability

Random Forest feature importances are plotted for both models and saved to `Models/`.

- **Customer model:** average behavioural risk score (0.20), maximum transaction amount (0.17), total transaction value (0.16).
- **Transaction model:** behavioural risk score (0.37), risk score (0.24), digital flag (0.13).

ROC and precision-recall curves for the customer Random Forest are also saved to `Models/`.

## 9. Threshold Optimisation

Thresholds from **0.10 to 0.90** (step 0.05) were swept for the customer Random Forest.

| Best-F1 threshold | Precision | Recall | F1 |
|---:|---:|---:|---:|
| 0.40 | 0.397 | 0.676 | 0.500 |

Lowering the cut-off from 0.50 to 0.40 raises recall from 49% to 68% for a small loss in precision. The threshold was chosen on the test set, so these figures are slightly optimistic. A production threshold would also weigh fraud loss, review cost, customer friction and team capacity.

## 10. Transaction-Level Fraud Prediction

A second Random Forest (same settings) is trained on 13 transaction features:

```text
amount                  is_high_value             is_international
is_digital              is_atm                    transaction_count_24h
minutes_since_previous_transaction                is_rapid_transaction
amount_z_score          is_amount_anomaly         risk_score
behavioural_risk_score  is_weekend
```

On the 40,000 held-out transactions it reaches 0.986 recall, 0.088 precision, 0.863 ROC-AUC and 0.198 PR-AUC. It catches almost all fraud but flags many legitimate transactions, which is why ranking by probability matters.

Outputs per transaction: `fraud_probability`, `model_prediction`, `risk_category`.

## 11. Fraud Risk Categories

| Fraud probability | Risk tier |
|---:|---|
| 0 – 0.25 | Low Risk |
| 0.25 – 0.50 | Medium Risk |
| 0.50 – 0.75 | High Risk |
| 0.75 – 1.00 | Critical Risk |

Tier counts across the portfolio: Low 134,114 · Medium 503 · High 55,975 · Critical 9,408. The tiers are analytical bands, not regulatory decision thresholds.

## 12. Fraud Investigation Queue

The queue contains every High or Critical transaction, sorted by fraud probability and then amount. Each row shows:

- transaction ID, customer ID, date
- type, channel, country
- amount, fraud probability, risk tier
- potential exposure (the amount, for queued transactions)

**Prioritisation value:** on held-out data, reviewing the **top 1%** of transactions by fraud probability covers **73% of fraudulent value**, at 41.5% precision.

## 13. Power BI Dashboard

`PowerBI/Financial_Fraud_Detection_Intelligence.pbix` is fed by `fraud_transaction_predictions.csv` and `daily_fraud_monitoring.csv`.

- **KPI strip:** total transactions, actual frauds, fraud rate, fraudulent value, potential exposure
- **Risk mix:** donut chart across the four tiers
- **Trend:** daily fraud count and potential exposure
- **Channel view:** fraudulent value by channel
- **Country view:** fraudulent value by country
- **Investigation queue:** High and Critical transactions with full detail

## 14. Key Business Questions Answered

1. What volume of transactions is processed?
2. What share of transactions is fraudulent?
3. What is the value of fraudulent transactions?
4. Which channels carry the most fraud exposure?
5. Which countries carry the most fraud exposure?
6. Which customers commit fraud repeatedly?
7. Do rapid or high-velocity transactions signal fraud?
8. Which amounts are statistical outliers?
9. Which features drive the model's predictions?
10. Which transactions should be reviewed first?
11. How much exposure sits in the High and Critical tiers?
12. How does fraud risk change day to day?

## 15. Project Outputs

```text
Dataset/
├── Raw/
│   └── financial_transactions_raw.csv
└── Processed/
    ├── financial_transactions_processed.csv
    ├── financial_transactions_mysql.csv
    ├── customer_ml_features.csv
    ├── fraud_transaction_predictions.csv
    ├── daily_fraud_monitoring.csv
    └── fraud_model_feature_importance.csv
SQL/
├── schema.sql
└── business_queries.sql
Notebooks/
└── Fraud_Detection_ML.ipynb
PowerBI/
└── Financial_Fraud_Detection_Intelligence.pbix
Models/
├── Random Forest Feature Importance.png
├── Transaction-Level Fraud Model Feature Importance.png
├── ROC Curve — Fraud Detection.png
└── Precision-Recall Curve — Fraud Detection.png
README.md
```

**How to reproduce**

1. Install the dependencies: `pip install pandas numpy matplotlib scikit-learn imbalanced-learn jupyter`.
2. Run notebook sections 0–7. This writes the raw, processed and MySQL extracts.
3. Run `SQL/schema.sql` in MySQL 8 and import `financial_transactions_mysql.csv` at the marked step.
4. Run `SQL/business_queries.sql` and export the final result to `Dataset/Processed/customer_ml_features.csv`.
5. Run notebook sections 8–11.
6. Open the `.pbix` file and refresh it.

## 16. Skills Demonstrated

**Data analytics:** EDA, data-quality profiling, feature engineering, behavioural analytics, KPI design, segment risk analysis

**SQL:** MySQL, CTEs, window functions, ranking, conditional aggregation, data-load validation, customer-level aggregation

**Machine learning:** binary classification, Logistic Regression, Random Forest, Balanced Random Forest, class-imbalance handling, feature importance, ROC-AUC, PR-AUC, threshold tuning

**Anomaly detection:** Z-score outliers, transaction velocity, rapid-transaction detection

**Business intelligence:** Power BI, DAX, KPI dashboards, risk segmentation, trend monitoring, investigation workflows

## 17. Limitations & Next Steps

- **Synthetic labels:** fraud comes from three injected rules, so the SQL findings partly rediscover those rules.
- **Small customer test set:** only 37 fraudulent customers, so the metrics have wide uncertainty.
- **Threshold chosen on test data:** a separate validation split or cross-validation would give an unbiased estimate.
- **Dashboard scores include training rows:** dashboard-level coverage figures are optimistic. Held-out figures are reported above.
- **Next steps:** time-based train/test split, cost-sensitive thresholds, gradient boosting, SHAP explanations.

## Author

**Sneha**
Data Analyst | Data Science | Machine Learning | Business Intelligence


