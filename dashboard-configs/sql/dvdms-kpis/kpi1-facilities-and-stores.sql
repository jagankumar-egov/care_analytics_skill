-- KPI 1: Facilities and Stores
WITH
  -- The reporting day, in IST. day_end is the exclusive upper bound, so every window
  -- below ends at midnight IST after the selected date and the card is reproducible
  -- for any past date instead of drifting with NOW(). KPI 2 derives its DDC counts
  -- the same way, so both cards agree for the same report_date.
  bounds AS (
    SELECT
      ({{report_date}}::DATE)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata' AS day_start,
      ({{report_date}}::DATE + 1)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata' AS day_end
  ),
  activity AS (
    -- Facility-scoped EMR writes in the 7 days up to the reporting day. 7 days is
    -- the one "active" window on this card: STORE_ACTIVE_STATUS and ACTIVE_DDC_COUNT
    -- use it too, so every status on a row means the same thing.
    SELECT
      e.facility_id
    FROM
      emr_encounter e
      CROSS JOIN bounds b
    WHERE
      e.deleted = FALSE
      AND e.created_date >= b.day_end - INTERVAL '7 days'
      AND e.created_date < b.day_end
    UNION ALL
    SELECT
      l.facility_id
    FROM
      emr_medicationdispense md
      CROSS JOIN bounds b
      JOIN emr_facilitylocation l ON l.id = md.location_id
      AND l.deleted = FALSE
    WHERE
      md.deleted = FALSE
      AND md.created_date >= b.day_end - INTERVAL '7 days'
      AND md.created_date < b.day_end
    UNION ALL
    SELECT
      l.facility_id
    FROM
      emr_deliveryorder d
      CROSS JOIN bounds b
      JOIN emr_facilitylocation l ON l.id = d.destination_id
      AND l.deleted = FALSE
    WHERE
      d.deleted = FALSE
      AND d.created_date >= b.day_end - INTERVAL '7 days'
      AND d.created_date < b.day_end
    UNION ALL
    SELECT
      l.facility_id
    FROM
      emr_requestorder r
      CROSS JOIN bounds b
      JOIN emr_facilitylocation l ON l.id = r.destination_id
      AND l.deleted = FALSE
    WHERE
      r.deleted = FALSE
      AND r.created_date >= b.day_end - INTERVAL '7 days'
      AND r.created_date < b.day_end
  ),
  facility_activity AS (
    SELECT DISTINCT
      a.facility_id
    FROM
      activity a
  ),
  ddc AS (
    -- A DDC is any location that has dispensed; no model flags dispensing locations.
    -- Same derivation as KPI 2 - keep the two in sync.
    SELECT
      l.facility_id,
      md.location_id,
      MAX(COALESCE(md.when_handed_over, md.when_prepared, md.created_date)) AS last_dispense
    FROM
      emr_medicationdispense md
      CROSS JOIN bounds b
      JOIN emr_facilitylocation l ON l.id = md.location_id
      AND l.deleted = FALSE
    WHERE
      md.deleted = FALSE
      -- Cap at the reporting day so a later dispense cannot mark a DDC active
      AND COALESCE(md.when_handed_over, md.when_prepared, md.created_date) < b.day_end
      AND md.status NOT IN ('cancelled', 'entered_in_error', 'stopped', 'declined')
    GROUP BY
      l.facility_id,
      md.location_id
  ),
  ddc_counts AS (
    -- Counts are facility-wide. They are NOT narrowed by {{store_id}}: a DDC is a
    -- location, and locations carry no store mapping.
    SELECT
      d.facility_id,
      COUNT(*) AS total_ddc_count,
      COUNT(*) FILTER (
        WHERE
          d.last_dispense >= b.day_end - INTERVAL '7 days'
      ) AS active_ddc_count
    FROM
      ddc d
      CROSS JOIN bounds b
    GROUP BY
      d.facility_id
  )
