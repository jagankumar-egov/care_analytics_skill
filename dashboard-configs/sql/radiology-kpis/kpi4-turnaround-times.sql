-- KPI 4: Radiology Turnaround Time (study level)
--
-- One row per imaging study with each leg of the journey in hours. This is the
-- drill-through table behind the TAT summary; export it to chase outliers.
--
-- Clock sources, and what each really measures:
--   ORDERED_AT       care_radiology_imagingstudy.created_date  (order placed in CARE)
--   SCAN_STARTED_AT  first MPPS webhook log with study_status IN_PROGRESS
--   SCAN_ENDED_AT    first MPPS webhook log with study_status COMPLETED
--   IMAGES_AT        earliest care_radiology_dicomstudy.created_date -- when the upload
--                    landed in CARE, NOT the DICOM acquisition time (that lives in the
--                    PACS, which CARE never copies into its own tables)
--   REPORT_FINAL_AT  emr_diagnosticreport.modified_date of the first report that reached
--                    status 'final'. DiagnosticReport carries no finalised_at column, so
--                    a report edited after finalisation reports its last edit instead.
--
-- Parameters: {{start_date}}, {{end_date}} (IST dates, inclusive), {{facility_id}} (optional)
WITH
  bounds AS (
    SELECT
      ({{start_date}}::DATE)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata'   AS period_start,
      ({{end_date}}::DATE + 1)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata' AS period_end
  ),
  mpps AS (
    SELECT
      LOWER(w.raw_data ->> 'service_request_id')                                     AS sr_external_id,
      MIN(w.created_date) FILTER (WHERE w.raw_data ->> 'study_status' = 'IN_PROGRESS') AS scan_started_at,
      MIN(w.created_date) FILTER (WHERE w.raw_data ->> 'study_status' = 'COMPLETED')   AS scan_ended_at,
      COUNT(*)                                                                       AS mpps_events
    FROM care_radiology_radiologywebhooklogs w
    WHERE w.deleted = FALSE
      AND w.type = 'MPPS'
      AND w.raw_data ? 'service_request_id'
    GROUP BY 1
  ),
  images AS (
    SELECT
      ds.imaging_study_id,
      MIN(ds.created_date)                            AS first_image_at,
      MAX(ds.created_date)                            AS last_image_at,
      COUNT(*) FILTER (WHERE ds.is_archived = FALSE)  AS live_studies,
      SUM(ds.number_of_series)                        AS series,
      SUM(ds.number_of_instances)                     AS instances
    FROM care_radiology_dicomstudy ds
    WHERE ds.deleted = FALSE
    GROUP BY ds.imaging_study_id
  ),
  reports AS (
    SELECT DISTINCT ON (dr.service_request_id)
      dr.service_request_id,
      dr.modified_date      AS report_final_at,
      dr.created_date       AS report_started_at,
      dr.updated_by_id      AS reporter_id
    FROM emr_diagnosticreport dr
    WHERE dr.deleted = FALSE
      AND dr.status = 'final'
    ORDER BY dr.service_request_id, dr.modified_date
  )
