USE NOVA_Market;
GO


/* =========================================================
   NOVA Market BI
   Gregorian -> Persian (Jalali) Date Conversion

   Purpose:
   Used only to enrich dwh.DimDate with Persian calendar
   attributes for the bilingual Power BI experience.

   The transactional source dates remain Gregorian and are
   never modified.
   ========================================================= */

CREATE OR ALTER FUNCTION dwh.fn_GregorianToPersianDate
(
    @GregorianDate DATE
)
RETURNS CHAR(10)
AS
BEGIN
    IF @GregorianDate IS NULL
        RETURN NULL;

    DECLARE
        @OriginalYear INT,
        @gy INT,
        @gm INT,
        @gd INT,
        @gDayNo INT,
        @jDayNo INT,
        @jNp INT,
        @jy INT,
        @jm INT,
        @jd INT,
        @DaysBeforeMonth INT;

    SET @OriginalYear = YEAR(@GregorianDate);
    SET @gy = YEAR(@GregorianDate) - 1600;
    SET @gm = MONTH(@GregorianDate) - 1;
    SET @gd = DAY(@GregorianDate) - 1;


    /* Days before Gregorian month */
    SET @DaysBeforeMonth =
        CASE @gm
            WHEN 0  THEN 0
            WHEN 1  THEN 31
            WHEN 2  THEN 59
            WHEN 3  THEN 90
            WHEN 4  THEN 120
            WHEN 5  THEN 151
            WHEN 6  THEN 181
            WHEN 7  THEN 212
            WHEN 8  THEN 243
            WHEN 9  THEN 273
            WHEN 10 THEN 304
            WHEN 11 THEN 334
        END;


    SET @gDayNo =
          365 * @gy
        + (@gy + 3) / 4
        - (@gy + 99) / 100
        + (@gy + 399) / 400
        + @DaysBeforeMonth;


    /* Gregorian leap-year adjustment */
    IF @gm > 1
       AND
       (
            (@OriginalYear % 4 = 0 AND @OriginalYear % 100 <> 0)
            OR
            (@OriginalYear % 400 = 0)
       )
    BEGIN
        SET @gDayNo = @gDayNo + 1;
    END;


    SET @gDayNo = @gDayNo + @gd;

    SET @jDayNo = @gDayNo - 79;

    SET @jNp = @jDayNo / 12053;
    SET @jDayNo = @jDayNo % 12053;

    SET @jy =
          979
        + (33 * @jNp)
        + (4 * (@jDayNo / 1461));

    SET @jDayNo = @jDayNo % 1461;


    IF @jDayNo >= 366
    BEGIN
        SET @jy =
            @jy + ((@jDayNo - 1) / 365);

        SET @jDayNo =
            (@jDayNo - 1) % 365;
    END;


    /* Persian month/day */
    IF @jDayNo < 186
    BEGIN
        SET @jm = (@jDayNo / 31) + 1;
        SET @jd = (@jDayNo % 31) + 1;
    END
    ELSE
    BEGIN
        SET @jm = ((@jDayNo - 186) / 30) + 7;
        SET @jd = ((@jDayNo - 186) % 30) + 1;
    END;


    RETURN
          RIGHT('0000' + CAST(@jy AS VARCHAR(4)), 4)
        + '/'
        + RIGHT('0' + CAST(@jm AS VARCHAR(2)), 2)
        + '/'
        + RIGHT('0' + CAST(@jd AS VARCHAR(2)), 2);
END;
GO



/* =========================================================
   Dimension: dwh.DimDate

   Grain:
   1 row = 1 calendar date

   Main DateKey:
   Gregorian YYYYMMDD

   Example:
   2018-07-15 -> 20180715

   Special Member:
   DateKey = 0 -> Unknown / Not Applicable

   Design:
   One shared dimension contains both Gregorian and Persian
   calendar attributes.

   Facts will reference only DateKey.
   ========================================================= */

IF OBJECT_ID(N'dwh.DimDate', N'U') IS NOT NULL
    DROP TABLE dwh.DimDate;
GO


