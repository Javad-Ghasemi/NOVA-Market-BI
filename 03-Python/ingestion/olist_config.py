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
    
    "products": {
    "file_name": "olist_products_dataset.csv",
    "schema": "stg",
    "table": "products",
    "expected_columns": [
        "product_id",
        "product_category_name",
        "product_name_lenght",
        "product_description_lenght",
        "product_photos_qty",
        "product_weight_g",
        "product_length_cm",
        "product_height_cm",
        "product_width_cm",
    ],
    "datetime_columns": [],
    "date_columns": [],
    "integer_columns": [
        "product_name_lenght",
        "product_description_lenght",
        "product_photos_qty",
        "product_weight_g",
        "product_length_cm",
        "product_height_cm",
        "product_width_cm",
    ],
    "decimal_columns": [],
    "key_columns": [
        "product_id",
    ],
    },
}