SELECT
  f.external_id                                                     AS "FACILITY_ID",
  f.name                                                            AS "FACILITY_NAME",
  ist.external_id                                                   AS "IMAGING_STUDY_ID",
  ist.accession_number                                              AS "ACCESSION_NUMBER",
  p.external_id                                                     AS "PATIENT_ID",
  COALESCE(ad.title, sr.title)                                      AS "PROCEDURE",
  COALESCE(rc.title, 'Uncategorised')                               AS "PROCEDURE_CATEGORY",
  sr.priority                                                       AS "PRIORITY",
  e.encounter_class                                                 AS "ENCOUNTER_CLASS",
  ist.status                                                        AS "STUDY_STATUS",
  ist.created_date                                                  AS "ORDERED_AT",
  m.scan_started_at                                                 AS "SCAN_STARTED_AT",
  m.scan_ended_at                                                   AS "SCAN_ENDED_AT",
  im.first_image_at                                                 AS "IMAGES_AT",
  r.report_final_at                                                 AS "REPORT_FINAL_AT",
  ROUND(EXTRACT(EPOCH FROM (m.scan_started_at - ist.created_date)) / 3600.0, 2)
                                                                    AS "ORDER_TO_SCAN_HRS",
  ROUND(EXTRACT(EPOCH FROM (m.scan_ended_at - m.scan_started_at)) / 3600.0, 2)
                                                                    AS "SCAN_DURATION_HRS",
  ROUND(EXTRACT(EPOCH FROM (im.first_image_at - COALESCE(m.scan_ended_at, m.scan_started_at, ist.created_date))) / 3600.0, 2)
                                                                    AS "SCAN_TO_IMAGES_HRS",
  ROUND(EXTRACT(EPOCH FROM (r.report_final_at - im.first_image_at)) / 3600.0, 2)
                                                                    AS "IMAGES_TO_REPORT_HRS",
  ROUND(EXTRACT(EPOCH FROM (r.report_final_at - ist.created_date)) / 3600.0, 2)
                                                                    AS "TOTAL_TAT_HRS",
  COALESCE(im.live_studies, 0)                                      AS "DICOM_STUDIES",
  im.series                                                         AS "SERIES",
  im.instances                                                      AS "INSTANCES",
  COALESCE(NULLIF(TRIM(CONCAT_WS(' ', ru.first_name, ru.last_name)), ''), ru.username)
                                                                    AS "REPORTED_BY",
  COALESCE(NULLIF(TRIM(CONCAT_WS(' ', qu.first_name, qu.last_name)), ''), qu.username)
                                                                    AS "ORDERED_BY",
  COALESCE(m.mpps_events, 0)                                        AS "MPPS_EVENTS",
  -- The stage a study is sitting in, for filtering the table down to a queue.
  CASE
    WHEN ist.status = 'CANCELLED'          THEN 'Cancelled'
    WHEN r.report_final_at IS NOT NULL     THEN 'Reported'
    WHEN im.first_image_at IS NOT NULL     THEN 'Awaiting report'
    WHEN m.scan_ended_at IS NOT NULL       THEN 'Awaiting images'
    WHEN m.scan_started_at IS NOT NULL     THEN 'Scan in progress'
    WHEN ist.accession_number IS NOT NULL  THEN 'Awaiting scan'
    ELSE 'Awaiting accession number'
  END                                                               AS "CURRENT_STAGE"
FROM care_radiology_imagingstudy ist
CROSS JOIN bounds b
LEFT JOIN emr_servicerequest sr      ON sr.id = ist.service_request_id AND sr.deleted = FALSE
JOIN emr_encounter e                 ON e.id = ist.encounter_id
JOIN emr_patient p                   ON p.id = ist.patient_id
JOIN facility_facility f             ON f.id = COALESCE(sr.facility_id, e.facility_id) AND f.deleted = FALSE
LEFT JOIN emr_activitydefinition ad  ON ad.id = sr.activity_definition_id AND ad.deleted = FALSE
LEFT JOIN emr_resourcecategory rc    ON rc.id = ad.category_id AND rc.deleted = FALSE
LEFT JOIN users_user qu              ON qu.id = sr.requester_id
LEFT JOIN mpps m                     ON m.sr_external_id = sr.external_id::TEXT
LEFT JOIN images im                  ON im.imaging_study_id = ist.id
LEFT JOIN reports r                  ON r.service_request_id = ist.service_request_id
LEFT JOIN users_user ru              ON ru.id = r.reporter_id
WHERE ist.deleted = FALSE
  AND ist.created_date >= b.period_start
  AND ist.created_date <  b.period_end
  [[AND f.external_id::TEXT = {{facility_id}}]]
ORDER BY ist.created_date DESC;