CREATE TABLE dwh.DimDate
(
    /* ========================
       Core Date
       ======================== */

    DateKey                     INT             NOT NULL,
    DateValue                   DATE            NULL,
    DateLabelEN                 CHAR(10)        NULL,


    /* ========================
       Gregorian Calendar
       ======================== */

    CalendarYear                SMALLINT        NULL,
    CalendarQuarter             TINYINT         NULL,
    QuarterLabelEN              VARCHAR(10)     NULL,

    MonthNumber                 TINYINT         NULL,
    MonthNameEN                 VARCHAR(20)     NULL,
    MonthShortNameEN            VARCHAR(3)      NULL,

    YearMonthKey                INT             NULL,
    YearMonthLabel              CHAR(7)         NULL,

    DayOfMonth                  TINYINT         NULL,
    DayOfYear                   SMALLINT        NULL,

    DayOfWeekNumber             TINYINT         NULL,
    DayNameEN                   VARCHAR(20)     NULL,
    DayNameFA                   NVARCHAR(20)    NULL,

    ISOWeekNumber               TINYINT         NULL,

    IsWeekend                   BIT             NOT NULL,


    /* ========================
       Persian / Jalali Calendar
       ======================== */

    PersianDateKey              INT             NULL,
    PersianDate                 CHAR(10)        NULL,

    PersianYear                 SMALLINT        NULL,
    PersianQuarter              TINYINT         NULL,
    PersianQuarterLabelFA       NVARCHAR(20)    NULL,

    PersianMonthNumber          TINYINT         NULL,
    PersianMonthNameFA          NVARCHAR(20)    NULL,

    PersianYearMonthKey         INT             NULL,
    PersianYearMonthLabel       CHAR(7)         NULL,

    PersianDayOfMonth           TINYINT         NULL,


    CONSTRAINT PK_DimDate
        PRIMARY KEY (DateKey)
);
GO



/* =========================================================
   Unknown Member

   Facts with NULL / unavailable dates will use DateKey = 0.
   ========================================================= */

INSERT INTO dwh.DimDate
(
    DateKey,
    DateValue,
    DateLabelEN,

    CalendarYear,
    CalendarQuarter,
    QuarterLabelEN,

    MonthNumber,
    MonthNameEN,
    MonthShortNameEN,

    YearMonthKey,
    YearMonthLabel,

    DayOfMonth,
    DayOfYear,

    DayOfWeekNumber,
    DayNameEN,
    DayNameFA,

    ISOWeekNumber,
    IsWeekend,

    PersianDateKey,
    PersianDate,
    PersianYear,
    PersianQuarter,
    PersianQuarterLabelFA,

    PersianMonthNumber,
    PersianMonthNameFA,

    PersianYearMonthKey,
    PersianYearMonthLabel,

    PersianDayOfMonth
)
VALUES
(
    0,
    NULL,
    NULL,

    NULL,
    NULL,
    'Unknown',

    NULL,
    'Unknown',
    'UNK',

    NULL,
    NULL,

    NULL,
    NULL,

    NULL,
    'Unknown',
    N'نامشخص',

    NULL,
    0,

    NULL,
    NULL,
    NULL,
    NULL,
    N'نامشخص',

    NULL,
    N'نامشخص',

    NULL,
    NULL,

    NULL
);
GO



/* =========================================================
   Determine Real Source Date Range

   Includes all source date fields that may later connect
   to DimDate from facts.

   Calendar is expanded only to full calendar years.
   Transaction dates themselves are NOT fabricated.
   ========================================================= */

DECLARE
    @MinSourceDate DATE,
    @MaxSourceDate DATE,
    @StartDate DATE,
    @EndDate DATE;


