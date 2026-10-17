# Fraud Risk Intelligence Platform

Transaction-level fraud analytics built with Python, MySQL, scikit-learn and Power BI. It covers the full path from a synthetic ledger to engineered risk signals, SQL investigations, fraud-propensity models, risk tiers and an investigator-facing dashboard.

---

## At a glance

| | |
|---|---|
| **Data** | ~200,000 synthetic transactions, ~30,000 customers, Jan 2024 – Dec 2025 |
| **Signals** | calendar, risk flags, 24h velocity, inter-transaction gap, amount Z-score, composite scores |
| **SQL** | CTEs, conditional aggregation, `HAVING`, `RANK()` and named windows |
| **Models** | Logistic Regression · Random Forest · Balanced Random Forest |
| **Outputs** | per-transaction fraud probability, 4 risk tiers, daily monitoring extract, Power BI report |

**Stack:** Python (pandas, NumPy, Matplotlib) · scikit-learn · imbalanced-learn · MySQL 8 · Power BI (DAX) · Jupyter

---

## Questions the project answers

- How large is the fraud problem in count, rate and value?
- Where is exposure concentrated by country, channel, transaction type and customer?
- Do burst activity (rapid / high-velocity transactions) and outlier amounts signal fraud?
- How well can a model rank fraud risk, and which signals drive it?
- Which decision threshold best balances precision and recall?
- Which transactions should investigators look at first, and how much money is at stake?

---

## Repository layout

```text
.
├── Dataset/
│   ├── Raw/financial_transactions_raw.csv          # simulated ledger
│   └── Processed/
│       ├── financial_transactions_processed.csv    # ledger + engineered features
│       ├── financial_transactions_mysql.csv        # same, NULLs encoded as \N for MySQL import
│       ├── customer_ml_features.csv                # built in SQL, consumed by the notebook
│       ├── fraud_transaction_predictions.csv       # scored transactions (Power BI)
│       ├── daily_fraud_monitoring.csv              # daily KPIs (Power BI)
│       └── fraud_model_feature_importance.csv      # transaction-model drivers
├── Notebooks/Fraud_Detection_ML.ipynb              # simulation, features, models, scoring
├── SQL/
│   ├── schema.sql                                  # warehouse setup, load prep, integrity checks
│   └── business_queries.sql                        # Q1–Q9 analytics + ML feature table
├── Models/                                         # importance, ROC and PR charts
└── PowerBI/Financial_Fraud_Detection_Intelligence.pbix
```

---

## Pipeline

```text
 simulate ledger ──► quality profile ──► feature engineering ──► CSV extracts
                                                                     │
                       ┌─────────────────────────────────────────────┘
                       ▼
               MySQL warehouse ──► business queries (Q1–Q9) ──► customer_ml_features
                                                                     │
                       ┌─────────────────────────────────────────────┘
                       ▼
        customer models + threshold sweep      transaction model ──► risk tiers
                                                                     │
                                                                     ▼
                                                 Power BI monitoring & investigation queue
```

### Stage 1 – Synthetic ledger

Every random draw uses one seeded generator (seed 42), so the ledger can be reproduced exactly. Labels come from three fraud rules:

| Rule | Population | Fraud probability |
|---|---|---|
| Big-ticket | amount ≥ 99.5th percentile | 65% |
| Cross-border digital | Online / Mobile, outside the UK | 8% |
| Large ATM cash-out | ATM withdrawal above 1,000 | 20% |

### Stage 2 – Feature engineering

| Group | Features |
|---|---|
| Calendar | year, month, day, day of week, day name, weekend flag |
| Risk flags | high value (≥ P95), international (non-UK), digital, ATM, `log1p(amount)` |
| Velocity | rolling 24h count per customer, minutes since previous transaction (999,999 when none), rapid flag (≤ 5 min) |
| Anomaly | amount Z-score, anomaly flag where \|z\| ≥ 3 |
| Composite | `risk_score` = high value + international + digital + ATM<br>`behavioural_risk_score` = high value + international + digital + rapid + anomaly |

### Stage 3 – MySQL warehouse (`financial_fraud_analytics`)

`schema.sql` creates `transactions`, `customer_fraud_summary` and `fraud_predictions`. It stages `previous_transaction_date` as text for the CSV import, converts the `\N` markers to real `NULL`s, restores the `DATETIME` type and runs integrity checks: row count, unique IDs, unique customers, fraud count and rows with no previous transaction. The loaded table holds 200,000 rows with 200,000 distinct transaction IDs.

### Stage 4 – SQL analytics (`business_queries.sql`)

| # | Analysis |
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
| ML | `customer_ml_features`: one row per customer, exported for modelling |

### Stage 5 – Customer-level models

- **Target:** the customer has at least one fraudulent transaction.
- **Features:** 12 activity, monetary, velocity and behaviour aggregates. `historical_fraud_transactions` and `historical_fraud_rate` are left out because they are derived from the target and would leak it.
- **Split:** 80/20, stratified.
- **Models:**
  - Logistic Regression: scaled inputs, balanced class weights
  - Random Forest: 300 trees, depth 12, min split 10, min leaf 5, balanced class weights
  - Balanced Random Forest: same tree settings, with per-tree undersampling
- **Evaluation:** accuracy, precision, recall, F1 and ROC-AUC. Precision, recall and F1 carry the most weight because the classes are imbalanced.
- **Diagnostics:** feature importance, ROC curve, precision-recall curve.
- **Threshold sweep:** cut-offs from 0.10 to 0.90 in 0.05 steps, choosing the best F1. A production threshold would also need to account for loss cost, review cost, customer friction, team capacity and regulation.

### Stage 6 – Transaction scoring

A transaction-level Random Forest uses the same settings and 13 features: amount, the four risk flags, 24h count, minutes since the previous transaction, rapid flag, Z-score, anomaly flag, both composite scores and the weekend flag. It scores every transaction:

| Fraud probability | Tier |
|---:|---|
| 0 – 0.25 | Low Risk |
| 0.25 – 0.50 | Medium Risk |
| 0.50 – 0.75 | High Risk |
| 0.75 – 1.00 | Critical Risk |

High and Critical transactions form the **investigation queue**. Their amount counts as `potential_exposure`. The tiers are analytical bands, not regulatory decision thresholds.

### Stage 7 – Power BI

- **KPI strip:** transactions, actual frauds, fraud rate, fraudulent value, potential exposure
- **Risk mix:** donut chart across the four tiers
- **Trend:** daily frauds and exposure
- **Exposure maps:** fraudulent value by channel and by country
- **Investigation queue:** High and Critical transactions with ID, customer, date, type, channel, country, amount, probability, tier and exposure

---

## Reproducing

1. Install the dependencies: `pandas numpy matplotlib scikit-learn imbalanced-learn jupyter`.
2. Open `Notebooks/Fraud_Detection_ML.ipynb` and run sections 0–7. This writes the raw, processed and MySQL extracts.
3. In MySQL 8, run `SQL/schema.sql`. Import `financial_transactions_mysql.csv` at the marked step, then finish the script.
4. Run `SQL/business_queries.sql` and export the final result to `Dataset/Processed/customer_ml_features.csv`.
5. Run notebook sections 8–11 to train, score and export the Power BI extracts.
6. Open the `.pbix` file and refresh it.

---

## Author

**Mohd Shafi Sutriwala**: Data Analyst · Data Science · Machine Learning · Business Intelligence
