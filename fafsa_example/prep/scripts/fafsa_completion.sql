/* Pull student-level FAFSA completion data for Delaware high schools
   Final grain: one row per SchoolYear + StudentID + SchoolCode
   FAFSA selection rule: most recent ApplicationReceiptDate
*/

DECLARE @SchoolYear int = NULL;              -- NULL = all years
DECLARE @SchoolName nvarchar(200) = NULL;    -- NULL = all schools

/* Drop temp tables so the query can be run more than once safely */
IF OBJECT_ID('tempdb..#asofdate')       IS NOT NULL DROP TABLE #asofdate;
IF OBJECT_ID('tempdb..#twelve_raw')     IS NOT NULL DROP TABLE #twelve_raw;
IF OBJECT_ID('tempdb..#twelve')         IS NOT NULL DROP TABLE #twelve;
IF OBJECT_ID('tempdb..#latest_isir')    IS NOT NULL DROP TABLE #latest_isir;


/* 1) Latest enrollment snapshot date by school year */
SELECT
    SchoolYear,
    MAX(AsOf) AS maxasof
INTO #asofdate
FROM [PUBLICREPORTMART].[details].[P20_STUDENT_ENROLLMENT_POINT_IN_TIME]
WHERE (@SchoolYear IS NULL OR SchoolYear = @SchoolYear)
GROUP BY SchoolYear;

CREATE INDEX IX_asofdate
    ON #asofdate (SchoolYear, maxasof);


/* 2) Pull current grade 12 enrollment snapshot */
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
    pit.Geography,
    pit.ZipCode,
    pit.Gender,
    pit.RaceEDEN AS RaceReportCode,   -- stored value is actually the race report code
    pit.LowIncome,
    pit.Medicaid,
    pit.SPEDCode,
    pit.CD504,
    pit.ELL,
    pit.Migrant,
    pit.Homeless,
    pit.FosterCare,
    pit.MilitaryDep,
    pit.Immersion,
    pit.Grade,
    pit.YearInHS,
    pit.GradeRepeater,
    pit.GradeSkipper
INTO #twelve_raw
FROM [PUBLICREPORTMART].[details].[P20_STUDENT_ENROLLMENT_POINT_IN_TIME] AS pit
JOIN CodeLibrary.dbo.School AS sc
    ON pit.SchoolCode = sc.SchoolCode
   AND pit.SchoolYear = sc.SchoolYear
JOIN CodeLibrary.dbo.District AS dt
    ON pit.DistrictCode = dt.DistrictCode
   AND pit.SchoolYear = dt.SchoolYear
JOIN #asofdate AS ad
    ON ad.SchoolYear = pit.SchoolYear
   AND pit.AsOf = ad.maxasof
WHERE (@SchoolYear IS NULL OR pit.SchoolYear = @SchoolYear)
  AND pit.Grade = '12'
  AND pit.SchoolCode NOT IN (516,530,650,545,655,750,689,522,630,538,108,537,514,540,977,728);

CREATE INDEX IX_twelve_raw
    ON #twelve_raw (SchoolYear, StudentID, SchoolCode);


/* 3) Enforce one row per SchoolYear + StudentID + SchoolCode */
WITH ranked_twelve AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY SchoolYear, StudentID, SchoolCode
            ORDER BY
                LastName,
                FirstName,
                BirthDate
        ) AS rn
    FROM #twelve_raw
)
SELECT
    SchoolYear,
    LastName,
    FirstName,
    BirthDate,
    StudentID,
    SchoolName,
    SchoolCode,
    DistrictName,
    DistrictCode,
    Geography,
    ZipCode,
    Gender,
    RaceReportCode,
    LowIncome,
    Medicaid,
    SPEDCode,
    CD504,
    ELL,
    Migrant,
    Homeless,
    FosterCare,
    MilitaryDep,
    Immersion,
    Grade,
    YearInHS,
    GradeRepeater,
    GradeSkipper
INTO #twelve
FROM ranked_twelve
WHERE rn = 1;

CREATE INDEX IX_twelve
    ON #twelve (SchoolYear, StudentID, SchoolCode, LastName, FirstName, BirthDate);


/* 4) Keep one ISIR row per student/year based on most recent ApplicationReceiptDate
      Tie-breakers are TransactionReceiptDate and ISIRID */
WITH ranked_isir AS (
    SELECT
        i.ISIRYear,
        i.ISIRID,
        i.StudentFirstName,
        i.StudentLastName,
        i.StudentDateOfBirth,
        i.ApplicationReceiptDate,
        i.TransactionReceiptDate,
        ROW_NUMBER() OVER (
            PARTITION BY
                i.ISIRYear,
                i.StudentFirstName,
                i.StudentLastName,
                i.StudentDateOfBirth
            ORDER BY
                CASE WHEN i.ApplicationReceiptDate IS NULL THEN 1 ELSE 0 END,
                i.ApplicationReceiptDate DESC,
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
    ApplicationReceiptDate
INTO #latest_isir
FROM ranked_isir
WHERE rn = 1;

CREATE INDEX IX_latest_isir
    ON #latest_isir (ISIRYear, StudentLastName, StudentFirstName, StudentDateOfBirth);


/* 5) Final output
      One row per SchoolYear + StudentID + SchoolCode
      No DISTINCT needed */
SELECT
    [asOf] = CAST(GETDATE() AS date),
    t.SchoolYear,
    t.StudentID,
    t.BirthDate,
    t.SchoolName,
    t.SchoolCode,
    t.DistrictName,
    t.DistrictCode,
    t.Geography,
    t.ZipCode,
    t.Gender,
    COALESCE(d.RaceReportTitle, CAST(t.RaceReportCode AS varchar(50))) AS RaceReportTitle,
    t.LowIncome,
    t.Medicaid,
    t.SPEDCode,
    se.SpEdDefinition,
    t.CD504,
    t.ELL,
    t.Migrant,
    t.Homeless,
    t.FosterCare,
    t.MilitaryDep,
    t.Immersion,
    t.Grade,
    t.YearInHS,
    t.GradeRepeater,
    t.GradeSkipper,
    i.ApplicationReceiptDate,
    CASE
        WHEN i.ApplicationReceiptDate IS NOT NULL THEN 'Y'
        ELSE 'N'
    END AS CompletedFAFSA
FROM #twelve AS t
LEFT JOIN #latest_isir AS i
    ON  i.ISIRYear = t.SchoolYear
    AND i.StudentLastName = t.LastName
    AND i.StudentFirstName = t.FirstName
    AND i.StudentDateOfBirth = t.BirthDate
LEFT JOIN CodeLibrary.dbo.RaceReportCodeEDEN AS d
    ON CAST(t.RaceReportCode AS varchar(50)) = CAST(d.RaceReportCode AS varchar(50))
LEFT JOIN CodeLibrary.dbo.SpEdCode AS se
    ON t.SPEDCode = se.SpEd
WHERE (@SchoolName IS NULL OR t.SchoolName = @SchoolName)
ORDER BY
    t.SchoolYear DESC,
    t.DistrictName,
    t.SchoolName,
    t.StudentID;