WITH SourceDates AS
(
    /* Orders */

    SELECT
        CAST(order_purchase_timestamp AS DATE) AS DateValue
    FROM stg.orders


    UNION ALL

    SELECT
        CAST(order_approved_at AS DATE)
    FROM stg.orders
    WHERE order_approved_at IS NOT NULL


    UNION ALL

    SELECT
        CAST(order_delivered_carrier_date AS DATE)
    FROM stg.orders
    WHERE order_delivered_carrier_date IS NOT NULL


    UNION ALL

    SELECT
        CAST(order_delivered_customer_date AS DATE)
    FROM stg.orders
    WHERE order_delivered_customer_date IS NOT NULL


    UNION ALL

    SELECT
        order_estimated_delivery_date
    FROM stg.orders
    WHERE order_estimated_delivery_date IS NOT NULL


    /* Order Items */

    UNION ALL

    SELECT
        CAST(shipping_limit_date AS DATE)
    FROM stg.order_items
    WHERE shipping_limit_date IS NOT NULL


    /* Reviews */

    UNION ALL

    SELECT
        CAST(review_creation_date AS DATE)
    FROM stg.reviews
    WHERE review_creation_date IS NOT NULL


    UNION ALL

    SELECT
        CAST(review_answer_timestamp AS DATE)
    FROM stg.reviews
    WHERE review_answer_timestamp IS NOT NULL
)
SELECT
    @MinSourceDate = MIN(DateValue),
    @MaxSourceDate = MAX(DateValue)
FROM SourceDates;


IF @MinSourceDate IS NULL
   OR @MaxSourceDate IS NULL
BEGIN
    THROW 50001,
          'Cannot build DimDate because no source dates were found.',
          1;
END;


SET @StartDate =
    DATEFROMPARTS(
        YEAR(@MinSourceDate),
        1,
        1
    );


SET @EndDate =
    DATEFROMPARTS(
        YEAR(@MaxSourceDate),
        12,
        31
    );



/* =========================================================
   Generate Calendar
   ========================================================= */

