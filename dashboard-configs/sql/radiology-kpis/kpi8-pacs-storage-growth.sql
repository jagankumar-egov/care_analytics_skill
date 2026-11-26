-- KPI 8: PACS Storage Growth & Archival
--
-- How much imaging is accumulating, per facility per month, and how much of it
-- has been archived out of the PACS.
--
-- NOTE: number_of_series / number_of_instances are written when CARE syncs a
-- study's metadata from DCM4CHEE; a study never synced leaves them NULL, which
-- is why UNSYNCED_STUDIES is on this card. Byte-level size is not kept in CARE
-- at all -- instance counts are the proxy.
--
-- Parameters: {{start_date}}, {{end_date}} (IST dates, inclusive), {{facility_id}} (optional)
WITH
  bounds AS (
    SELECT
      ({{start_date}}::DATE)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata'   AS period_start,
      ({{end_date}}::DATE + 1)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata' AS period_end
  ),
  studies AS (
    SELECT
      COALESCE(sr.facility_id, e.facility_id)                                    AS facility_id,
      DATE_TRUNC('month', ds.created_date AT TIME ZONE 'Asia/Kolkata')::DATE     AS month,
      COALESCE(rc.title, 'Uncategorised')                                        AS procedure_category,
      ds.is_archived,
      ds.number_of_series,
      ds.number_of_instances,
      ds.archived_datetime,
      ds.id
    FROM care_radiology_dicomstudy ds
    CROSS JOIN bounds b
    JOIN care_radiology_imagingstudy ist ON ist.id = ds.imaging_study_id AND ist.deleted = FALSE
    LEFT JOIN emr_servicerequest sr      ON sr.id = ist.service_request_id AND sr.deleted = FALSE
    JOIN emr_encounter e                 ON e.id = ist.encounter_id
    LEFT JOIN emr_activitydefinition ad  ON ad.id = sr.activity_definition_id AND ad.deleted = FALSE
    LEFT JOIN emr_resourcecategory rc    ON rc.id = ad.category_id AND rc.deleted = FALSE
    WHERE ds.deleted = FALSE
      AND ds.created_date >= b.period_start
      AND ds.created_date <  b.period_end
  )
SELECT
  f.external_id                                                         AS "FACILITY_ID",
  f.name                                                                AS "FACILITY_NAME",
  s.month                                                               AS "MONTH",
  s.procedure_category                                                  AS "PROCEDURE_CATEGORY",
  COUNT(*)                                                              AS "DICOM_STUDIES",
  COUNT(*) FILTER (WHERE NOT s.is_archived)                             AS "LIVE_STUDIES",
  COUNT(*) FILTER (WHERE s.is_archived)                                 AS "ARCHIVED_STUDIES",
  COUNT(*) FILTER (WHERE s.number_of_instances IS NULL)                 AS "UNSYNCED_STUDIES",
  COALESCE(SUM(s.number_of_series), 0)                                  AS "SERIES",
  COALESCE(SUM(s.number_of_instances), 0)                               AS "INSTANCES",
  COALESCE(SUM(s.number_of_instances) FILTER (WHERE NOT s.is_archived), 0)
                                                                        AS "LIVE_INSTANCES",
  ROUND(AVG(s.number_of_instances)::NUMERIC, 1)                         AS "AVG_INSTANCES_PER_STUDY",
  MAX(s.number_of_instances)                                            AS "MAX_INSTANCES_IN_A_STUDY",
  -- Running total within a facility+category series, so the card doubles as a
  -- capacity-planning line chart. Partitioned by category because that is part
  -- of the grain -- summing across categories here would depend on row order.
  SUM(COALESCE(SUM(s.number_of_instances) FILTER (WHERE NOT s.is_archived), 0))
    OVER (PARTITION BY f.external_id, s.procedure_category ORDER BY s.month)
                                                                        AS "CUMULATIVE_LIVE_INSTANCES"
FROM studies s
JOIN facility_facility f ON f.id = s.facility_id AND f.deleted = FALSE
WHERE TRUE
  [[AND f.external_id::TEXT = {{facility_id}}]]
GROUP BY f.external_id, f.name, s.month, s.procedure_category
ORDER BY "MONTH" DESC, "INSTANCES" DESC;
