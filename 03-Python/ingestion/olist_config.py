OLIST_TABLES = {
    "orders": {
        "file_name": "olist_orders_dataset.csv",
        "schema": "stg",
        "table": "orders",
        "expected_columns": [
            "order_id",
            "customer_id",
            "order_status",
            "order_purchase_timestamp",
            "order_approved_at",
            "order_delivered_carrier_date",
            "order_delivered_customer_date",
            "order_estimated_delivery_date",
        ],
        "datetime_columns": [
            "order_purchase_timestamp",
            "order_approved_at",
            "order_delivered_carrier_date",
            "order_delivered_customer_date",
        ],
        "date_columns": [
            "order_estimated_delivery_date",
        ],
        "key_columns": [
            "order_id",
        ],
    },

    "order_items": {
        "file_name": "olist_order_items_dataset.csv",
        "schema": "stg",
        "table": "order_items",
        "expected_columns": [
            "order_id",
            "order_item_id",
            "product_id",
            "seller_id",
            "shipping_limit_date",
            "price",
            "freight_value",
        ],
        "datetime_columns": [
            "shipping_limit_date",
        ],
        "date_columns": [],
        "integer_columns": [
            "order_item_id",
        ],
        "decimal_columns": [
            "price",
            "freight_value",
        ],
        "key_columns": [
            "order_id",
            "order_item_id",
        ],
    },
}