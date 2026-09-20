USE NOVA_Market;
GO

/* =========================================================
   Data Quality Validation: stg.products
   Source: Olist products dataset
   Grain : one row per product_id
   ========================================================= */


------------------------------------------------------------
-- 1. Row Count
------------------------------------------------------------
SELECT
    COUNT(*) AS [RowCount]
FROM stg.products;

-- Expected: 32,951


------------------------------------------------------------
-- 2. Duplicate Primary / Business Key
------------------------------------------------------------
SELECT
    product_id,
    COUNT(*) AS DuplicateCount
FROM stg.products
GROUP BY product_id
HAVING COUNT(*) > 1;

-- Expected: No rows


------------------------------------------------------------
-- 3. NULL Audit
------------------------------------------------------------
SELECT
    SUM(CASE WHEN product_id IS NULL THEN 1 ELSE 0 END)
        AS product_id_nulls,

    SUM(CASE WHEN product_category_name IS NULL THEN 1 ELSE 0 END)
        AS product_category_name_nulls,

    SUM(CASE WHEN product_name_lenght IS NULL THEN 1 ELSE 0 END)
        AS product_name_length_nulls,

    SUM(CASE WHEN product_description_lenght IS NULL THEN 1 ELSE 0 END)
        AS product_description_length_nulls,

    SUM(CASE WHEN product_photos_qty IS NULL THEN 1 ELSE 0 END)
        AS product_photos_qty_nulls,

    SUM(CASE WHEN product_weight_g IS NULL THEN 1 ELSE 0 END)
        AS product_weight_g_nulls,

    SUM(CASE WHEN product_length_cm IS NULL THEN 1 ELSE 0 END)
        AS product_length_cm_nulls,

    SUM(CASE WHEN product_height_cm IS NULL THEN 1 ELSE 0 END)
        AS product_height_cm_nulls,

    SUM(CASE WHEN product_width_cm IS NULL THEN 1 ELSE 0 END)
        AS product_width_cm_nulls

FROM stg.products;

-- Known source fact:
-- product_category_name NULLs = 610


------------------------------------------------------------
-- 4. Blank / Empty Category Values
------------------------------------------------------------
SELECT
    COUNT(*) AS BlankCategoryRows
FROM stg.products
WHERE product_category_name IS NOT NULL
  AND LTRIM(RTRIM(product_category_name)) = '';

-- Ideally: 0


------------------------------------------------------------
-- 5. Referential Integrity
-- order_items -> products
------------------------------------------------------------
SELECT
    COUNT(*) AS OrphanOrderItems
FROM stg.order_items oi
LEFT JOIN stg.products p
    ON oi.product_id = p.product_id
WHERE p.product_id IS NULL;

-- Expected: 0


------------------------------------------------------------
-- 6. Invalid Negative Numeric Values
------------------------------------------------------------
SELECT
    SUM(CASE WHEN product_name_lenght < 0 THEN 1 ELSE 0 END)
        AS NegativeNameLength,

    SUM(CASE WHEN product_description_lenght < 0 THEN 1 ELSE 0 END)
        AS NegativeDescriptionLength,

    SUM(CASE WHEN product_photos_qty < 0 THEN 1 ELSE 0 END)
        AS NegativePhotoQty,

    SUM(CASE WHEN product_weight_g < 0 THEN 1 ELSE 0 END)
        AS NegativeWeight,

    SUM(CASE WHEN product_length_cm < 0 THEN 1 ELSE 0 END)
        AS NegativeLength,

    SUM(CASE WHEN product_height_cm < 0 THEN 1 ELSE 0 END)
        AS NegativeHeight,

    SUM(CASE WHEN product_width_cm < 0 THEN 1 ELSE 0 END)
        AS NegativeWidth

FROM stg.products;

-- Expected: preferably all 0


------------------------------------------------------------
-- 7. Suspicious Zero Physical Attributes
------------------------------------------------------------
SELECT
    SUM(CASE WHEN product_weight_g = 0 THEN 1 ELSE 0 END)
        AS ZeroWeight,

    SUM(CASE WHEN product_length_cm = 0 THEN 1 ELSE 0 END)
        AS ZeroLength,

    SUM(CASE WHEN product_height_cm = 0 THEN 1 ELSE 0 END)
        AS ZeroHeight,

    SUM(CASE WHEN product_width_cm = 0 THEN 1 ELSE 0 END)
        AS ZeroWidth

FROM stg.products;

-- These are reviewed as suspicious values.
-- Do not automatically modify or delete them.


------------------------------------------------------------
-- 8. Numeric Range / Sanity Check
------------------------------------------------------------
SELECT
    MIN(product_weight_g) AS MinWeight,
    MAX(product_weight_g) AS MaxWeight,

    MIN(product_length_cm) AS MinLength,
    MAX(product_length_cm) AS MaxLength,

    MIN(product_height_cm) AS MinHeight,
    MAX(product_height_cm) AS MaxHeight,

    MIN(product_width_cm) AS MinWidth,
    MAX(product_width_cm) AS MaxWidth,

    MIN(product_photos_qty) AS MinPhotos,
    MAX(product_photos_qty) AS MaxPhotos

FROM stg.products;


------------------------------------------------------------
-- 9. Category Coverage
------------------------------------------------------------
SELECT
    COUNT(DISTINCT product_category_name) AS DistinctCategories
FROM stg.products
WHERE product_category_name IS NOT NULL;


------------------------------------------------------------
-- 10. Products Missing Category
------------------------------------------------------------
SELECT
    COUNT(*) AS ProductsWithoutCategory
FROM stg.products
WHERE product_category_name IS NULL;

-- Expected: 610


------------------------------------------------------------
-- 11. Category Distribution
------------------------------------------------------------
SELECT
    COALESCE(product_category_name, N'[NULL]') AS ProductCategory,
    COUNT(*) AS ProductCount
FROM stg.products
GROUP BY product_category_name
ORDER BY ProductCount DESC;


------------------------------------------------------------
-- 12. Products Not Referenced by Any Order Item
-- Informational only, NOT necessarily a DQ error
------------------------------------------------------------
SELECT
    COUNT(*) AS ProductsWithoutOrderItems
FROM stg.products p
LEFT JOIN stg.order_items oi
    ON p.product_id = oi.product_id
WHERE oi.product_id IS NULL;





------------------------------------------------------------
-- Known Source Quality Issue
-- Four products have zero recorded weight.
-- Source values are preserved in staging.
-- No synthetic correction is applied.
------------------------------------------------------------

SELECT
    CONCAT(
        '[KNOWN ISSUE] ProductID=', p.product_id,
        ' | Category=', COALESCE(p.product_category_name, N'[NULL]'),
        ' | Weight=', p.product_weight_g,
        ' | Dimensions=',
        p.product_length_cm, 'x',
        p.product_height_cm, 'x',
        p.product_width_cm,
        ' | OrderItems=', COUNT(oi.order_id)
    ) AS DQ_Result
FROM stg.products p
LEFT JOIN stg.order_items oi
    ON p.product_id = oi.product_id
WHERE p.product_weight_g = 0
GROUP BY
    p.product_id,
    p.product_category_name,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
ORDER BY p.product_id;