-- KPI 2: Imaging Order Volume (daily, by facility and procedure)
--
-- The "is it being used, and is usage growing?" trend card. One row per
-- facility x day x procedure, with the lifecycle status mix for that bucket.
--
-- Parameters: {{start_date}}, {{end_date}} (IST dates, inclusive), {{facility_id}} (optional)
WITH
  bounds AS (
    SELECT
      ({{start_date}}::DATE)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata'   AS period_start,
      ({{end_date}}::DATE + 1)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata' AS period_end
  ),
  orders AS (
    SELECT
      COALESCE(sr.facility_id, e.facility_id)                                   AS facility_id,
      (ist.created_date AT TIME ZONE 'Asia/Kolkata')::DATE                      AS order_date,
      COALESCE(ad.title, sr.title, 'Unspecified procedure')                     AS procedure_title,
      COALESCE(rc.title, 'Uncategorised')                                       AS procedure_category,
      ist.status                                                                AS study_status,
      sr.priority                                                               AS priority,
      e.encounter_class                                                         AS encounter_class,
      ist.id                                                                    AS imaging_study_pk,
      ist.patient_id,
      ist.accession_number,
      EXISTS (
        SELECT 1 FROM care_radiology_dicomstudy ds
        WHERE ds.imaging_study_id = ist.id AND ds.deleted = FALSE AND ds.is_archived = FALSE
      )                                                                         AS has_images,
      EXISTS (
        SELECT 1 FROM emr_diagnosticreport dr
        WHERE dr.service_request_id = ist.service_request_id
          AND dr.deleted = FALSE AND dr.status = 'final'
      )                                                                         AS has_final_report
    FROM care_radiology_imagingstudy ist
    CROSS JOIN bounds b
    LEFT JOIN emr_servicerequest sr      ON sr.id = ist.service_request_id AND sr.deleted = FALSE
    JOIN emr_encounter e                 ON e.id = ist.encounter_id
    LEFT JOIN emr_activitydefinition ad  ON ad.id = sr.activity_definition_id AND ad.deleted = FALSE
    LEFT JOIN emr_resourcecategory rc    ON rc.id = ad.category_id AND rc.deleted = FALSE
    WHERE ist.deleted = FALSE
      AND ist.created_date >= b.period_start
      AND ist.created_date <  b.period_end
  )
SELECT
  f.external_id                                                         AS "FACILITY_ID",
  f.name                                                                AS "FACILITY_NAME",
  o.order_date                                                          AS "ORDER_DATE",
  o.procedure_category                                                  AS "PROCEDURE_CATEGORY",
  o.procedure_title                                                     AS "PROCEDURE",
  COUNT(*)                                                              AS "ORDERS",
  COUNT(DISTINCT o.patient_id)                                          AS "PATIENTS",
  COUNT(*) FILTER (WHERE o.encounter_class = 'amb')                     AS "OUTPATIENT_ORDERS",
  COUNT(*) FILTER (WHERE o.priority IN ('urgent', 'asap', 'stat'))      AS "URGENT_ORDERS",
  COUNT(*) FILTER (WHERE o.study_status = 'ACTIVE')                     AS "STATUS_ACTIVE",
  COUNT(*) FILTER (WHERE o.study_status = 'IN_PROGRESS')                AS "STATUS_IN_PROGRESS",
  COUNT(*) FILTER (WHERE o.study_status = 'COMPLETED')                  AS "STATUS_COMPLETED",
  COUNT(*) FILTER (WHERE o.study_status = 'CANCELLED')                  AS "STATUS_CANCELLED",
  COUNT(*) FILTER (WHERE o.has_images)                                  AS "WITH_IMAGES",
  COUNT(*) FILTER (WHERE o.has_final_report)                            AS "WITH_FINAL_REPORT",
  COUNT(*) FILTER (WHERE o.accession_number IS NULL)                    AS "MISSING_ACCESSION",
  ROUND(100.0 * COUNT(*) FILTER (WHERE o.has_images) / NULLIF(COUNT(*), 0), 1)
                                                                        AS "IMAGED_PCT",
  ROUND(100.0 * COUNT(*) FILTER (WHERE o.has_final_report) / NULLIF(COUNT(*), 0), 1)
                                                                        AS "REPORTED_PCT"
FROM orders o
JOIN facility_facility f ON f.id = o.facility_id AND f.deleted = FALSE
WHERE TRUE
  [[AND f.external_id::TEXT = {{facility_id}}]]
GROUP BY
  f.external_id, f.name, o.order_date, o.procedure_category, o.procedure_title
ORDER BY
  "ORDER_DATE" DESC, "ORDERS" DESC, "FACILITY_NAME";
