/*
    FAFSA completion for high school seniors

    What this query does, in normal-human language:
    1) Find the latest enrollment snapshot for each school in each year.
    2) Grab current 12th graders from that snapshot.
    3) Pick one latest ISIR row per student/year.
    4) Join the two and say whether the student completed a FAFSA.

    Changes I made from Ches's source query:
      1) Latest enrollment snapshot is by SchoolYear + SchoolCode
      3) ISIR ties get one winner via ROW_NUMBER(), with ISIRID DESC as the tie-breaker
      4) Final DISTINCT is removed

    Intentionally left alone:
      - FAFSA matching still uses raw first name + last name + DOB
      - @SchoolName filtering still happens in the final query
      - Final ORDER BY is still here because apparently we enjoy readable output
*/

SET NOCOUNT ON;  -- Stops narrating every row count.

DECLARE @SchoolYear  int           = NULL;  -- NULL = all years; set a year like 2026 if you want to be specific.
DECLARE @SchoolName  nvarchar(200) = NULL;  -- NULL = all schools; set one school name if you're feeling selective.
DECLARE @RunDate     date          = CAST(SYSDATETIME() AS date);  -- One run date for the whole query just in case you forgot what today is.

/*
    Temp table cleanup.
    Translation: if you run this twice, we don't want tempdb dragging old stuff into the query.
*/
IF OBJECT_ID('tempdb..#latest_isir') IS NOT NULL DROP TABLE #latest_isir;
IF OBJECT_ID('tempdb..#asofdate')    IS NOT NULL DROP TABLE #asofdate;
IF OBJECT_ID('tempdb..#twelve')      IS NOT NULL DROP TABLE #twelve;

/*
    1) Get the latest enrollment snapshot for each school in each year.
*/
SELECT
    pit.SchoolYear,
    pit.SchoolCode,
    MAX(pit.AsOf) AS maxasof
INTO #asofdate
FROM [PUBLICREPORTMART].[details].[P20_STUDENT_ENROLLMENT_POINT_IN_TIME] AS pit
WHERE (@SchoolYear IS NULL OR pit.SchoolYear = @SchoolYear)
GROUP BY
    pit.SchoolYear,
    pit.SchoolCode
OPTION (RECOMPILE);

/*
    Clustered index because this table is tiny-ish and we join on these exact columns.
*/
CREATE CLUSTERED INDEX CIX_asofdate
    ON #asofdate (SchoolYear, SchoolCode, maxasof);

/*
    2) Pull current grade 12 enrollment from the latest snapshot.

    This is the senior list.
    We join to school and district reference tables so the final output is not just a pile of codes.
*/
SELECT
    pit.SchoolYear,
    pit.LastName,
    pit.FirstName,
    pit.BirthDate,
    pit.StudentID,
    sc.SchoolName,
    pit.SchoolCode,
    dt.DistrictName,
    pit.DistrictCode,
    pit.LowIncome,
    pit.SWD
INTO #twelve
FROM [PUBLICREPORTMART].[details].[P20_STUDENT_ENROLLMENT_POINT_IN_TIME] AS pit
INNER JOIN CodeLibrary.dbo.School AS sc
    ON sc.SchoolCode = pit.SchoolCode
   AND sc.SchoolYear = pit.SchoolYear
INNER JOIN CodeLibrary.dbo.District AS dt
    ON dt.DistrictCode = pit.DistrictCode
   AND dt.SchoolYear = pit.SchoolYear
INNER JOIN #asofdate AS ad
    ON ad.SchoolYear = pit.SchoolYear
   AND ad.SchoolCode = pit.SchoolCode
   AND pit.AsOf = ad.maxasof
WHERE (@SchoolYear IS NULL OR pit.SchoolYear = @SchoolYear)
  AND pit.Grade = '12'
  AND pit.SchoolCode NOT IN (516,530,650,545,655,750,689,522,630,538,108,537,514,540,977,728)
OPTION (RECOMPILE);

/*
    Supporting index for the final FAFSA match.
    We join on SchoolYear + raw name + DOB, so that is what gets indexed. Not the best but it's what we've got...
*/
CREATE INDEX IX_twelve_match
    ON #twelve (SchoolYear, LastName, FirstName, BirthDate);

/*
    3) Pick one latest ISIR row per student/year.

    Students can have multiple ISIR transactions.
    We rank rows newest-to-oldest by TransactionReceiptDate.
    If there is a tie on that date, the higher ISIRID wins.
*/
;WITH isir_ranked AS (
    SELECT
        i.ISIRYear,
        i.StudentFirstName,
        i.StudentLastName,
        i.StudentDateOfBirth,
        i.RejectReasonCodes,
        i.StudentEmailAddress,
        i.ApplicationReceiptDate,
        i.TransactionReceiptDate,
        i.ISIRID,
        ROW_NUMBER() OVER (
            PARTITION BY
                i.ISIRYear,
                i.StudentFirstName,
                i.StudentLastName,
                i.StudentDateOfBirth
            ORDER BY
                i.TransactionReceiptDate DESC,
                i.ISIRID DESC
        ) AS rn
    FROM [DOESISDB02\DB2].[HigherEdV3].[dbo].[ISIR] AS i
    WHERE (@SchoolYear IS NULL OR i.ISIRYear = @SchoolYear)
)
SELECT
    ISIRYear,
    StudentFirstName,
    StudentLastName,
    StudentDateOfBirth,
    RejectReasonCodes,
    StudentEmailAddress,
    ApplicationReceiptDate
INTO #latest_isir
FROM isir_ranked
WHERE rn = 1
OPTION (RECOMPILE);

CREATE INDEX IX_latest_isir_match
    ON #latest_isir (ISIRYear, StudentLastName, StudentFirstName, StudentDateOfBirth);

/*
    4) Final join.

    Left join is important here:
    every senior should stay in the output even if we do not find a matching ISIR row.
    CompletedFAFSA = Y when ApplicationReceiptDate exists, else N.
*/
SELECT
    @RunDate AS AsOf,
    t.SchoolYear,
    t.StudentID,
    t.LastName,
    t.FirstName,
    t.BirthDate,
    t.SchoolName,
    t.SchoolCode,
    t.DistrictName,
    t.DistrictCode,
    i.RejectReasonCodes,
    i.ApplicationReceiptDate,
    i.StudentEmailAddress,
    CASE
        WHEN i.ApplicationReceiptDate IS NOT NULL THEN 'Y'
        ELSE 'N'
    END AS CompletedFAFSA
FROM #twelve AS t
LEFT JOIN #latest_isir AS i
    ON i.ISIRYear = t.SchoolYear
   AND i.StudentLastName = t.LastName
   AND i.StudentFirstName = t.FirstName
   AND i.StudentDateOfBirth = t.BirthDate
WHERE (@SchoolName IS NULL OR t.SchoolName = @SchoolName)
ORDER BY
    t.SchoolYear DESC,
    t.DistrictName,
    t.SchoolName,
    t.LastName,
    t.FirstName;

/*
    Tiny caveat for future-you:
    matching on raw first/last name + DOB is the best available key in this query,
    but it is still a little janky in the way all name matching is a little janky (it's what was passed down to me).
    If you ever get a stronger crosswalk key, use it and never look back.
*/
