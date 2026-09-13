# Olist Data Quality Report

## Dataset Inventory

| Dataset | Rows |
|---|---:|
| orders | 99,441 |
| order_items | 112,650 |
| products | 32,951 |
| customers | 99,441 |
| sellers | 3,095 |
| payments | 103,886 |
| reviews | 99,224 |
| geolocation | 1,000,163 |
| category_translation | 71 |

## Source Time Range

- Minimum order purchase timestamp: `2016-09-04 21:15:19`
- Maximum order purchase timestamp: `2018-10-17 17:30:18`

## Order Status Distribution

| Status | Orders |
|---|---:|
| delivered | 96,478 |
| shipped | 1,107 |
| canceled | 625 |
| unavailable | 609 |
| invoiced | 314 |
| processing | 301 |
| created | 5 |
| approved | 2 |

## Key Data Quality Checks

| Check | Result |
|---|---:|
| Duplicate order_id | 0 |
| Duplicate customer_id | 0 |
| Duplicate seller_id | 0 |
| Duplicate product_id | 0 |
| Duplicate order_id + order_item_id | 0 |
| Orphan order_items -> orders | 0 |
| Orphan order_items -> products | 0 |
| Orphan order_items -> sellers | 0 |
| Orphan payments -> orders | 0 |
| Orphan reviews -> orders | 0 |
| Products with missing category | 610 |

## Payment Multiplicity

- Orders with more than one payment row: `2,961`
- Maximum payment rows for one order: `29`

## Review Multiplicity

- Orders with more than one review row: `547`
- Maximum review rows for one order: `3`

## Important Null Checks

| Field | Null Rows |
|---|---:|
| orders.order_purchase_timestamp | 0 |
| orders.customer_id | 0 |
| order_items.order_id | 0 |
| order_items.product_id | 0 |
| order_items.seller_id | 0 |
| products.product_id | 0 |

## Category Translation Coverage

- Source categories: `73`
- Translated categories: `71`
- Categories without English translation: `2`

### Categories without Translation

- `pc_gamer`
- `portateis_cozinha_e_preparadores_de_alimentos`

## Payment vs Item Value Diagnostic

- Orders where summed payment value differs from summed item price: `99,100`
- This is a diagnostic only. Payment value must not be naively treated as sales value because payments can include freight and other amounts.

## Delivered Orders

- Delivered orders: `96,478`
- Delivered order-item rows: `110,197`

## Architectural Findings

- Olist is the real transaction source for this project.
- Seller is not treated as a physical branch.
- Olist does not provide native product cost / COGS.
- Olist source period is 2016–2018.
- Payment and review data remain separate fact domains.
- Product orphan records must be handled explicitly during ETL.
- No synthetic transactions are introduced as real source data.