WITH Calendar AS
(
    SELECT
        @StartDate AS DateValue

    UNION ALL

    SELECT
        DATEADD(
            DAY,
            1,
            DateValue
        )
    FROM Calendar

    WHERE DateValue < @EndDate
),
PersianConversion AS
(
    SELECT
        DateValue,

        dwh.fn_GregorianToPersianDate(
            DateValue
        ) AS PersianDate

    FROM Calendar
),
DateParts AS
(
    SELECT
        DateValue,
        PersianDate,

        CAST(
            SUBSTRING(PersianDate, 1, 4)
            AS INT
        ) AS PersianYear,

        CAST(
            SUBSTRING(PersianDate, 6, 2)
            AS INT
        ) AS PersianMonth,

        CAST(
            SUBSTRING(PersianDate, 9, 2)
            AS INT
        ) AS PersianDay,

        /* Monday = 1 ... Sunday = 7 */
        (
            DATEDIFF(
                DAY,
                CONVERT(DATE, '19000101'),
                DateValue
            ) % 7
        ) + 1 AS ISOWeekDay

    FROM PersianConversion
)
INSERT INTO dwh.DimDate
(
    DateKey,
    DateValue,
    DateLabelEN,

    CalendarYear,
    CalendarQuarter,
    QuarterLabelEN,

    MonthNumber,
    MonthNameEN,
    MonthShortNameEN,

    YearMonthKey,
    YearMonthLabel,

    DayOfMonth,
    DayOfYear,

    DayOfWeekNumber,
    DayNameEN,
    DayNameFA,

    ISOWeekNumber,
    IsWeekend,

    PersianDateKey,
    PersianDate,
    PersianYear,

    PersianQuarter,
    PersianQuarterLabelFA,

    PersianMonthNumber,
    PersianMonthNameFA,

    PersianYearMonthKey,
    PersianYearMonthLabel,

    PersianDayOfMonth
)
SELECT

    /* DateKey */
      YEAR(DateValue) * 10000
    + MONTH(DateValue) * 100
    + DAY(DateValue),


    DateValue,


    CONVERT(
        CHAR(10),
        DateValue,
        23
    ),


    /* Gregorian */
    YEAR(DateValue),

    DATEPART(
        QUARTER,
        DateValue
    ),

    CONCAT(
        'Q',
        DATEPART(
            QUARTER,
            DateValue
        )
    ),


    MONTH(DateValue),


    CASE MONTH(DateValue)
        WHEN 1  THEN 'January'
        WHEN 2  THEN 'February'
        WHEN 3  THEN 'March'
        WHEN 4  THEN 'April'
        WHEN 5  THEN 'May'
        WHEN 6  THEN 'June'
        WHEN 7  THEN 'July'
        WHEN 8  THEN 'August'
        WHEN 9  THEN 'September'
        WHEN 10 THEN 'October'
        WHEN 11 THEN 'November'
        WHEN 12 THEN 'December'
    END,


    CASE MONTH(DateValue)
        WHEN 1  THEN 'Jan'
        WHEN 2  THEN 'Feb'
        WHEN 3  THEN 'Mar'
        WHEN 4  THEN 'Apr'
        WHEN 5  THEN 'May'
        WHEN 6  THEN 'Jun'
        WHEN 7  THEN 'Jul'
        WHEN 8  THEN 'Aug'
        WHEN 9  THEN 'Sep'
        WHEN 10 THEN 'Oct'
        WHEN 11 THEN 'Nov'
        WHEN 12 THEN 'Dec'
    END,


      YEAR(DateValue) * 100
    + MONTH(DateValue),


    CONCAT(
        YEAR(DateValue),
        '-',
        RIGHT(
            '0' + CAST(
                MONTH(DateValue)
                AS VARCHAR(2)
            ),
            2
        )
    ),


    DAY(DateValue),

    DATEPART(
        DAYOFYEAR,
        DateValue
    ),


    ISOWeekDay,


    CASE ISOWeekDay
        WHEN 1 THEN 'Monday'
        WHEN 2 THEN 'Tuesday'
        WHEN 3 THEN 'Wednesday'
        WHEN 4 THEN 'Thursday'
        WHEN 5 THEN 'Friday'
        WHEN 6 THEN 'Saturday'
        WHEN 7 THEN 'Sunday'
    END,


    CASE ISOWeekDay
        WHEN 1 THEN N'دوشنبه'
        WHEN 2 THEN N'سه‌شنبه'
        WHEN 3 THEN N'چهارشنبه'
        WHEN 4 THEN N'پنجشنبه'
        WHEN 5 THEN N'جمعه'
        WHEN 6 THEN N'شنبه'
        WHEN 7 THEN N'یکشنبه'
    END,


    DATEPART(
        ISO_WEEK,
        DateValue
    ),


    /*
       Weekend follows the source business context:
       Brazil -> Saturday / Sunday.

       Persian UI does NOT change source business semantics.
    */
    CASE
        WHEN ISOWeekDay IN (6, 7)
            THEN 1
        ELSE 0
    END,


    /* Persian DateKey */
      PersianYear * 10000
    + PersianMonth * 100
    + PersianDay,


    PersianDate,

    PersianYear,


    ((PersianMonth - 1) / 3) + 1,


    CONCAT(
        N'فصل ',
        ((PersianMonth - 1) / 3) + 1
    ),


    PersianMonth,


    CASE PersianMonth
        WHEN 1  THEN N'فروردین'
        WHEN 2  THEN N'اردیبهشت'
        WHEN 3  THEN N'خرداد'
        WHEN 4  THEN N'تیر'
        WHEN 5  THEN N'مرداد'
        WHEN 6  THEN N'شهریور'
        WHEN 7  THEN N'مهر'
        WHEN 8  THEN N'آبان'
        WHEN 9  THEN N'آذر'
        WHEN 10 THEN N'دی'
        WHEN 11 THEN N'بهمن'
        WHEN 12 THEN N'اسفند'
    END,


      PersianYear * 100
    + PersianMonth,


    CONCAT(
        PersianYear,
        '/',
        RIGHT(
            '0' + CAST(
                PersianMonth
                AS VARCHAR(2)
            ),
            2
        )
    ),


    PersianDay

FROM DateParts
OPTION (MAXRECURSION 0);
GO



/* =========================================================
   Supporting Indexes
   ========================================================= */

CREATE UNIQUE INDEX UX_DimDate_DateValue
    ON dwh.DimDate(DateValue)
    WHERE DateValue IS NOT NULL;
GO


