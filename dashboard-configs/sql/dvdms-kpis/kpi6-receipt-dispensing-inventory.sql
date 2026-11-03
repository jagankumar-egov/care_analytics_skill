-- KPI 6: Drug Receipt, Patient Dispensing and Available Inventory
--
-- ENGINE: PostgreSQL 16 ONLY. Uses DISTINCT ON, LATERAL, AT TIME ZONE and :: casts.
--   Running this on a SQLite/MySQL connection fails at line 1 of the first CTE with
--   `near "ON": syntax error` -- that is a wrong-database-connection error, not a bug
--   in this query. Point the editor at the CARE Postgres database (Metabase db id 2).
--
-- PARAMETERS
--   report_date  required  date   reporting day, interpreted in Asia/Kolkata
--   store_id     optional  text   eAushadhi store id
--
-- COLUMN GRAIN -- read before comparing the three quantity columns:
--   QUANTITY_RECEIVED_FROM_DVDMS  cumulative, on/before report_date
--   QUANTITY_ISSUED_TO_PATIENTS   cumulative, on/before report_date
--   AVAILABLE_QUANTITY_IN_CARE    LIVE current stock -- does NOT move with the date
--   They only reconcile when report_date is today. CARE stores no stock history,
--   so the available column cannot be rewound (see the in_care CTE below).
--
--   Received is sourced straight from DVDMS inward records; issued and available are
--   restricted to products that have a DVDMS product mapping. Products with no mapping
--   therefore contribute to neither -- received will not tie out to issued + available.
WITH
  product_drug AS (
    -- Each CARE product's DVDMS drug for the institute, most used mapping first
    -- (as _find_product_mapping), so a product is counted under one drug only
    SELECT DISTINCT ON (pm.institute_id, pm.product_knowledge_id)
      pm.institute_id,
      pm.product_knowledge_id,
      pm.eaushadhi_drug_id,
      dr.name
    FROM
      care_dvdms_dvdmsproductmapping pm
      JOIN care_dvdms_dvdmsdrug dr ON dr.id = pm.drug_id
    WHERE
      pm.deleted = FALSE
    ORDER BY
      pm.institute_id,
      pm.product_knowledge_id,
      pm.usage_count DESC,
      pm.modified_date DESC
  ),
  received AS (
    SELECT
      ir.institute_id,
      iir.drug_id AS eaushadhi_drug_id,
      MIN(iir.drug_name) AS drug_name,
      SUM(rid.quantity_accepted) AS quantity
    FROM
      care_dvdms_dvdmsrecorditemdelivery rid
      JOIN care_dvdms_dvdmsrecorddelivery rd ON rd.id = rid.record_delivery_id
      AND rd.deleted = FALSE
      AND rd.status IN ('received', 'acknowledged', 'acknowledgement_failed')
      JOIN care_dvdms_dvdmsinwarditemrecord iir ON iir.id = rid.inward_record_item_id
      AND iir.deleted = FALSE
      JOIN care_dvdms_dvdmsinwardrecord ir ON ir.id = iir.inward_record_id
      AND ir.deleted = FALSE
    WHERE
      rid.deleted = FALSE
      AND rid.status <> 'REVERSED'
      -- Cumulative: everything received on or before the reporting day
      AND (rid.created_date AT TIME ZONE 'Asia/Kolkata')::DATE <= {{report_date}}
    GROUP BY
      ir.institute_id,
      iir.drug_id
  ),
  issued AS (
    SELECT
      pd.institute_id,
      pd.eaushadhi_drug_id,
      SUM(md.quantity) AS quantity
    FROM
      emr_medicationdispense md
      JOIN emr_facilitylocation l ON l.id = md.location_id
      AND l.deleted = FALSE
      JOIN care_dvdms_dvdmsinstitute inst ON inst.facility_id = l.facility_id
      AND inst.deleted = FALSE
      JOIN emr_inventoryitem ii ON ii.id = md.item_id
      AND ii.deleted = FALSE
      JOIN emr_product pr ON pr.id = ii.product_id
      AND pr.deleted = FALSE
      JOIN product_drug pd ON pd.institute_id = inst.id
      AND pd.product_knowledge_id = pr.product_knowledge_id
    WHERE
      md.deleted = FALSE
      AND md.status NOT IN ('cancelled', 'entered_in_error', 'stopped', 'declined')
      -- Cumulative: everything issued on or before the reporting day
      AND (COALESCE(md.when_handed_over, md.when_prepared, md.created_date) AT TIME ZONE 'Asia/Kolkata')::DATE <= {{report_date}}
    GROUP BY
      pd.institute_id,
      pd.eaushadhi_drug_id
  ),
  -- LIVE, not as-of: net_content is current stock and CARE keeps no history, so this
  -- column does NOT move with {{report_date}} while RECEIVED and ISSUED above do. The
  -- three columns are only on the same grain when the reporting day is today.
  in_care AS (
    SELECT
      pd.institute_id,
      pd.eaushadhi_drug_id,
      SUM(ii.net_content) AS quantity
    FROM
      emr_inventoryitem ii
      JOIN emr_facilitylocation l ON l.id = ii.location_id
      AND l.deleted = FALSE
      JOIN care_dvdms_dvdmsinstitute inst ON inst.facility_id = l.facility_id
      AND inst.deleted = FALSE
      JOIN emr_product pr ON pr.id = ii.product_id
      AND pr.deleted = FALSE
      JOIN product_drug pd ON pd.institute_id = inst.id
      AND pd.product_knowledge_id = pr.product_knowledge_id
    WHERE
      ii.deleted = FALSE
    GROUP BY
      pd.institute_id,
      pd.eaushadhi_drug_id
  ),
  drugs AS (
    SELECT institute_id, eaushadhi_drug_id FROM received
    UNION
    SELECT institute_id, eaushadhi_drug_id FROM issued
    UNION
    SELECT institute_id, eaushadhi_drug_id FROM in_care
  )
