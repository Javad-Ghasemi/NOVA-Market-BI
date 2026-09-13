# Olist Dataset — Source Definition

## Dataset

Brazilian E-Commerce Public Dataset by Olist

## Source

Kaggle / Olist

## Dataset Type

Real commercial e-commerce transaction data

## Scope

Brazilian e-commerce marketplace data covering orders,
order items, products, customers, sellers, payments,
reviews, geolocation and product category translation.

## Source Files

1. olist_orders_dataset.csv
2. olist_order_items_dataset.csv
3. olist_products_dataset.csv
4. olist_customers_dataset.csv
5. olist_sellers_dataset.csv
6. olist_order_payments_dataset.csv
7. olist_order_reviews_dataset.csv
8. olist_geolocation_dataset.csv
9. product_category_name_translation.csv

## Project Usage

Olist is the real transaction backbone of the NOVA Market BI project.

NOVA Market represents the business and analytics model built
on top of the source data.

## Important Scope Limitations

- The source represents e-commerce activity, not physical retail branches.
- Seller must not be interpreted as a physical branch.
- The source does not provide native COGS / product cost.
- The source period is 2016–2018.
- Some order-item records do not have a matching product record.

## Data Integrity Principle

No synthetic transactions will be presented as real Olist transactions.

Any future synthetic or derived data must be explicitly identified.