-- KPI 1: Radiology Readiness & Adoption by Facility
--
-- Go-live card. One row per active facility, answering "is radiology actually
-- switched on here, and is anyone using it?". Everything to the left of
-- IMAGING_ORDERS_TOTAL is configuration; everything to the right is usage.
--
-- Parameters: {{start_date}}, {{end_date}} (IST dates, inclusive), {{facility_id}} (optional)
WITH
  -- Reporting window in IST. period_end is the exclusive upper bound, so the card is
  -- reproducible for any past window instead of drifting with NOW().
  bounds AS (
    SELECT
      ({{start_date}}::DATE)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata'     AS period_start,
      ({{end_date}}::DATE + 1)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata'   AS period_end
  ),
  -- Radiology procedures are ActivityDefinitions with classification 'imaging'; the
  -- same literal the plugin matches ServiceRequest.category against
  -- (CARE_RADIOLOGY_RADIOLOGY_CATEGORY, default "imaging").
  imaging_defs AS (
    SELECT
      ad.facility_id,
      COUNT(*) FILTER (WHERE ad.status = 'active' AND ad.latest)                        AS active_procedures,
      COUNT(DISTINCT ad.category_id) FILTER (WHERE ad.status = 'active' AND ad.latest)  AS procedure_categories,
      -- A procedure with no locations never appears in any modality worklist.
      COUNT(*) FILTER (
        WHERE ad.status = 'active' AND ad.latest AND COALESCE(ARRAY_LENGTH(ad.locations, 1), 0) = 0
      )                                                                                 AS procedures_without_location
    FROM emr_activitydefinition ad
    WHERE ad.deleted = FALSE
      AND ad.classification = 'imaging'
    GROUP BY ad.facility_id
  ),
  devices AS (
    SELECT
      d.facility_id,
      COUNT(*) FILTER (WHERE d.care_type = 'dicom-enabler')                             AS dicom_enablers,
      COUNT(*) FILTER (WHERE d.care_type = 'dicom')                                     AS modality_devices,
      COUNT(*) FILTER (
        WHERE d.care_type = 'dicom' AND d.metadata ->> 'assignment_status' = 'assigned'
      )                                                                                 AS assigned_modalities,
      -- worklist_devices(): active + available + placed in a room. Anything short of
      -- this is invisible to the DICOM Enabler.
      COUNT(*) FILTER (
        WHERE d.care_type = 'dicom'
          AND d.status = 'active'
          AND d.availability_status = 'available'
          AND d.current_location_id IS NOT NULL
      )                                                                                 AS worklist_ready_modalities,
      -- Guarded cast: last_synced_at is free-form JSON, so a non-ISO value reads as
      -- "never synced" instead of aborting the card.
      MAX(
        CASE WHEN d.care_type = 'dicom' AND d.metadata ->> 'last_synced_at' ~ '^\d{4}-\d{2}-\d{2}'
             THEN (d.metadata ->> 'last_synced_at')::TIMESTAMPTZ END
      )                                                                                 AS last_modality_sync_at
    FROM emr_device d
    WHERE d.deleted = FALSE
      AND d.care_type IN ('dicom', 'dicom-enabler')
    GROUP BY d.facility_id
  ),
  templates AS (
    SELECT t.facility_id, COUNT(*) AS report_templates
    FROM care_radiology_observationtemplate t
    WHERE t.deleted = FALSE
    GROUP BY t.facility_id
  ),
  -- The three tag displays process_mpps_webhook() looks up. A facility missing them
  -- still works, but scan progress never lands on the service request.
  mpps_tags AS (
    SELECT tc.facility_id, COUNT(DISTINCT tc.display) AS mpps_tags_configured
    FROM emr_tagconfig tc
    WHERE tc.deleted = FALSE
      AND tc.status = 'active'
      AND tc.display IN ('Scan Started', 'Scan Completed', 'Scan Cancelled')
      AND tc.facility_id IS NOT NULL
    GROUP BY tc.facility_id
  ),
  studies AS (
    SELECT
      COALESCE(sr.facility_id, e.facility_id)                                           AS facility_id,
      COUNT(*)                                                                          AS imaging_orders_total,
      COUNT(*) FILTER (WHERE ist.created_date >= b.period_start AND ist.created_date < b.period_end)
                                                                                        AS imaging_orders_in_period,
      COUNT(DISTINCT ist.patient_id)                                                    AS patients_imaged_total,
      MIN(ist.created_date)                                                             AS first_order_at,
      MAX(ist.created_date)                                                             AS last_order_at
    FROM care_radiology_imagingstudy ist
    CROSS JOIN bounds b
    LEFT JOIN emr_servicerequest sr ON sr.id = ist.service_request_id AND sr.deleted = FALSE
    JOIN emr_encounter e ON e.id = ist.encounter_id
    WHERE ist.deleted = FALSE
    GROUP BY 1
  ),
  images AS (
    SELECT
      COALESCE(sr.facility_id, e.facility_id)                                           AS facility_id,
      COUNT(DISTINCT ds.id) FILTER (WHERE ds.is_archived = FALSE)                       AS dicom_studies_live
    FROM care_radiology_dicomstudy ds
    JOIN care_radiology_imagingstudy ist ON ist.id = ds.imaging_study_id AND ist.deleted = FALSE
    LEFT JOIN emr_servicerequest sr ON sr.id = ist.service_request_id AND sr.deleted = FALSE
    JOIN emr_encounter e ON e.id = ist.encounter_id
    WHERE ds.deleted = FALSE
    GROUP BY 1
  )