CREATE UNIQUE INDEX UX_DimDate_PersianDateKey
    ON dwh.DimDate(PersianDateKey)
    WHERE PersianDateKey IS NOT NULL;
GO



/* =========================================================
   Validation 1:
   General Dimension Statistics
   ========================================================= */

SELECT
    COUNT(*) AS [RowCount],

    MIN(DateValue) AS MinGregorianDate,
    MAX(DateValue) AS MaxGregorianDate,

    MIN(
        CASE
            WHEN DateKey <> 0
            THEN DateKey
        END
    ) AS MinDateKey,

    MAX(DateKey) AS MaxDateKey,

    MIN(PersianDate) AS MinPersianDate,
    MAX(PersianDate) AS MaxPersianDate

FROM dwh.DimDate;
GO



/* =========================================================
   Validation 2:
   Unknown Member
   ========================================================= */

SELECT
    *
FROM dwh.DimDate
WHERE DateKey = 0;
GO



/* =========================================================
   Validation 3:
   Known Nowruz Conversion Tests
   ========================================================= */

WITH TestDates AS
(
    SELECT *
    FROM
    (
        VALUES
            (CAST('2016-03-20' AS DATE), '1395/01/01'),
            (CAST('2017-03-21' AS DATE), '1396/01/01'),
            (CAST('2018-03-21' AS DATE), '1397/01/01'),
            (CAST('2019-03-21' AS DATE), '1398/01/01'),
            (CAST('2020-03-20' AS DATE), '1399/01/01')
    )
    x
    (
        GregorianDate,
        ExpectedPersianDate
    )
)
SELECT
    GregorianDate,
    ExpectedPersianDate,

    dwh.fn_GregorianToPersianDate(
        GregorianDate
    ) AS ActualPersianDate,

    CASE
        WHEN
            dwh.fn_GregorianToPersianDate(
                GregorianDate
            ) = ExpectedPersianDate
        THEN 'PASS'
        ELSE 'FAIL'
    END AS ValidationStatus

FROM TestDates
ORDER BY GregorianDate;
GO



/* =========================================================
   Validation 4:
   Verify every source date maps to DimDate
   ========================================================= */

WITH SourceDates AS
(
    SELECT CAST(order_purchase_timestamp AS DATE) AS DateValue
    FROM stg.orders

    UNION

    SELECT CAST(order_approved_at AS DATE)
    FROM stg.orders
    WHERE order_approved_at IS NOT NULL

    UNION

    SELECT CAST(order_delivered_carrier_date AS DATE)
    FROM stg.orders
    WHERE order_delivered_carrier_date IS NOT NULL

    UNION

    SELECT CAST(order_delivered_customer_date AS DATE)
    FROM stg.orders
    WHERE order_delivered_customer_date IS NOT NULL

    UNION

    SELECT order_estimated_delivery_date
    FROM stg.orders
    WHERE order_estimated_delivery_date IS NOT NULL

    UNION

    SELECT CAST(shipping_limit_date AS DATE)
    FROM stg.order_items
    WHERE shipping_limit_date IS NOT NULL

    UNION

    SELECT CAST(review_creation_date AS DATE)
    FROM stg.reviews
    WHERE review_creation_date IS NOT NULL

    UNION

    SELECT CAST(review_answer_timestamp AS DATE)
    FROM stg.reviews
    WHERE review_answer_timestamp IS NOT NULL
)
SELECT
    COUNT(*) AS MissingSourceDatesInDimDate
FROM SourceDates s
LEFT JOIN dwh.DimDate d
    ON s.DateValue = d.DateValue
WHERE d.DateKey IS NULL;
GO



/* =========================================================
   Validation 5:
   Sample Bilingual Calendar
   ========================================================= */

SELECT TOP (20)

    DateKey,
    DateValue,

    CalendarYear,
    MonthNameEN,
    DayNameEN,

    PersianDateKey,
    PersianDate,
    PersianYear,
    PersianMonthNameFA,
    DayNameFA,

    IsWeekend

FROM dwh.DimDate
WHERE DateKey <> 0
ORDER BY DateValue;
GO