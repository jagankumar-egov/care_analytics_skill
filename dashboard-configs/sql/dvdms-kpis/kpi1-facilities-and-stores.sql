-- KPI 1: Facilities and Stores
WITH
  -- The reporting day, in IST. day_end is the exclusive upper bound, so every window
  -- below ends at midnight IST after the selected date and the card is reproducible
  -- for any past date instead of drifting with NOW().
  bounds AS (
    SELECT
      ({{report_date}}::DATE)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata' AS day_start,
      ({{report_date}}::DATE + 1)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata' AS day_end
  ),
  activity AS (
    -- Facility-scoped EMR writes in the last 30 days (the widest window used below)
    SELECT
      e.facility_id,
      e.created_by_id,
      e.created_date
    FROM
      emr_encounter e
      CROSS JOIN bounds b
    WHERE
      e.deleted = FALSE
      AND e.created_date >= b.day_end - INTERVAL '30 days'
      AND e.created_date < b.day_end
    UNION ALL
    SELECT
      l.facility_id,
      md.created_by_id,
      md.created_date
    FROM
      emr_medicationdispense md
      CROSS JOIN bounds b
      JOIN emr_facilitylocation l ON l.id = md.location_id
      AND l.deleted = FALSE
    WHERE
      md.deleted = FALSE
      AND md.created_date >= b.day_end - INTERVAL '30 days'
      AND md.created_date < b.day_end
    UNION ALL
    SELECT
      l.facility_id,
      d.created_by_id,
      d.created_date
    FROM
      emr_deliveryorder d
      CROSS JOIN bounds b
      JOIN emr_facilitylocation l ON l.id = d.destination_id
      AND l.deleted = FALSE
    WHERE
      d.deleted = FALSE
      AND d.created_date >= b.day_end - INTERVAL '30 days'
      AND d.created_date < b.day_end
    UNION ALL
    SELECT
      l.facility_id,
      r.created_by_id,
      r.created_date
    FROM
      emr_requestorder r
      CROSS JOIN bounds b
      JOIN emr_facilitylocation l ON l.id = r.destination_id
      AND l.deleted = FALSE
    WHERE
      r.deleted = FALSE
      AND r.created_date >= b.day_end - INTERVAL '30 days'
      AND r.created_date < b.day_end
  ),
  facility_activity AS (
    SELECT
      a.facility_id,
      COUNT(DISTINCT a.created_by_id) FILTER (
        WHERE
          a.created_date >= b.day_end - INTERVAL '7 days'
      ) AS active_users
    FROM
      activity a
      CROSS JOIN bounds b
    GROUP BY
      a.facility_id
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
  CASE
    WHEN st.id IS NULL THEN NULL
    WHEN EXISTS (
      -- Indent raised
      SELECT
        1
      FROM
        care_dvdms_dvdmsoutwardrecordorder o
        JOIN care_dvdms_dvdmsrecordorder ro ON ro.id = o.record_order_id
      WHERE
        ro.institute_store_id = st.id
        AND o.deleted = FALSE
        AND o.status = 'submitted'
        AND o.modified_date >= b.day_end - INTERVAL '7 days'
        AND o.modified_date < b.day_end
    )
    OR EXISTS (
      -- Issue received; inward records with no outward_record can't be tied to a store
      SELECT
        1
      FROM
        care_dvdms_dvdmsinwardrecord i
        JOIN care_dvdms_dvdmsoutwardrecordorder o ON o.id = i.outward_record_id
        JOIN care_dvdms_dvdmsrecordorder ro ON ro.id = o.record_order_id
      WHERE
        ro.institute_store_id = st.id
        AND i.deleted = FALSE
        AND i.created_date >= b.day_end - INTERVAL '7 days'
        AND i.created_date < b.day_end
    ) THEN 'Active'
    ELSE 'Inactive'
  END AS "STORE_ACTIVE_STATUS",
  sp.eaushadhi_warehouse_name AS "PARENT_STORE_NAME",
  COALESCE(fa.active_users, 0) AS "ACTIVE_USERS_COUNT"
FROM
  facility_facility f
  CROSS JOIN bounds b
  LEFT JOIN abdm_healthfacility hf ON hf.facility_id = f.external_id
  AND hf.deleted = FALSE
  LEFT JOIN facility_activity fa ON fa.facility_id = f.id
  LEFT JOIN care_dvdms_dvdmsinstitute inst ON inst.facility_id = f.id
  AND inst.deleted = FALSE
  -- One store / one supplier per institute is enforced in the UI, not in the
  -- database. LATERAL + LIMIT 1 keeps one row per facility, preferring the default.
  LEFT JOIN LATERAL (
    SELECT
      s2.id,
      s2.eaushadhi_store_id,
      s2.eaushadhi_store_name
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