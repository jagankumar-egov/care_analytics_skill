-- KPI 6: Open Radiology Backlog & Aging
--
-- The daily ops queue: every non-cancelled, non-reported study with how long it
-- has been sitting and which stage it is stuck at. Unlike the other cards this
-- one ignores {{start_date}}/{{end_date}} on purpose -- a backlog is about what
-- is open *now*, and the oldest items are the ones that matter most.
--
-- Parameters: {{facility_id}} (optional), {{min_age_hours}} (optional, default 0)
WITH
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
    SELECT ds.imaging_study_id, MIN(ds.created_date) AS first_image_at, COUNT(*) AS dicom_studies
    FROM care_radiology_dicomstudy ds
    WHERE ds.deleted = FALSE AND ds.is_archived = FALSE
    GROUP BY ds.imaging_study_id
  ),
  open_studies AS (
    SELECT
      COALESCE(sr.facility_id, e.facility_id)                     AS facility_id,
      ist.external_id                                             AS imaging_study_id,
      ist.accession_number,
      ist.status                                                  AS study_status,
      ist.created_date                                            AS ordered_at,
      sr.status                                                   AS service_request_status,
      sr.priority,
      p.name                                                      AS patient_name,
      p.external_id                                               AS patient_external_id,
      e.encounter_class,
      COALESCE(ad.title, sr.title)                                AS procedure_title,
      COALESCE(rc.title, 'Uncategorised')                         AS procedure_category,
      m.scan_started_at,
      m.scan_ended_at,
      im.first_image_at,
      COALESCE(im.dicom_studies, 0)                               AS dicom_studies,
      COALESCE(NULLIF(TRIM(CONCAT_WS(' ', qu.first_name, qu.last_name)), ''), qu.username)
                                                                  AS ordered_by,
      EXTRACT(EPOCH FROM (NOW() - ist.created_date)) / 3600.0     AS age_hours
    FROM care_radiology_imagingstudy ist
    LEFT JOIN emr_servicerequest sr      ON sr.id = ist.service_request_id AND sr.deleted = FALSE
    JOIN emr_encounter e                 ON e.id = ist.encounter_id
    JOIN emr_patient p                   ON p.id = ist.patient_id
    LEFT JOIN emr_activitydefinition ad  ON ad.id = sr.activity_definition_id AND ad.deleted = FALSE
    LEFT JOIN emr_resourcecategory rc    ON rc.id = ad.category_id AND rc.deleted = FALSE
    LEFT JOIN users_user qu              ON qu.id = sr.requester_id
    LEFT JOIN mpps m                     ON m.sr_external_id = sr.external_id::TEXT
    LEFT JOIN images im                  ON im.imaging_study_id = ist.id
    WHERE ist.deleted = FALSE
      AND ist.status <> 'CANCELLED'
      -- Not yet closed out clinically.
      AND NOT EXISTS (
        SELECT 1 FROM emr_diagnosticreport dr
        WHERE dr.service_request_id = ist.service_request_id
          AND dr.deleted = FALSE AND dr.status = 'final'
      )
  )
SELECT
  f.external_id                                   AS "FACILITY_ID",
  f.name                                          AS "FACILITY_NAME",
  o.imaging_study_id                              AS "IMAGING_STUDY_ID",
  o.accession_number                              AS "ACCESSION_NUMBER",
  o.patient_external_id                           AS "PATIENT_ID",
  o.patient_name                                  AS "PATIENT_NAME",
  o.procedure_category                            AS "PROCEDURE_CATEGORY",
  o.procedure_title                               AS "PROCEDURE",
  o.priority                                      AS "PRIORITY",
  o.encounter_class                               AS "ENCOUNTER_CLASS",
  o.study_status                                  AS "STUDY_STATUS",
  o.service_request_status                        AS "ORDER_STATUS",
  o.ordered_by                                    AS "ORDERED_BY",
  o.ordered_at                                    AS "ORDERED_AT",
  ROUND(o.age_hours::NUMERIC, 1)                  AS "AGE_HOURS",
  CASE
    WHEN o.age_hours < 4    THEN '0-4h'
    WHEN o.age_hours < 24   THEN '4-24h'
    WHEN o.age_hours < 72   THEN '1-3d'
    WHEN o.age_hours < 168  THEN '3-7d'
    ELSE '7d+'
  END                                             AS "AGE_BUCKET",
  CASE
    WHEN o.accession_number IS NULL   THEN 'Awaiting accession number'
    WHEN o.first_image_at IS NOT NULL THEN 'Awaiting report'
    WHEN o.scan_ended_at IS NOT NULL  THEN 'Awaiting images'
    WHEN o.scan_started_at IS NOT NULL THEN 'Scan in progress'
    ELSE 'Awaiting scan'
  END                                             AS "BLOCKED_AT",
  o.dicom_studies                                 AS "DICOM_STUDIES"
FROM open_studies o
JOIN facility_facility f ON f.id = o.facility_id AND f.deleted = FALSE
WHERE TRUE
  [[AND o.age_hours >= {{min_age_hours}}::NUMERIC]]
  [[AND f.external_id::TEXT = {{facility_id}}]]
ORDER BY
  CASE WHEN o.priority IN ('stat', 'asap') THEN 0 WHEN o.priority = 'urgent' THEN 1 ELSE 2 END,
  o.age_hours DESC;
