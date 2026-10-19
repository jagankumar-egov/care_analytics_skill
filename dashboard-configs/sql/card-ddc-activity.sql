-- DDC Activity (7 days)
-- One row per DDC (a facility location attached to a `pharmacy` healthcare
-- service). "Dispenses (7d)" counts completed patient dispenses in the 7-day
-- window ending on the dashboard's Date filter (inclusive, Asia/Kolkata);
-- 0 means the DDC saw no dispensing activity in that window.
WITH
  w AS (
    SELECT
      CASE LOWER(TRIM({{issue_date}}))
        WHEN 'today' THEN (NOW() AT TIME ZONE 'Asia/Kolkata')::date
        WHEN 'yesterday' THEN (NOW() AT TIME ZONE 'Asia/Kolkata')::date - 1
        ELSE {{issue_date}}::date
      END AS end_date
  )
SELECT
  loc.external_id                            AS location_id,
  loc.name                                   AS ddc,
  loc.status                                 AS location_status,
  t.last_dispense_date                       AS last_dispense,
  (w.end_date - t.last_dispense_date)        AS days_since_last_dispense,
  COALESCE(t.dispenses_7d, 0)                AS dispenses_7d
FROM
  w
  CROSS JOIN facility_facility f
  JOIN emr_facilitylocation loc ON loc.facility_id = f.id
  AND loc.deleted = FALSE
  LEFT JOIN LATERAL (
    SELECT
      MAX(
        (
          COALESCE(md.when_handed_over, md.when_prepared, md.created_date)
          AT TIME ZONE 'Asia/Kolkata'
        )::date
      ) AS last_dispense_date,
      COUNT(*) FILTER (
        WHERE
          (
            COALESCE(md.when_handed_over, md.when_prepared, md.created_date)
            AT TIME ZONE 'Asia/Kolkata'
          )::date BETWEEN (w.end_date - 6) AND w.end_date
      ) AS dispenses_7d
    FROM
      emr_medicationdispense md
    WHERE
      md.location_id = loc.id
      AND md.deleted = FALSE
      AND md.status = 'completed'
      AND (
        COALESCE(md.when_handed_over, md.when_prepared, md.created_date)
        AT TIME ZONE 'Asia/Kolkata'
      )::date <= w.end_date
  ) t ON TRUE
WHERE
  f.deleted = FALSE
  AND f.external_id = {{facility_id}}::UUID
  AND EXISTS (
    SELECT
      1
    FROM
      emr_healthcareservice hs
    WHERE
      loc.id = ANY (hs.locations)
      AND hs.deleted = FALSE
      AND hs.internal_type = 'pharmacy'
  )
ORDER BY
  COALESCE(t.dispenses_7d, 0) DESC,
  loc.name;
