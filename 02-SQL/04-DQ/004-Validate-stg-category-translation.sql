USE NOVA_Market;
GO

/* =========================================================
   Data Quality Validation: stg.category_translation
   Source: Olist product category translation dataset
   Grain : one row per product_category_name

   Purpose:
   - Validate source translation integrity
   - Measure translation coverage against stg.products
   - Identify missing English translations
   - Identify unused translation records

   Known Source Gap:
   - 73 non-null product categories exist in stg.products
   - 71 category translations exist in source
   - 2 categories have no English translation:
       1. pc_gamer
       2. portateis_cozinha_e_preparadores_de_alimentos
   - These gaps affect 13 products in total
   ========================================================= */


------------------------------------------------------------
-- 1. Row Count
------------------------------------------------------------
SELECT
    COUNT(*) AS [RowCount]
FROM stg.category_translation;

-- Expected: 71


------------------------------------------------------------
-- 2. Duplicate Source Category Key
------------------------------------------------------------
SELECT
    product_category_name,
    COUNT(*) AS DuplicateCount
FROM stg.category_translation
GROUP BY product_category_name
HAVING COUNT(*) > 1;

-- Expected: No rows


------------------------------------------------------------
-- 3. NULL Audit
------------------------------------------------------------
SELECT
    SUM(
        CASE
            WHEN product_category_name IS NULL
            THEN 1 ELSE 0
        END
    ) AS SourceCategoryNulls,

    SUM(
        CASE
            WHEN product_category_name_english IS NULL
            THEN 1 ELSE 0
        END
    ) AS EnglishCategoryNulls

FROM stg.category_translation;

-- Expected:
-- SourceCategoryNulls  = 0
-- EnglishCategoryNulls = 0


------------------------------------------------------------
-- 4. Blank / Empty Value Audit
------------------------------------------------------------
SELECT
    SUM(
        CASE
            WHEN product_category_name IS NOT NULL
             AND LTRIM(RTRIM(product_category_name)) = ''
            THEN 1 ELSE 0
        END
    ) AS BlankSourceCategories,

    SUM(
        CASE
            WHEN product_category_name_english IS NOT NULL
             AND LTRIM(RTRIM(product_category_name_english)) = ''
            THEN 1 ELSE 0
        END
    ) AS BlankEnglishCategories

FROM stg.category_translation;

-- Expected:
-- BlankSourceCategories  = 0
-- BlankEnglishCategories = 0


------------------------------------------------------------
-- 5. Distinct Product Categories
------------------------------------------------------------
SELECT
    COUNT(DISTINCT product_category_name)
        AS DistinctProductCategories
FROM stg.products
WHERE product_category_name IS NOT NULL;

-- Expected: 73


------------------------------------------------------------
-- 6. Distinct Translation Categories
------------------------------------------------------------
SELECT
    COUNT(DISTINCT product_category_name)
        AS DistinctTranslationCategories
FROM stg.category_translation;

-- Expected: 71


------------------------------------------------------------
-- 7. Product Categories Missing English Translation
------------------------------------------------------------
SELECT
    p.product_category_name
FROM
(
    SELECT DISTINCT
        product_category_name
    FROM stg.products
    WHERE product_category_name IS NOT NULL
) p
LEFT JOIN stg.category_translation t
    ON p.product_category_name = t.product_category_name
WHERE t.product_category_name IS NULL
ORDER BY p.product_category_name;

-- Expected:
-- pc_gamer
-- portateis_cozinha_e_preparadores_de_alimentos


------------------------------------------------------------
-- 8. Missing Translation Category Count
------------------------------------------------------------
SELECT
    COUNT(*) AS MissingTranslationCategoryCount
FROM
(
    SELECT DISTINCT
        p.product_category_name
    FROM stg.products p
    LEFT JOIN stg.category_translation t
        ON p.product_category_name = t.product_category_name
    WHERE p.product_category_name IS NOT NULL
      AND t.product_category_name IS NULL
) x;

-- Expected: 2


------------------------------------------------------------
-- 9. Missing Translation Impact by Product Count
------------------------------------------------------------
SELECT
    p.product_category_name,
    COUNT(*) AS ProductCount
FROM stg.products p
LEFT JOIN stg.category_translation t
    ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL
GROUP BY p.product_category_name
ORDER BY p.product_category_name;

-- Expected:
-- pc_gamer                                      = 3
-- portateis_cozinha_e_preparadores_de_alimentos = 10


------------------------------------------------------------
-- 10. Total Products Affected by Missing Translation
------------------------------------------------------------
SELECT
    COUNT(*) AS ProductsAffectedByMissingTranslation
FROM stg.products p
LEFT JOIN stg.category_translation t
    ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL;

-- Expected: 13


------------------------------------------------------------
-- 11. Translation Categories Not Used by Products
------------------------------------------------------------
SELECT
    t.product_category_name,
    t.product_category_name_english
FROM stg.category_translation t
LEFT JOIN
(
    SELECT DISTINCT
        product_category_name
    FROM stg.products
    WHERE product_category_name IS NOT NULL
) p
    ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NULL
ORDER BY t.product_category_name;

-- Expected: No rows


------------------------------------------------------------
-- 12. Unused Translation Count
------------------------------------------------------------
SELECT
    COUNT(*) AS UnusedTranslationCount
FROM stg.category_translation t
LEFT JOIN
(
    SELECT DISTINCT
        product_category_name
    FROM stg.products
    WHERE product_category_name IS NOT NULL
) p
    ON t.product_category_name = p.product_category_name
WHERE p.product_category_name IS NULL;

-- Expected: 0


------------------------------------------------------------
-- 13. Duplicate English Category Labels
------------------------------------------------------------
SELECT
    product_category_name_english,
    COUNT(*) AS DuplicateCount
FROM stg.category_translation
WHERE product_category_name_english IS NOT NULL
GROUP BY product_category_name_english
HAVING COUNT(*) > 1;

-- Expected: No rows


------------------------------------------------------------
-- 14. Translation Coverage Percentage
------------------------------------------------------------
SELECT
    CAST(
        100.0 *
        COUNT(DISTINCT t.product_category_name)
        /
        NULLIF(
            COUNT(DISTINCT p.product_category_name),
            0
        )
        AS DECIMAL(6,2)
    ) AS TranslationCoveragePercent
FROM stg.products p
LEFT JOIN stg.category_translation t
    ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL;

-- Expected: approximately 97.26%


------------------------------------------------------------
-- 15. Full Translation Mapping
------------------------------------------------------------
SELECT
    product_category_name         AS CategoryNameSourcePT,
    product_category_name_english AS CategoryNameEN
FROM stg.category_translation
ORDER BY product_category_name;

-- Informational
-- This mapping will later feed the DWH localization layer.