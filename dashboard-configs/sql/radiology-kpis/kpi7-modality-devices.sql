-- KPI 7: Modality & DICOM Enabler Inventory
--
-- Every registered imaging device, its worklist eligibility, and the volume of
-- the room it stands in.
--
-- IMPORTANT: CARE stores no link from an imaging study to the device that
-- acquired it. The worklist matches a service request to a device by room
-- (ActivityDefinition.locations overlapping Device.current_location), so the
-- volume columns below are ROOM volume, shared by every device in that room --
-- not per-machine throughput. True per-machine counts need the Station Name in
-- the PACS, which CARE does not copy into its own tables.
--
-- Parameters: {{start_date}}, {{end_date}} (IST dates, inclusive), {{facility_id}} (optional)
WITH
  bounds AS (
    SELECT
      ({{start_date}}::DATE)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata'   AS period_start,
      ({{end_date}}::DATE + 1)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata' AS period_end
  ),
  -- Studies attributed to a room via the ordered procedure's location list.
  room_volume AS (
    SELECT
      loc.id                                            AS location_id,
      COUNT(DISTINCT ist.id)                            AS studies_in_period,
      COUNT(DISTINCT ist.id) FILTER (
        WHERE EXISTS (
          SELECT 1 FROM care_radiology_dicomstudy ds
          WHERE ds.imaging_study_id = ist.id AND ds.deleted = FALSE AND ds.is_archived = FALSE
        )
      )                                                 AS imaged_in_period
    FROM care_radiology_imagingstudy ist
    CROSS JOIN bounds b
    JOIN emr_servicerequest sr      ON sr.id = ist.service_request_id AND sr.deleted = FALSE
    JOIN emr_activitydefinition ad  ON ad.id = sr.activity_definition_id AND ad.deleted = FALSE
    JOIN emr_facilitylocation loc   ON loc.id = ANY (ad.locations) AND loc.deleted = FALSE
    WHERE ist.deleted = FALSE
      AND ist.created_date >= b.period_start
      AND ist.created_date <  b.period_end
    GROUP BY loc.id
  )
SELECT
  f.external_id                                                       AS "FACILITY_ID",
  f.name                                                              AS "FACILITY_NAME",
  d.external_id                                                       AS "DEVICE_ID",
  d.care_type                                                         AS "DEVICE_KIND",
  COALESCE(d.user_friendly_name, d.registered_name)                   AS "DEVICE_NAME",
  d.manufacturer                                                      AS "MANUFACTURER",
  d.model_number                                                      AS "MODEL",
  d.metadata -> 'machine' ->> 'modality'                              AS "MODALITY",
  d.metadata -> 'machine' ->> 'ae_title'                              AS "AE_TITLE",
  d.metadata ->> 'ip'                                                 AS "IP",
  d.status                                                            AS "DEVICE_STATUS",
  d.availability_status                                               AS "AVAILABILITY",
  COALESCE(d.metadata ->> 'assignment_status', 'unassigned')          AS "ASSIGNMENT_STATUS",
  loc.name                                                            AS "ROOM",
  enabler.registered_name                                             AS "DICOM_ENABLER",
  -- Guarded cast: last_synced_at is free-form JSON, so anything that is not an
  -- ISO timestamp is read as "never synced" rather than aborting the card.
  CASE WHEN d.metadata ->> 'last_synced_at' ~ '^\d{4}-\d{2}-\d{2}'
       THEN (d.metadata ->> 'last_synced_at')::TIMESTAMPTZ END        AS "LAST_SYNCED_AT",
  CASE WHEN d.metadata ->> 'last_synced_at' ~ '^\d{4}-\d{2}-\d{2}'
       THEN ROUND(EXTRACT(EPOCH FROM (NOW() - (d.metadata ->> 'last_synced_at')::TIMESTAMPTZ)) / 3600.0, 1)
  END                                                                 AS "HOURS_SINCE_SYNC",
  -- worklist_devices(): active + available + placed in a room.
  CASE
    WHEN d.care_type <> 'dicom' THEN 'n/a'
    WHEN d.status = 'active' AND d.availability_status = 'available' AND d.current_location_id IS NOT NULL
      THEN 'Yes'
    ELSE 'No'
  END                                                                 AS "ON_WORKLIST",
  COALESCE(rv.studies_in_period, 0)                                   AS "ROOM_STUDIES_IN_PERIOD",
  COALESCE(rv.imaged_in_period, 0)                                    AS "ROOM_STUDIES_IMAGED",
  d.created_date                                                      AS "REGISTERED_AT"
FROM emr_device d
JOIN facility_facility f        ON f.id = d.facility_id AND f.deleted = FALSE
LEFT JOIN emr_facilitylocation loc ON loc.id = d.current_location_id AND loc.deleted = FALSE
-- A DICOM device points at its enabler by the enabler's external_id, held as text in metadata.
LEFT JOIN emr_device enabler    ON enabler.external_id::TEXT = d.metadata ->> 'dicom_enabler'
                                AND enabler.deleted = FALSE
LEFT JOIN room_volume rv        ON rv.location_id = d.current_location_id
WHERE d.deleted = FALSE
  AND d.care_type IN ('dicom', 'dicom-enabler')
  [[AND f.external_id::TEXT = {{facility_id}}]]
ORDER BY "FACILITY_NAME", "DEVICE_KIND", "DEVICE_NAME";
