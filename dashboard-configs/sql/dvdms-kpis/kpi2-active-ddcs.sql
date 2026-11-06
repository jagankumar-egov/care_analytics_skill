-- KPI 2: Active DDCs
WITH
  -- The reporting day, in IST. day_end is the exclusive upper bound, so every window
  -- below ends at midnight IST after the selected date and the card is reproducible
  -- for any past date instead of drifting with NOW().
  bounds AS (
    SELECT
      ({{dispense_date}}::DATE)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata' AS day_start,
      ({{dispense_date}}::DATE + 1)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata' AS day_end
  ),
  dispenses AS (
    SELECT
      st.id AS store_pk,
      st.eaushadhi_store_id,
      st.eaushadhi_store_name,
      -- eAushadhi's store type (sststrTypeName) is only read from the lookup API to
      -- group the store picker; the store mapping never persists it, so STORE_TYPE
      -- stays NULL until that mapping writes the type into meta.
      st.meta ->> 'store_type' AS store_type,
      md.location_id,
      l.name AS location_name,
      md.created_by_id,
      (COALESCE(md.when_handed_over, md.when_prepared, md.created_date) AT TIME ZONE 'Asia/Kolkata')::DATE AS dispense_date
    FROM
      emr_medicationdispense md
      JOIN emr_facilitylocation l ON l.id = md.location_id
      AND l.deleted = FALSE
      JOIN facility_facility f ON f.id = l.facility_id
      AND f.deleted = FALSE
      AND f.is_active = TRUE
      AND f.is_public = TRUE
      JOIN care_dvdms_dvdmsinstitute inst ON inst.facility_id = f.id
      AND inst.deleted = FALSE
      -- Dispenses happen at DDC counters, not at the store's own location, so
      -- each dispense is attributed to the institute's store (default first, as in KPI 1)
      JOIN LATERAL (
        SELECT
          s2.id,
          s2.eaushadhi_store_id,
          s2.eaushadhi_store_name,
          s2.meta
        FROM
          care_dvdms_dvdmsstore s2
        WHERE
          s2.institute_id = inst.id
          AND s2.deleted = FALSE
        ORDER BY
          s2.is_default DESC,
          s2.id
        LIMIT
          1
      ) st ON TRUE
    WHERE
      md.deleted = FALSE
      AND md.status NOT IN ('cancelled', 'entered_in_error', 'stopped', 'declined')
      [[AND st.eaushadhi_store_id = {{store_id}}]]
      -- Mandatory: no [[ ]], so Metabase requires the parameter.
      AND (COALESCE(md.when_handed_over, md.when_prepared, md.created_date) AT TIME ZONE 'Asia/Kolkata')::DATE = {{dispense_date}}
  ),
  active_users AS (
    -- Same rule as KPI 1: any EMR write in the last 7 days
    SELECT created_by_id FROM emr_encounter, bounds b
    WHERE deleted = FALSE AND created_date >= b.day_end - INTERVAL '7 days' AND created_date < b.day_end
    UNION
    SELECT created_by_id FROM emr_medicationdispense, bounds b
    WHERE deleted = FALSE AND created_date >= b.day_end - INTERVAL '7 days' AND created_date < b.day_end
    UNION
    SELECT created_by_id FROM emr_deliveryorder, bounds b
    WHERE deleted = FALSE AND created_date >= b.day_end - INTERVAL '7 days' AND created_date < b.day_end
    UNION
    SELECT created_by_id FROM emr_requestorder, bounds b
    WHERE deleted = FALSE AND created_date >= b.day_end - INTERVAL '7 days' AND created_date < b.day_end
  )
SELECT
  d.eaushadhi_store_id AS "STORE_ID",
  d.eaushadhi_store_name AS "STORE_NAME",
  d.store_type AS "STORE_TYPE",
  d.location_name AS "LOCATION_NAME",
  u.username AS "USER_ID",
  -- Falls back to the username for accounts with no first/last name
  COALESCE(NULLIF(TRIM(CONCAT_WS(' ', u.first_name, u.last_name)), ''), u.username) AS "USER_NAME",
  CASE
    WHEN au.created_by_id IS NULL THEN 'Inactive'
    ELSE 'Active'
  END AS "USER_ACTIVE_STATUS",
  u.last_login AS "LATEST_LOGIN_DATE",
  d.dispense_date AS "DISPENSE_DATE",
  COUNT(*) AS "NUMBER_OF_DISPENSES"
FROM
  dispenses d
  JOIN users_user u ON u.id = d.created_by_id
  LEFT JOIN active_users au ON au.created_by_id = u.id
GROUP BY
  d.store_pk,
  d.eaushadhi_store_id,
  d.eaushadhi_store_name,
  d.store_type,
  d.location_id,
  d.location_name,
  u.id,
  au.created_by_id,
  d.dispense_date
ORDER BY
  "STORE_NAME",
  "LOCATION_NAME",
  "DISPENSE_DATE" DESC,
  "USER_NAME";