SELECT
  f.name AS "FACILITY_NAME",
  inst.eaushadhi_institute_name AS "INSTITUTE_NAME",
  sp.eaushadhi_warehouse_id AS "PARENT_ID",
  hf.hf_id AS "HOSPITAL_UNIQUE_ID",
  CASE
    WHEN fa.facility_id IS NULL THEN 'Inactive'
    ELSE 'Active'
  END AS "FACILITY_ACTIVE_STATUS",
  st.eaushadhi_store_id AS "STORE_ID",
  st.eaushadhi_store_name AS "STORE_NAME",
  -- eAushadhi's store type (sststrTypeName) is only read from the lookup API to group
  -- the store picker; the store mapping never persists it, so these two columns are
  -- NULL today. They light up as soon as the mapping writes the type into meta.
  st.meta ->> 'store_type' AS "STORE_TYPE",
  CASE
    WHEN st.id IS NULL THEN NULL
    WHEN EXISTS (
      -- Indent raised
      SELECT
        1
      FROM
        care_dvdms_dvdmsoutwardrecordorder o
        JOIN care_dvdms_dvdmsrecordorder ro ON ro.id = o.record_order_id
        AND ro.deleted = FALSE
      WHERE
        ro.institute_store_id = st.id
        AND o.deleted = FALSE
        AND o.status = 'submitted'
        AND o.modified_date >= b.day_end - INTERVAL '7 days'
        AND o.modified_date < b.day_end
    )
    OR EXISTS (
      -- Issue received. Inward records are institute-scoped and only some of them
      -- carry an outward record, so match on the institute - one store is reported
      -- per institute here, so the two are the same thing.
      SELECT
        1
      FROM
        care_dvdms_dvdmsinwardrecord i
      WHERE
        i.institute_id = inst.id
        AND i.deleted = FALSE
        AND i.created_date >= b.day_end - INTERVAL '7 days'
        AND i.created_date < b.day_end
    ) THEN 'Active'
    ELSE 'Inactive'
  END AS "STORE_ACTIVE_STATUS",
  sp.eaushadhi_warehouse_name AS "PARENT_STORE_NAME",
  st.meta ->> 'parent_store_type' AS "PARENT_STORE_TYPE",
  COALESCE(dc.active_ddc_count, 0) AS "ACTIVE_DDC_COUNT",
  COALESCE(dc.total_ddc_count - dc.active_ddc_count, 0) AS "INACTIVE_DDC_COUNT",
  COALESCE(dc.total_ddc_count, 0) AS "TOTAL_DDC_COUNT"
FROM
  facility_facility f
  CROSS JOIN bounds b
  LEFT JOIN abdm_healthfacility hf ON hf.facility_id = f.external_id
  AND hf.deleted = FALSE
  LEFT JOIN facility_activity fa ON fa.facility_id = f.id
  LEFT JOIN ddc_counts dc ON dc.facility_id = f.id
  LEFT JOIN care_dvdms_dvdmsinstitute inst ON inst.facility_id = f.id
  AND inst.deleted = FALSE
  -- The database allows several stores / suppliers per institute (only the default
  -- is unique). LATERAL + LIMIT 1 keeps one row per facility, preferring the default;
  -- the store_id filter is repeated inside so picking a non-default store still works.
  LEFT JOIN LATERAL (
    SELECT
      s2.id,
      s2.eaushadhi_store_id,
      s2.eaushadhi_store_name,
      s2.meta
    FROM
      care_dvdms_dvdmsstore s2
    WHERE
      s2.institute_id = inst.id
      AND s2.deleted = FALSE [[AND s2.eaushadhi_store_id = {{store_id}}]]
    ORDER BY
      s2.is_default DESC,
      s2.id
    LIMIT
      1
  ) st ON TRUE
  LEFT JOIN LATERAL (
    SELECT
      p2.eaushadhi_warehouse_id,
      p2.eaushadhi_warehouse_name
    FROM
      care_dvdms_dvdmssupplier p2
    WHERE
      p2.institute_id = inst.id
      AND p2.deleted = FALSE
    ORDER BY
      p2.is_default DESC,
      p2.id
    LIMIT
      1
  ) sp ON TRUE
WHERE
  f.deleted = FALSE
  AND f.is_active = TRUE
  AND f.is_public = TRUE [[AND st.eaushadhi_store_id = {{store_id}}]]
ORDER BY
  f.name;
