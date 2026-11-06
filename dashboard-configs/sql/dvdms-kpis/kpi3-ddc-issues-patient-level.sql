

-- KPI 3: Active DDC Issues (Patient Level)
SELECT
  st.eaushadhi_store_id AS "STORE_ID",
  st.eaushadhi_store_name AS "STORE_NAME",
  -- eAushadhi's store type (sststrTypeName) is only read from the lookup API to group
  -- the store picker; the store mapping never persists it, so STORE_TYPE stays NULL
  -- until that mapping writes the type into meta.
  st.meta ->> 'store_type' AS "STORE_TYPE",
  dist.name AS "DISTRICT_NAME",
  mrp.meta ->> 'eaushadhi_prescription_id' AS "PRESCRIPTION_ID",
  (MIN(COALESCE(mr.authored_on, mrp.created_date)) AT TIME ZONE 'Asia/Kolkata')::DATE AS "PRESCRIPTION_DATE",
  (COALESCE(md.when_handed_over, md.when_prepared, md.created_date) AT TIME ZONE 'Asia/Kolkata')::DATE AS "DISPENSE_DATE",
  uhid.value AS "PATIENT_UHID",
  ab.abha_number AS "ABHA_ID",
  p.gender AS "PATIENT_GENDER",
  -- Completed years AT THE TIME OF THE DISPENSE, not today, so a report run for a past
  -- date stays stable. Mirrors Patient.age in care/emr/models/patient.py: start at
  -- date_of_birth, else 1 Jan of year_of_birth; stop at date of death if there is one
  -- (LEAST ignores NULLs, so a living patient just uses the dispense date). NULL when
  -- neither date_of_birth nor year_of_birth is recorded.
  EXTRACT(
    YEAR
    FROM
      AGE(
        LEAST(
          (COALESCE(md.when_handed_over, md.when_prepared, md.created_date) AT TIME ZONE 'Asia/Kolkata')::DATE,
          (p.deceased_datetime AT TIME ZONE 'Asia/Kolkata')::DATE
        ),
        COALESCE(p.date_of_birth, MAKE_DATE(p.year_of_birth, 1, 1))
      )
  )::INT AS "PATIENT_AGE",
  -- Dispense lines; the same drug dispensed twice counts as two items
  COUNT(*) AS "NUMBER_OF_ITEMS"
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
  -- Dispenses happen at DDC counters, so each one is attributed to the
  -- institute's store (default first), as in KPI 2
  JOIN LATERAL (
    SELECT
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
  -- Kept so the dispenses counted here are the same rows KPI 4 lists
  JOIN emr_inventoryitem ii ON ii.id = md.item_id
  AND ii.deleted = FALSE
  JOIN emr_product pr ON pr.id = ii.product_id
  AND pr.deleted = FALSE
  JOIN emr_patient p ON p.id = md.patient_id
  AND p.deleted = FALSE
  LEFT JOIN emr_medicationrequest mr ON mr.id = md.authorizing_request_id
  AND mr.deleted = FALSE
  LEFT JOIN emr_medicationrequestprescription mrp ON mrp.id = mr.prescription_id
  AND mrp.deleted = FALSE
  LEFT JOIN abdm_abhanumber ab ON ab.patient_id = p.id
  AND ab.deleted = FALSE
  -- District: the facility's geo organization or one of its parents
  LEFT JOIN LATERAL (
    SELECT
      o.name
    FROM
      emr_organization o
    WHERE
      o.id = ANY (f.geo_organization_cache)
      AND o.org_type = 'govt'
      AND o.metadata ->> 'govt_org_type' = 'district'
      AND o.deleted = FALSE
    LIMIT
      1
  ) dist ON TRUE
  -- UHID: identifier whose config display is "UHID", as get_patient_uhid in care_radiology.
  -- Read from PatientIdentifier, which backs both Patient.instance_identifiers and
  -- Patient.facility_identifiers, so a UHID configured for the facility is found too
  LEFT JOIN LATERAL (
    SELECT
      pi.value
    FROM
      emr_patientidentifier pi
      JOIN emr_patientidentifierconfig c ON c.id = pi.config_id
    WHERE
      pi.patient_id = p.id
      AND pi.deleted = FALSE
      AND pi.value <> ''
      AND LOWER(c.config ->> 'display') = 'uhid'
      AND (
        c.facility_id IS NULL
        OR c.facility_id = f.id
      )
    ORDER BY
      c.facility_id NULLS FIRST
    LIMIT
      1
  ) uhid ON TRUE
WHERE
  md.deleted = FALSE
  AND md.status NOT IN ('cancelled', 'entered_in_error', 'stopped', 'declined')
  [[AND st.eaushadhi_store_id = {{store_id}}]]
  -- Mandatory: no [[ ]], so Metabase requires the parameter.
  AND (COALESCE(md.when_handed_over, md.when_prepared, md.created_date) AT TIME ZONE 'Asia/Kolkata')::DATE = {{dispense_date}}
-- One row per prescription; dispenses with no prescription are grouped per patient
GROUP BY
  st.eaushadhi_store_id,
  st.eaushadhi_store_name,
  st.meta,
  dist.name,
  mrp.id,
  p.id,
  uhid.value,
  ab.abha_number,
  (COALESCE(md.when_handed_over, md.when_prepared, md.created_date) AT TIME ZONE 'Asia/Kolkata')::DATE
ORDER BY
  MAX(COALESCE(md.when_handed_over, md.when_prepared, md.created_date)) DESC,
  mrp.id DESC;
