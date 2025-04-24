# Peer Review QC Script

## Overview

This SQL script performs **quality control (QC) checks** across critical land management data tables during client onboarding or system migration. It is designed to run in a **staging environment** before deployment to production and ensures data accuracy, consistency, and readiness for UI-driven applications.

## Purpose

This script supports:
- **Data quality assurance** during ETL migrations
- **Peer and manager review** before deployment
- **Auditable logs** with contextual error messages and sample failing records

## Components

| Section | Description |
|--------|-------------|
| `#QC_Log` Temp Table | Central log to collect results of each QC check |
| `Company`            | Confirms required company master data is loaded |
| `Agreement`, `AgreementTract`, `AgreementTractDOI` | Validates agreement structure, acreage, and ownership interest rules |
| `AgreementProvision`, `AgreementPayee` | Confirms provision data like payments, obligations, and payees |
| `Area`, `AreaTract`, `AreaGeoBasin`, `AreaHierarchy` | Ensures hierarchical relationships and legal references are consistent |
| `Asset`, `AssetTract`, `AssetInterest` | Validates asset interest math, tracts, and accounting alignment |
| `CrossReference`     | Ensures bi-directional references between parent/child entities |
| `Owner`              | Confirms owner information is loaded and validated against ETL |
| `Tract Digit Lengths`| Verifies tract numbers follow a standardized format |
| `QC Roll-up`         | Aggregates failures per checklist item with example `RecordIDs` for quick investigation |

## Output

Each QC result is written to the `#QC_Log` temp table with the following fields:
- `Area`: The source domain of the data
- `Checklist`: The specific rule or check being validated
- `ErrorDescription`: What went wrong (or "PASS")
- `Status`: `PASS`, `FAIL`, or `CHECK`
- `RecordID`: The offending record (when applicable)
- `Additional_Comments`: Domain or client-specific guidance
- `Reviewed_YN`, `ReviewerInitials`, `Reviewed_Date`: Signoff metadata for peer validation
- `Data_Hygienist_Comments`: Analyst notes during triage

## Real-World Context

This script was used as part of **data conversion efforts for an enterprise land system** — including migrations from legacy formats (Excel, flat files) to a proprietary land software platform. The checks accommodate **complex business logic** (e.g., net/gross acreage relationships, interest type cross-validation).

## Highlights

- 70+ QC checks across 15+ domain areas
- Dynamic roll-up of top error descriptions
- Designed for reusability and adaptation across multiple clients
- Clear separation of validation logic per domain object

## Usage

1. Run the script in a staging environment after ETL load
2. Review the `#QC_Log` output
3. Address all `FAIL` and `CHECK` items
4. Re-run as needed until all critical data passes validation
5. Optionally export `#QC_Log` to Excel for peer review or documentation