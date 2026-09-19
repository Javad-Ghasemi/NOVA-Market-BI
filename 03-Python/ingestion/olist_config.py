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
    }
}