-- KPI 9: Reporting Productivity & Template Adoption
--
-- Who is finalising radiology reports, how fast, and how much of the reporting
-- is coming from the plugin's observation templates rather than free text.
--
-- Attribution: emr_diagnosticreport.updated_by_id is the user who last wrote the
-- report, which for a finalised report is the radiologist who signed it off.
-- There is no separate "finalised_by" column, so a report edited after
-- finalisation is attributed to whoever made that last edit.
--
-- Parameters: {{start_date}}, {{end_date}} (IST dates, inclusive), {{facility_id}} (optional)
WITH
  bounds AS (
    SELECT
      ({{start_date}}::DATE)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata'   AS period_start,
      ({{end_date}}::DATE + 1)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata' AS period_end
  ),
  -- Observation definitions that a facility has wrapped in a radiology template.
  template_defs AS (
    SELECT DISTINCT t.facility_id, t.observation_definition_id
    FROM care_radiology_observationtemplate t
    WHERE t.deleted = FALSE
  ),
  radiology_reports AS (
    SELECT
      dr.id,
      -- DiagnosticReport.facility is nullable; fall back to the order's facility so a
      -- report with no facility set is still counted somewhere.
      COALESCE(dr.facility_id, sr.facility_id, e.facility_id) AS facility_id,
      dr.service_request_id,
      dr.status,
      dr.created_date,
      dr.modified_date,
      dr.updated_by_id,
      dr.conclusion,
      ist.created_date                                   AS ordered_at,
      COALESCE(rc.title, 'Uncategorised')                AS procedure_category
    FROM emr_diagnosticreport dr
    CROSS JOIN bounds b
    -- An imaging study on the service request is what makes this a radiology report
    -- rather than a lab one.
    JOIN care_radiology_imagingstudy ist  ON ist.service_request_id = dr.service_request_id
                                         AND ist.deleted = FALSE
    JOIN emr_encounter e                  ON e.id = ist.encounter_id
    LEFT JOIN emr_servicerequest sr       ON sr.id = dr.service_request_id AND sr.deleted = FALSE
    LEFT JOIN emr_activitydefinition ad   ON ad.id = sr.activity_definition_id AND ad.deleted = FALSE
    LEFT JOIN emr_resourcecategory rc     ON rc.id = ad.category_id AND rc.deleted = FALSE
    WHERE dr.deleted = FALSE
      AND dr.status = 'final'
      AND dr.modified_date >= b.period_start
      AND dr.modified_date <  b.period_end
  ),
  observations AS (
    SELECT
      o.diagnostic_report_id,
      COUNT(*)                                                                AS observation_count,
      COUNT(*) FILTER (WHERE td.observation_definition_id IS NOT NULL)        AS templated_observations
    FROM emr_observation o
    JOIN radiology_reports rr   ON rr.id = o.diagnostic_report_id
    LEFT JOIN template_defs td  ON td.observation_definition_id = o.observation_definition_id
                               AND td.facility_id = rr.facility_id
    WHERE o.deleted = FALSE
      AND o.status <> 'entered_in_error'
    GROUP BY o.diagnostic_report_id
  )
SELECT
  f.external_id                                                           AS "FACILITY_ID",
  f.name                                                                  AS "FACILITY_NAME",
  u.external_id                                                           AS "REPORTER_ID",
  COALESCE(NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''), u.username)
                                                                          AS "REPORTER",
  u.user_type                                                             AS "REPORTER_TYPE",
  r.procedure_category                                                    AS "PROCEDURE_CATEGORY",
  COUNT(*)                                                                AS "REPORTS_FINALISED",
  COUNT(DISTINCT (r.modified_date AT TIME ZONE 'Asia/Kolkata')::DATE)     AS "ACTIVE_DAYS",
  ROUND(
    COUNT(*)::NUMERIC / NULLIF(COUNT(DISTINCT (r.modified_date AT TIME ZONE 'Asia/Kolkata')::DATE), 0),
    1
  )                                                                       AS "REPORTS_PER_ACTIVE_DAY",
  ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (
    ORDER BY EXTRACT(EPOCH FROM (r.modified_date - r.ordered_at)) / 3600.0
  )::NUMERIC, 2)                                                          AS "ORDER_TO_REPORT_P50_HRS",
  ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (
    ORDER BY EXTRACT(EPOCH FROM (r.modified_date - r.ordered_at)) / 3600.0
  )::NUMERIC, 2)                                                          AS "ORDER_TO_REPORT_P90_HRS",
  COALESCE(SUM(ob.observation_count), 0)                                  AS "OBSERVATIONS_RECORDED",
  COALESCE(SUM(ob.templated_observations), 0)                             AS "TEMPLATED_OBSERVATIONS",
  ROUND(
    100.0 * COALESCE(SUM(ob.templated_observations), 0)
    / NULLIF(SUM(ob.observation_count), 0), 1
  )                                                                       AS "TEMPLATE_USE_PCT",
  COUNT(*) FILTER (WHERE COALESCE(TRIM(r.conclusion), '') <> '')          AS "REPORTS_WITH_CONCLUSION",
  MAX(r.modified_date)                                                    AS "LAST_REPORT_AT"
FROM radiology_reports r
JOIN facility_facility f  ON f.id = r.facility_id AND f.deleted = FALSE
LEFT JOIN users_user u    ON u.id = r.updated_by_id
LEFT JOIN observations ob ON ob.diagnostic_report_id = r.id
WHERE TRUE
  [[AND f.external_id::TEXT = {{facility_id}}]]
GROUP BY f.external_id, f.name, u.external_id, u.username, u.first_name, u.last_name, u.user_type, r.procedure_category
ORDER BY "REPORTS_FINALISED" DESC, "FACILITY_NAME";
