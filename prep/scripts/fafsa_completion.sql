USE [PUBLICREPORTMART];
GO

/* =============================================================================
   FAFSA COMPLETION APP INPUT

   PURPOSE
   -------
   Build the summarized source file used by the FAFSA Completion Shiny app.

   DESIGN
   ------
   - FAFSA_Completers_SchoolLevel supplies the canonical reporting rules.
   - The student-level structure is retained long enough to assign each completed
     senior to ApplicationReceiptMonth before aggregation.

   R / SHINY HANDLES
   -----------------
   - zero-completion months
   - cumulative completions and rates
   - current-school display rules
   - visualization
============================================================================= */

WITH

/* ==== 1. LATEST ENROLLMENT SNAPSHOT ======================================= */
latest_enrollment_date AS (
    SELECT
        SchoolYear,
        MAX(AsOf) AS EnrollmentAsOf
    FROM [PUBLICREPORTMART].[details].[P20_STUDENT_ENROLLMENT_POINT_IN_TIME]
    WHERE SchoolYear >= 2015
    GROUP BY SchoolYear
),

/* ==== 2. GRADE 12 REPORTING COHORT ======================================== */
-- Match FAFSA_Completers_SchoolLevel:
-- latest AsOf + Grade 12 + GradeSpan != '6-8'.
-- Do NOT use the StudentLevel report's explicit school-code exclusion list.
enrollment_cohort AS (
    SELECT
        pit.SchoolYear,
        d.EnrollmentAsOf,
        pit.StudentID,
        pit.LastName,
        pit.FirstName,
        pit.BirthDate,
        CAST(pit.DistrictCode AS varchar(20)) AS SourceDistrictCode,
        dt.DistrictName AS SourceDistrictName,
        CAST(pit.SchoolCode AS varchar(20)) AS SchoolCode,
        sc.SchoolName
    FROM [PUBLICREPORTMART].[details].[P20_STUDENT_ENROLLMENT_POINT_IN_TIME] pit
    INNER JOIN latest_enrollment_date d
        ON pit.SchoolYear = d.SchoolYear
       AND pit.AsOf = d.EnrollmentAsOf
    INNER JOIN CodeLibrary.dbo.School sc
        ON pit.SchoolYear = sc.SchoolYear
       AND pit.SchoolCode = sc.SchoolCode
    INNER JOIN CodeLibrary.dbo.District dt
        ON pit.SchoolYear = dt.SchoolYear
       AND pit.DistrictCode = dt.DistrictCode
    WHERE pit.Grade = '12'
      AND sc.GradeSpan <> '6-8'
),

/* ==== 3. REPORTING LEA ==================================================== */
-- Reassign the two charter schools before LEA aggregation.
-- Historical schools remain in the reporting population.
reporting_cohort AS (
    SELECT
        SchoolYear,
        EnrollmentAsOf,
        StudentID,
        LastName,
        FirstName,
        BirthDate,
        CASE
            WHEN SchoolCode = '295' THEN '70'
            WHEN SchoolCode = '578' THEN '79'
            ELSE SourceDistrictCode
        END AS DistrictCode,
        CASE
            WHEN SchoolCode = '295' THEN 'Charter School of Wilmington'
            WHEN SchoolCode = '578' THEN 'Delaware Military Academy'
            ELSE SourceDistrictName
        END AS DistrictName,
        SchoolCode,
        SchoolName
    FROM enrollment_cohort
),

/* ==== 4. LATEST FAFSA RECORD ============================================== */
-- Match FAFSA_Completers_SchoolLevel:
-- MAX(ISIRID) by ISIRYear + FirstName + LastName + DOB.
latest_isir AS (
    SELECT
        ISIRYear,
        StudentFirstName,
        StudentLastName,
        StudentDateOfBirth,
        MAX(ISIRID) AS LatestISIRID
    FROM [DOESISDB02\DB2].[HigherEdV3].[dbo].[ISIR]
    WHERE ISIRYear >= 2015
    GROUP BY
        ISIRYear,
        StudentFirstName,
        StudentLastName,
        StudentDateOfBirth
),

selected_isir AS (
    SELECT
        i.ISIRYear,
        i.StudentFirstName,
        i.StudentLastName,
        i.StudentDateOfBirth,
        i.ApplicationReceiptDate
    FROM latest_isir l
    INNER JOIN [DOESISDB02\DB2].[HigherEdV3].[dbo].[ISIR] i
        ON l.LatestISIRID = i.ISIRID
),

