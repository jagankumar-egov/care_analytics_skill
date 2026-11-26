-- KPI 10: Integration Health & Data-Quality Exceptions
--
-- One row per exception class per facility, with a count and the oldest example.
-- This is the card to watch in the first weeks after go-live: everything here is
-- a silent failure that no user will report.
--
-- Parameters: {{start_date}}, {{end_date}} (IST dates, inclusive), {{facility_id}} (optional)
WITH
  bounds AS (
    SELECT
      ({{start_date}}::DATE)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata'   AS period_start,
      ({{end_date}}::DATE + 1)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata' AS period_end
  ),
  study_facility AS (
    SELECT
      ist.id,
      ist.external_id,
      ist.accession_number,
      ist.status,
      ist.created_date,
      ist.service_request_id,
      COALESCE(sr.facility_id, e.facility_id) AS facility_id
    FROM care_radiology_imagingstudy ist
    CROSS JOIN bounds b
    LEFT JOIN emr_servicerequest sr ON sr.id = ist.service_request_id AND sr.deleted = FALSE
    JOIN emr_encounter e            ON e.id = ist.encounter_id
    WHERE ist.deleted = FALSE
      AND ist.created_date >= b.period_start
      AND ist.created_date <  b.period_end
  ),
  exceptions AS (
    -- The accession-number Celery task never ran or failed: the study can never be
    -- matched to an incoming DICOM file.
    SELECT 'Missing accession number'                AS exception_type,
           'Celery / assign_accession_number'        AS likely_cause,
           s.facility_id, s.external_id AS ref, s.created_date
    FROM study_facility s
    WHERE s.accession_number IS NULL
      AND s.status <> 'CANCELLED'

    UNION ALL
    -- ImagingStudy.service_request is nullable; a study without one is invisible to
    -- the worklist and to every report join.
    SELECT 'Imaging study with no service request', 'Order deleted or signal race',
           s.facility_id, s.external_id, s.created_date
    FROM study_facility s
    WHERE s.service_request_id IS NULL

    UNION ALL
    -- Two studies sharing an accession number break DICOM linkage both ways.
    SELECT 'Duplicate accession number', 'Sequence collision / manual edit',
           s.facility_id, s.external_id, s.created_date
    FROM study_facility s
    WHERE s.accession_number IS NOT NULL
      AND EXISTS (
        SELECT 1 FROM care_radiology_imagingstudy o
        WHERE o.deleted = FALSE
          AND o.accession_number = s.accession_number
          AND o.id <> s.id
      )

    UNION ALL
    -- Marked COMPLETED by MPPS but nothing ever reached the PACS.
    SELECT 'Completed with no images', 'DICOM Enabler / STOW-RS upload',
           s.facility_id, s.external_id, s.created_date
    FROM study_facility s
    WHERE s.status = 'COMPLETED'
      AND NOT EXISTS (
        SELECT 1 FROM care_radiology_dicomstudy ds
        WHERE ds.imaging_study_id = s.id AND ds.deleted = FALSE AND ds.is_archived = FALSE
      )

    UNION ALL
    -- Images arrived against an order that was later revoked; usually a relink candidate.
    SELECT 'Images on a cancelled order', 'Order cancelled after scan',
           s.facility_id, s.external_id, s.created_date
    FROM study_facility s
    WHERE s.status = 'CANCELLED'
      AND EXISTS (
        SELECT 1 FROM care_radiology_dicomstudy ds
        WHERE ds.imaging_study_id = s.id AND ds.deleted = FALSE AND ds.is_archived = FALSE
      )

    UNION ALL
    -- Study metadata never synced back from DCM4CHEE: no series/instance counts,
    -- so storage reporting under-counts and the viewer may show an empty study.
    SELECT 'DICOM study never synced from PACS', 'DCM4CHEE metadata sync',
           COALESCE(sr.facility_id, e.facility_id), ds.external_id, ds.created_date
    FROM care_radiology_dicomstudy ds
    CROSS JOIN bounds b
    JOIN care_radiology_imagingstudy ist ON ist.id = ds.imaging_study_id AND ist.deleted = FALSE
    LEFT JOIN emr_servicerequest sr      ON sr.id = ist.service_request_id AND sr.deleted = FALSE
    JOIN emr_encounter e                 ON e.id = ist.encounter_id
    WHERE ds.deleted = FALSE
      AND ds.is_archived = FALSE
      AND ds.number_of_instances IS NULL
      AND ds.created_date >= b.period_start
      AND ds.created_date <  b.period_end

    UNION ALL
    -- MPPS webhook accepted and logged, but no imaging study carries that status.
    -- The log row is written before process_mpps_webhook() runs, so a 404 or a
    -- tag-config failure leaves exactly this footprint.
    SELECT 'MPPS event with no matching study', 'Webhook payload / facility mismatch',
           NULL::BIGINT, w.external_id, w.created_date
    FROM care_radiology_radiologywebhooklogs w
    CROSS JOIN bounds b
    WHERE w.deleted = FALSE
      AND w.type = 'MPPS'
      AND w.created_date >= b.period_start
      AND w.created_date <  b.period_end
      AND NOT EXISTS (
        SELECT 1
        FROM care_radiology_imagingstudy ist
        JOIN emr_servicerequest sr ON sr.id = ist.service_request_id
        WHERE ist.deleted = FALSE
          AND sr.external_id::TEXT = LOWER(w.raw_data ->> 'service_request_id')
      )
  )
SELECT
  COALESCE(f.external_id::TEXT, '(unattributed)')  AS "FACILITY_ID",
  COALESCE(f.name, '(unattributed)')               AS "FACILITY_NAME",
  x.exception_type                                 AS "EXCEPTION",
  x.likely_cause                                   AS "LIKELY_CAUSE",
  COUNT(*)                                         AS "COUNT",
  MIN(x.created_date)                              AS "OLDEST",
  MAX(x.created_date)                              AS "NEWEST",
  (ARRAY_AGG(x.ref ORDER BY x.created_date))[1]    AS "OLDEST_RECORD_ID"
FROM exceptions x
LEFT JOIN facility_facility f ON f.id = x.facility_id AND f.deleted = FALSE
WHERE TRUE
  [[AND COALESCE(f.external_id::TEXT, '') = {{facility_id}}]]
GROUP BY f.external_id, f.name, x.exception_type, x.likely_cause
ORDER BY "COUNT" DESC, "FACILITY_NAME";
