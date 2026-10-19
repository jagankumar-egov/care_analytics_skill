-- Issues to Patient (per location)
-- One row per issue. An "issue" is a DispenseOrder: a dispensing event for one
-- patient at one location, grouping N MedicationDispense line items.
-- Filters: Issue Date (single day, Asia/Kolkata), Facility ID, Location ID.
-- Location ID is optional - leave it blank for all DDCs in the facility.
WITH
  w AS (
    SELECT
      CASE LOWER(TRIM({{issue_date}}))
        WHEN 'today' THEN (NOW() AT TIME ZONE 'Asia/Kolkata')::date
        WHEN 'yesterday' THEN (NOW() AT TIME ZONE 'Asia/Kolkata')::date - 1
        ELSE {{issue_date}}::date
      END AS end_date
  ),
  dispensed AS (
    SELECT
      -- DispenseOrder is nullable on a dispense. Orderless dispenses get their
      -- own negative key so each stands alone instead of collapsing together.
      COALESCE(dord.id, -md.id)                 AS issue_key,
      COALESCE(dord.external_id, md.external_id) AS issue_id,
      loc.external_id                           AS location_uuid,
      loc.name                                  AS location_name,
      pat.external_id                           AS patient_uuid,
      (
        COALESCE(md.when_handed_over, md.when_prepared, md.created_date)
        AT TIME ZONE 'Asia/Kolkata'
      )::date                                   AS issued_on,
      md.quantity                               AS quantity
    FROM
      w
      CROSS JOIN emr_medicationdispense md
      JOIN emr_facilitylocation loc ON loc.id = md.location_id
      AND loc.deleted = FALSE
      JOIN facility_facility f ON f.id = loc.facility_id
      AND f.deleted = FALSE
      JOIN emr_patient pat ON pat.id = md.patient_id
      AND pat.deleted = FALSE
      LEFT JOIN emr_dispenseorder dord ON dord.id = md.order_id
      AND dord.deleted = FALSE
    WHERE
      md.deleted = FALSE
      AND md.status = 'completed'
      AND f.external_id = {{facility_id}}::UUID
      AND (
        COALESCE(md.when_handed_over, md.when_prepared, md.created_date)
        AT TIME ZONE 'Asia/Kolkata'
      )::date = w.end_date
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
      [[AND loc.external_id = {{location_id}}::UUID]]
  )
SELECT
  issued_on       AS issue_date,
  location_uuid   AS location_id,
  location_name   AS ddc,
  issue_id        AS issue_id,
  patient_uuid    AS patient_id,
  COUNT(*)        AS no_of_items,
  SUM(quantity)   AS total_quantity
FROM
  dispensed
GROUP BY
  issue_key,
  issued_on,
  location_uuid,
  location_name,
  issue_id,
  patient_uuid
ORDER BY
  location_name,
  issue_id;
