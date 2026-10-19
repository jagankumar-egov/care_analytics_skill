SELECT
  f.external_id                 AS facility_id,
  f.name                        AS facility_name,
  geo.name                      AS geo_organization,
  inst.eaushadhi_institute_id   AS institute_id,
  inst.eaushadhi_institute_name AS institute_name,
  st.eaushadhi_store_id         AS store_id,
  st.eaushadhi_store_name       AS store_name,
  stloc.name                    AS store_location,
  sp.eaushadhi_warehouse_id     AS supplier_id,
  sp.eaushadhi_warehouse_name   AS supplier_name,
  sporg.name                    AS supplier_organization,
  CASE
    WHEN inst.id IS NULL THEN 'Not onboarded'
    WHEN st.id IS NULL
      OR sp.id IS NULL THEN 'Incomplete mapping'
    ELSE 'Configured'
  END                           AS dvdms_status
FROM
  facility_facility f
  LEFT JOIN emr_organization geo ON geo.id = f.geo_organization_id
  AND geo.deleted = FALSE
  LEFT JOIN care_dvdms_dvdmsinstitute inst ON inst.facility_id = f.id
  AND inst.deleted = FALSE
  -- One store / one supplier per institute is enforced in the UI, not in the
  -- database (the only DB constraint is one *default* per institute). LATERAL
  -- + LIMIT 1 keeps this one row per facility even if that invariant slips.
  LEFT JOIN LATERAL (
    SELECT
      s2.id,
      s2.eaushadhi_store_id,
      s2.eaushadhi_store_name,
      s2.location_id
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
  LEFT JOIN emr_facilitylocation stloc ON stloc.id = st.location_id
  AND stloc.deleted = FALSE
  LEFT JOIN LATERAL (
    SELECT
      p2.id,
      p2.eaushadhi_warehouse_id,
      p2.eaushadhi_warehouse_name,
      p2.supplier_id
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
  LEFT JOIN emr_organization sporg ON sporg.id = sp.supplier_id
  AND sporg.deleted = FALSE
WHERE
  f.deleted = FALSE
  AND f.is_active = TRUE
  -- Inherited from the original card. Drop this line to also list facilities
  -- that are not flagged public (is_public defaults to FALSE).
  AND f.is_public = TRUE
  [[AND f.external_id = {{facility_id}}::UUID]]
ORDER BY
  f.name;
