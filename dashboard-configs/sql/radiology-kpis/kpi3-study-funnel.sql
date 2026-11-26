-- KPI 3: Imaging Study Funnel (order -> accession -> scan -> images -> report)
--
-- Where orders fall out of the pipeline, per facility. Each stage is a subset of
-- the one before it, so the drop between two columns is the leak to investigate.
--
-- Stage sources:
--   ORDERED        care_radiology_imagingstudy row (created by the ServiceRequest post_save signal)
--   ACCESSIONED    accession_number set by the assign_accession_number Celery task
--   SCAN_STARTED   MPPS webhook log with study_status IN_PROGRESS, or a study past ACTIVE
--   IMAGES_STORED  at least one non-archived care_radiology_dicomstudy
--   REPORT_DRAFTED emr_diagnosticreport in any status
--   REPORT_FINAL   emr_diagnosticreport with status 'final'
--
-- Parameters: {{start_date}}, {{end_date}} (IST dates, inclusive), {{facility_id}} (optional)
WITH
  bounds AS (
    SELECT
      ({{start_date}}::DATE)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata'   AS period_start,
      ({{end_date}}::DATE + 1)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata' AS period_end
  ),
  -- The MPPS webhook log is the only record of when a scan started or finished:
  -- ImagingStudy keeps a single status column with no per-transition timestamp.
  -- Joined on text, not ::uuid, so a malformed payload cannot abort the query.
  mpps AS (
    SELECT
      LOWER(w.raw_data ->> 'service_request_id')                                        AS sr_external_id,
      BOOL_OR(w.raw_data ->> 'study_status' = 'IN_PROGRESS')                            AS scan_started,
      BOOL_OR(w.raw_data ->> 'study_status' = 'COMPLETED')                              AS scan_completed
    FROM care_radiology_radiologywebhooklogs w
    WHERE w.deleted = FALSE
      AND w.type = 'MPPS'
      AND w.raw_data ? 'service_request_id'
    GROUP BY 1
  ),
  studies AS (
    SELECT
      COALESCE(sr.facility_id, e.facility_id)                                           AS facility_id,
      COALESCE(rc.title, 'Uncategorised')                                               AS procedure_category,
      ist.id,
      ist.status,
      ist.accession_number IS NOT NULL                                                  AS accessioned,
      COALESCE(m.scan_started, FALSE)
        OR ist.status IN ('IN_PROGRESS', 'COMPLETED')                                   AS scan_started,
      COALESCE(m.scan_completed, FALSE)
        OR ist.status = 'COMPLETED'                                                     AS scan_completed,
      EXISTS (
        SELECT 1 FROM care_radiology_dicomstudy ds
        WHERE ds.imaging_study_id = ist.id AND ds.deleted = FALSE AND ds.is_archived = FALSE
      )                                                                                 AS images_stored,
      EXISTS (
        SELECT 1 FROM emr_diagnosticreport dr
        WHERE dr.service_request_id = ist.service_request_id AND dr.deleted = FALSE
      )                                                                                 AS report_drafted,
      EXISTS (
        SELECT 1 FROM emr_diagnosticreport dr
        WHERE dr.service_request_id = ist.service_request_id
          AND dr.deleted = FALSE AND dr.status = 'final'
      )                                                                                 AS report_final
    FROM care_radiology_imagingstudy ist
    CROSS JOIN bounds b
    LEFT JOIN emr_servicerequest sr      ON sr.id = ist.service_request_id AND sr.deleted = FALSE
    JOIN emr_encounter e                 ON e.id = ist.encounter_id
    LEFT JOIN emr_activitydefinition ad  ON ad.id = sr.activity_definition_id AND ad.deleted = FALSE
    LEFT JOIN emr_resourcecategory rc    ON rc.id = ad.category_id AND rc.deleted = FALSE
    LEFT JOIN mpps m                     ON m.sr_external_id = sr.external_id::TEXT
    WHERE ist.deleted = FALSE
      AND ist.created_date >= b.period_start
      AND ist.created_date <  b.period_end
  )
SELECT
  f.external_id                                                     AS "FACILITY_ID",
  f.name                                                            AS "FACILITY_NAME",
  s.procedure_category                                              AS "PROCEDURE_CATEGORY",
  COUNT(*)                                                          AS "ORDERED",
  COUNT(*) FILTER (WHERE s.accessioned)                             AS "ACCESSIONED",
  COUNT(*) FILTER (WHERE s.scan_started)                            AS "SCAN_STARTED",
  COUNT(*) FILTER (WHERE s.scan_completed)                          AS "SCAN_COMPLETED",
  COUNT(*) FILTER (WHERE s.images_stored)                           AS "IMAGES_STORED",
  COUNT(*) FILTER (WHERE s.report_drafted)                          AS "REPORT_DRAFTED",
  COUNT(*) FILTER (WHERE s.report_final)                            AS "REPORT_FINAL",
  COUNT(*) FILTER (WHERE s.status = 'CANCELLED')                    AS "CANCELLED",
  ROUND(100.0 * COUNT(*) FILTER (WHERE s.images_stored) / NULLIF(COUNT(*), 0), 1)
                                                                    AS "ORDER_TO_IMAGE_PCT",
  ROUND(100.0 * COUNT(*) FILTER (WHERE s.report_final)
        / NULLIF(COUNT(*) FILTER (WHERE s.images_stored), 0), 1)    AS "IMAGE_TO_REPORT_PCT",
  ROUND(100.0 * COUNT(*) FILTER (WHERE s.report_final) / NULLIF(COUNT(*), 0), 1)
                                                                    AS "END_TO_END_PCT",
  -- Scanned but nothing in the PACS: the usual sign of a DICOM Enabler or
  -- accession-number mismatch rather than a clinical delay.
  COUNT(*) FILTER (WHERE s.scan_completed AND NOT s.images_stored)  AS "SCANNED_NO_IMAGES",
  COUNT(*) FILTER (WHERE s.images_stored AND NOT s.report_drafted)  AS "IMAGED_NOT_REPORTED"
FROM studies s
JOIN facility_facility f ON f.id = s.facility_id AND f.deleted = FALSE
WHERE TRUE
  [[AND f.external_id::TEXT = {{facility_id}}]]
GROUP BY f.external_id, f.name, s.procedure_category
ORDER BY "ORDERED" DESC, "FACILITY_NAME";