SELECT
  st.eaushadhi_store_id AS "STORE_ID",
  st.eaushadhi_store_name AS "STORE_NAME",
  sp.eaushadhi_warehouse_id AS "PARENT_STORE_ID",
  sp.eaushadhi_warehouse_name AS "PARENT_STORE_NAME",
  d.eaushadhi_drug_id AS "DRUG_ID",
  COALESCE(pd.name, r.drug_name) AS "DRUG_NAME",
  COALESCE(r.quantity, 0) AS "QUANTITY_RECEIVED_FROM_DVDMS",
  COALESCE(i.quantity, 0) AS "QUANTITY_ISSUED_TO_PATIENTS",
  COALESCE(c.quantity, 0) AS "AVAILABLE_QUANTITY_IN_CARE"
FROM
  drugs d
  JOIN care_dvdms_dvdmsinstitute inst ON inst.id = d.institute_id
  AND inst.deleted = FALSE
  JOIN facility_facility f ON f.id = inst.facility_id
  AND f.deleted = FALSE
  AND f.is_active = TRUE
  AND f.is_public = TRUE
  LEFT JOIN received r ON r.institute_id = d.institute_id
  AND r.eaushadhi_drug_id = d.eaushadhi_drug_id
  LEFT JOIN issued i ON i.institute_id = d.institute_id
  AND i.eaushadhi_drug_id = d.eaushadhi_drug_id
  LEFT JOIN in_care c ON c.institute_id = d.institute_id
  AND c.eaushadhi_drug_id = d.eaushadhi_drug_id
  -- At most one: a drug ID is mapped once per institute
  LEFT JOIN product_drug pd ON pd.institute_id = d.institute_id
  AND pd.eaushadhi_drug_id = d.eaushadhi_drug_id
  -- Default store and supplier, as in KPI 1
  LEFT JOIN LATERAL (
    SELECT
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
  TRUE
  [[AND st.eaushadhi_store_id = {{store_id}}]]
ORDER BY
  "STORE_NAME",
  "DRUG_NAME";