SELECT
  f.external_id                                              AS "FACILITY_ID",
  f.name                                                     AS "FACILITY_NAME",
  geo.name                                                   AS "GEO_ORGANIZATION",
  COALESCE(idf.active_procedures, 0)                         AS "IMAGING_PROCEDURES",
  COALESCE(idf.procedures_without_location, 0)               AS "PROCEDURES_WITHOUT_ROOM",
  COALESCE(dv.dicom_enablers, 0)                             AS "DICOM_ENABLERS",
  COALESCE(dv.modality_devices, 0)                           AS "MODALITIES",
  COALESCE(dv.worklist_ready_modalities, 0)                  AS "MODALITIES_ON_WORKLIST",
  COALESCE(dv.assigned_modalities, 0)                        AS "MODALITIES_ASSIGNED",
  dv.last_modality_sync_at                                   AS "LAST_MODALITY_SYNC",
  COALESCE(tpl.report_templates, 0)                          AS "REPORT_TEMPLATES",
  COALESCE(tg.mpps_tags_configured, 0)                       AS "MPPS_TAGS_OF_3",
  COALESCE(s.imaging_orders_total, 0)                        AS "IMAGING_ORDERS_TOTAL",
  COALESCE(s.imaging_orders_in_period, 0)                    AS "IMAGING_ORDERS_IN_PERIOD",
  COALESCE(s.patients_imaged_total, 0)                       AS "PATIENTS_IMAGED",
  COALESCE(im.dicom_studies_live, 0)                         AS "DICOM_STUDIES_LIVE",
  (s.first_order_at AT TIME ZONE 'Asia/Kolkata')::DATE       AS "FIRST_ORDER_DATE",
  (s.last_order_at AT TIME ZONE 'Asia/Kolkata')::DATE        AS "LAST_ORDER_DATE",
  CASE
    WHEN COALESCE(s.imaging_orders_in_period, 0) > 0 AND COALESCE(im.dicom_studies_live, 0) > 0
      THEN 'Live'
    WHEN COALESCE(s.imaging_orders_total, 0) > 0
      THEN 'Piloting'
    WHEN COALESCE(idf.active_procedures, 0) > 0 AND COALESCE(dv.worklist_ready_modalities, 0) > 0
      THEN 'Configured, no orders'
    WHEN COALESCE(idf.active_procedures, 0) > 0 OR COALESCE(dv.modality_devices, 0) > 0
      THEN 'Partially configured'
    ELSE 'Not onboarded'
  END                                                        AS "ROLLOUT_STAGE",
  -- Blockers worth chasing before a facility is called live.
  NULLIF(
    CONCAT_WS(
      '; ',
      CASE WHEN COALESCE(idf.active_procedures, 0) = 0 THEN 'no imaging procedures' END,
      CASE WHEN COALESCE(idf.procedures_without_location, 0) > 0 THEN 'procedures with no room' END,
      CASE WHEN COALESCE(dv.worklist_ready_modalities, 0) = 0 THEN 'no worklist-ready modality' END,
      CASE WHEN COALESCE(dv.dicom_enablers, 0) = 0 THEN 'no DICOM enabler' END,
      CASE WHEN COALESCE(tpl.report_templates, 0) = 0 THEN 'no report template' END,
      CASE WHEN COALESCE(tg.mpps_tags_configured, 0) < 3 THEN 'MPPS tags incomplete' END
    ),
    ''
  )                                                          AS "GAPS"
FROM facility_facility f
LEFT JOIN emr_organization geo ON geo.id = f.geo_organization_id AND geo.deleted = FALSE
LEFT JOIN imaging_defs idf ON idf.facility_id = f.id
LEFT JOIN devices dv       ON dv.facility_id = f.id
LEFT JOIN templates tpl    ON tpl.facility_id = f.id
LEFT JOIN mpps_tags tg     ON tg.facility_id = f.id
LEFT JOIN studies s        ON s.facility_id = f.id
LEFT JOIN images im        ON im.facility_id = f.id
WHERE f.deleted = FALSE
  AND f.is_active = TRUE
  [[AND f.external_id::TEXT = {{facility_id}}]]
  -- Facilities with no radiology footprint at all are noise on a rollout card.
  AND (
    COALESCE(idf.active_procedures, 0) > 0
    OR COALESCE(dv.modality_devices, 0) > 0
    OR COALESCE(dv.dicom_enablers, 0) > 0
    OR COALESCE(s.imaging_orders_total, 0) > 0
  )
ORDER BY "IMAGING_ORDERS_IN_PERIOD" DESC, "FACILITY_NAME";