/* ==== 5. MATCH FAFSA TO THE GRADE 12 COHORT =============================== */
-- LEFT JOIN keeps unmatched seniors in the denominator.
student_fafsa AS (
    SELECT
        e.SchoolYear,
        e.EnrollmentAsOf,
        e.StudentID,
        e.DistrictCode,
        e.DistrictName,
        e.SchoolCode,
        e.SchoolName,
        CASE
            WHEN i.ApplicationReceiptDate IS NOT NULL THEN
                DATEFROMPARTS(
                    YEAR(i.ApplicationReceiptDate),
                    MONTH(i.ApplicationReceiptDate),
                    1
                )
        END AS ApplicationReceiptMonth
    FROM reporting_cohort e
    LEFT JOIN selected_isir i
        ON e.SchoolYear = i.ISIRYear
       AND e.LastName = i.StudentLastName
       AND e.FirstName = i.StudentFirstName
       AND e.BirthDate = i.StudentDateOfBirth
),

/* ==== 6. CREATE SCHOOL / LEA / STATE REPORTING LEVELS ===================== */
reporting_levels AS (
    SELECT
        'school' AS level,
        EnrollmentAsOf,
        SchoolYear,
        StudentID,
        DistrictCode,
        DistrictName,
        SchoolCode,
        SchoolName,
        ApplicationReceiptMonth
    FROM student_fafsa

    UNION ALL

    SELECT
        'lea' AS level,
        EnrollmentAsOf,
        SchoolYear,
        StudentID,
        DistrictCode,
        DistrictName,
        'All Schools' AS SchoolCode,
        'All Schools' AS SchoolName,
        ApplicationReceiptMonth
    FROM student_fafsa

    UNION ALL

    SELECT
        'state' AS level,
        EnrollmentAsOf,
        SchoolYear,
        StudentID,
        'All LEAs' AS DistrictCode,
        'All LEAs' AS DistrictName,
        'All Schools' AS SchoolCode,
        'All Schools' AS SchoolName,
        ApplicationReceiptMonth
    FROM student_fafsa
),

/* ==== 7. SENIOR DENOMINATORS ============================================== */
entities AS (
    SELECT
        level,
        EnrollmentAsOf,
        SchoolYear,
        DistrictCode,
        DistrictName,
        SchoolCode,
        SchoolName,
        COUNT(DISTINCT StudentID) AS seniors
    FROM reporting_levels
    GROUP BY
        level,
        EnrollmentAsOf,
        SchoolYear,
        DistrictCode,
        DistrictName,
        SchoolCode,
        SchoolName
),

/* ==== 8. ACTUAL MONTHLY FAFSA COMPLETIONS ================================= */
-- Preserve only months that actually occur in the source data.
monthly_completions AS (
    SELECT
        level,
        SchoolYear,
        DistrictCode,
        SchoolCode,
        ApplicationReceiptMonth,
        COUNT(DISTINCT StudentID) AS completed_this_month
    FROM reporting_levels
    WHERE ApplicationReceiptMonth IS NOT NULL
    GROUP BY
        level,
        SchoolYear,
        DistrictCode,
        SchoolCode,
        ApplicationReceiptMonth
)

/* ==== 9. APP-READY SOURCE OUTPUT ========================================== */
SELECT
    CAST(GETDATE() AS date) AS DataAsOf,
    e.EnrollmentAsOf,
    e.level,
    e.SchoolYear,
    e.DistrictCode,
    e.DistrictName,
    e.SchoolCode,
    e.SchoolName,
    mc.ApplicationReceiptMonth,
    e.seniors,
    COALESCE(mc.completed_this_month, 0) AS completed_this_month
FROM entities e
LEFT JOIN monthly_completions mc
    ON e.level = mc.level
   AND e.SchoolYear = mc.SchoolYear
   AND e.DistrictCode = mc.DistrictCode
   AND e.SchoolCode = mc.SchoolCode
ORDER BY
    e.SchoolYear DESC,
    CASE e.level
        WHEN 'school' THEN 1
        WHEN 'lea' THEN 2
        WHEN 'state' THEN 3
    END,
    e.DistrictName,
    e.SchoolName,
    mc.ApplicationReceiptMonth;
