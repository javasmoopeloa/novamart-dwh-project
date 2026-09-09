# NovaMart Data Warehouse Project

## Overview
This project builds an end-to-end data warehouse for **NovaMart**, a fictional multi-channel
retailer (e-commerce, mobile app, and pop-up stores). It solves a common BI problem: finance,
marketing, and operations all report different sales numbers, and there's no single source of
truth. We designed and built a staging → core → data mart architecture on AWS, modeled a star
schema for the Sales business process, and built a reporting dashboard on top.

## Team & Roles
| Name | Student Number | Role | Owns |
|---|---|---|---|
| Moopeloa Jabulane | 22350028 | Architecture Lead | Staging/core/mart layer design (Ch. 2) |
| Asande Akhona Dlamini | 22367136 | Modeling Lead | Star schema, grain, key design (Ch. 3, Ch. 4) |
| Sibahle Magubane | 22271233 | ETL/Engineering Lead | AWS setup and SQL transformation scripts |
| Senamile Nxumalo | 22302052 | BI/Reporting Lead | Dashboard and final presentation |

## Dataset
We are using the **Olist Brazilian E-Commerce Public Dataset**, re-themed as NovaMart data.
See `docs/01_business_requirements.md` for the column-mapping notes.

## Architecture
Sources → S3 (raw landing) → RDS PostgreSQL `staging` schema → `core` schema → `mart_finance` schema → BI tool

See `docs/02_architecture_diagram.png` for the full diagram.

## How to Run This Project
1. Clone this repo.
2. Provision AWS S3 + RDS PostgreSQL (see `docs/02_architecture_diagram.png` and Phase 2 notes).
3. Run `sql/01_create_schemas.sql` against your RDS instance.
4. Load raw files into `staging` (see Phase 2/3 notes).
5. Run `sql/02_create_core_tables.sql`, then `sql/03_etl_staging_to_core.sql`.
6. Run `sql/04_build_data_mart.sql`.
7. Connect your BI tool to `mart_finance` and open the dashboard file in `dashboard/`.

## Repo Structure
```
docs/       business requirements, data quality report, dimensional model, diagrams
sql/        all SQL scripts, numbered in run order
dashboard/  BI tool file or screenshots/video
```

## Setup Evidence (Phase 2)
Screenshots confirming the S3 bucket, RDS instance, and DBeaver connection are working.

**S3 bucket with source folders**
![S3 Bucket](docs/screenshots/01_s3_bucket.jpeg)

**RDS instance — Available**
![RDS Available](docs/screenshots/02_rds_available.jpeg)

**DBeaver successfully connected to RDS**
![DBeaver Connected](docs/screenshots/03_dbeaver_connected.jpeg)

**Schemas created (staging, core, mart_finance)**
![Schemas Created](docs/screenshots/04_schemas_created.png)
