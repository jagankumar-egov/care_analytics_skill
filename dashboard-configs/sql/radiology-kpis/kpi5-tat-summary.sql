-- KPI 5: Turnaround Time Summary (median / p90 per facility and procedure)
--
-- The headline SLA card. Same clocks as KPI 4 -- read its header for what each
-- timestamp actually measures before quoting these numbers to anyone.
-- Percentiles are computed only over studies that reached the stage, so the
-- *_N columns are there to tell a fast median from a thin one.
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
      LOWER(w.raw_data ->> 'service_request_id')                                       AS sr_external_id,
      MIN(w.created_date) FILTER (WHERE w.raw_data ->> 'study_status' = 'IN_PROGRESS') AS scan_started_at,
      MIN(w.created_date) FILTER (WHERE w.raw_data ->> 'study_status' = 'COMPLETED')   AS scan_ended_at
    FROM care_radiology_radiologywebhooklogs w
    WHERE w.deleted = FALSE
      AND w.type = 'MPPS'
      AND w.raw_data ? 'service_request_id'
    GROUP BY 1
  ),
  images AS (
    SELECT ds.imaging_study_id, MIN(ds.created_date) AS first_image_at
    FROM care_radiology_dicomstudy ds
    WHERE ds.deleted = FALSE
    GROUP BY ds.imaging_study_id
  ),
  reports AS (
    SELECT DISTINCT ON (dr.service_request_id)
      dr.service_request_id,
      dr.modified_date AS report_final_at
    FROM emr_diagnosticreport dr
    WHERE dr.deleted = FALSE AND dr.status = 'final'
    ORDER BY dr.service_request_id, dr.modified_date
  ),
  legs AS (
    SELECT
      COALESCE(sr.facility_id, e.facility_id)                                     AS facility_id,
      COALESCE(rc.title, 'Uncategorised')                                         AS procedure_category,
      sr.priority                                                                 AS priority,
      ist.status                                                                  AS study_status,
      EXTRACT(EPOCH FROM (m.scan_started_at - ist.created_date)) / 3600.0         AS order_to_scan_hrs,
      EXTRACT(EPOCH FROM (im.first_image_at
                          - COALESCE(m.scan_ended_at, m.scan_started_at, ist.created_date))) / 3600.0
                                                                                  AS scan_to_images_hrs,
      EXTRACT(EPOCH FROM (r.report_final_at - im.first_image_at)) / 3600.0        AS images_to_report_hrs,
      EXTRACT(EPOCH FROM (r.report_final_at - ist.created_date)) / 3600.0         AS total_tat_hrs
    FROM care_radiology_imagingstudy ist
    CROSS JOIN bounds b
    LEFT JOIN emr_servicerequest sr      ON sr.id = ist.service_request_id AND sr.deleted = FALSE
    JOIN emr_encounter e                 ON e.id = ist.encounter_id
    LEFT JOIN emr_activitydefinition ad  ON ad.id = sr.activity_definition_id AND ad.deleted = FALSE
    LEFT JOIN emr_resourcecategory rc    ON rc.id = ad.category_id AND rc.deleted = FALSE
    LEFT JOIN mpps m                     ON m.sr_external_id = sr.external_id::TEXT
    LEFT JOIN images im                  ON im.imaging_study_id = ist.id
    LEFT JOIN reports r                  ON r.service_request_id = ist.service_request_id
    WHERE ist.deleted = FALSE
      AND ist.status <> 'CANCELLED'
      AND ist.created_date >= b.period_start
      AND ist.created_date <  b.period_end
  )
SELECT
  f.external_id                                                                 AS "FACILITY_ID",
  f.name                                                                        AS "FACILITY_NAME",
  l.procedure_category                                                          AS "PROCEDURE_CATEGORY",
  COUNT(*)                                                                      AS "STUDIES",
  COUNT(*) FILTER (WHERE l.priority IN ('urgent', 'asap', 'stat'))              AS "URGENT_STUDIES",

  COUNT(l.order_to_scan_hrs)                                                    AS "ORDER_TO_SCAN_N",
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY l.order_to_scan_hrs)::NUMERIC, 2)
                                                                                AS "ORDER_TO_SCAN_P50_HRS",
  ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY l.order_to_scan_hrs)::NUMERIC, 2)
                                                                                AS "ORDER_TO_SCAN_P90_HRS",

  COUNT(l.scan_to_images_hrs)                                                   AS "SCAN_TO_IMAGES_N",
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY l.scan_to_images_hrs)::NUMERIC, 2)
                                                                                AS "SCAN_TO_IMAGES_P50_HRS",
  ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY l.scan_to_images_hrs)::NUMERIC, 2)
                                                                                AS "SCAN_TO_IMAGES_P90_HRS",

  COUNT(l.images_to_report_hrs)                                                 AS "IMAGES_TO_REPORT_N",
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY l.images_to_report_hrs)::NUMERIC, 2)
                                                                                AS "IMAGES_TO_REPORT_P50_HRS",
  ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY l.images_to_report_hrs)::NUMERIC, 2)
                                                                                AS "IMAGES_TO_REPORT_P90_HRS",

  COUNT(l.total_tat_hrs)                                                        AS "TOTAL_TAT_N",
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY l.total_tat_hrs)::NUMERIC, 2)
                                                                                AS "TOTAL_TAT_P50_HRS",
  ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY l.total_tat_hrs)::NUMERIC, 2)
                                                                                AS "TOTAL_TAT_P90_HRS",
  -- Share of studies reported within a day of the order being raised.
  ROUND(100.0 * COUNT(*) FILTER (WHERE l.total_tat_hrs <= 24) / NULLIF(COUNT(*), 0), 1)
                                                                                AS "REPORTED_WITHIN_24H_PCT"
FROM legs l
JOIN facility_facility f ON f.id = l.facility_id AND f.deleted = FALSE
WHERE TRUE
  [[AND f.external_id::TEXT = {{facility_id}}]]
GROUP BY f.external_id, f.name, l.procedure_category
ORDER BY "STUDIES" DESC, "FACILITY_NAME";
