-- KPI 5: Hospital Inventory Position (CARE System)
WITH
  location_stock AS (
    SELECT
      l.facility_id,
      ii.location_id,
      pr.product_knowledge_id,
      SUM(ii.net_content) AS quantity
    FROM
      emr_inventoryitem ii
      JOIN emr_product pr ON pr.id = ii.product_id
      AND pr.deleted = FALSE
      JOIN emr_facilitylocation l ON l.id = ii.location_id
      AND l.deleted = FALSE
    WHERE
      ii.deleted = FALSE
    GROUP BY
      l.facility_id,
      ii.location_id,
      pr.product_knowledge_id
  )
SELECT
  st.eaushadhi_store_id AS "STORE_ID",
  st.eaushadhi_store_name AS "STORE_NAME",
  dist.name AS "DISTRICT_NAME",
  drug.eaushadhi_drug_id AS "DRUG_ITEM_ID",
  -- Products with no DVDMS mapping fall back to the CARE product name
  COALESCE(drug.name, pk.name) AS "DRUG_ITEM_NAME",
  COALESCE(
    SUM(ls.quantity) FILTER (
      WHERE
        ls.location_id = st.location_id
    ),
    0
  ) AS "AVAILABLE_MAIN_STORE_QTY",
  SUM(ls.quantity) AS "AVAILABLE_INHAND_QTY"
FROM
  facility_facility f
  JOIN care_dvdms_dvdmsinstitute inst ON inst.facility_id = f.id
  AND inst.deleted = FALSE
  -- Main store: the institute's default store (first store if none is marked default)
  JOIN LATERAL (
    SELECT
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
  JOIN location_stock ls ON ls.facility_id = f.id
  JOIN emr_productknowledge pk ON pk.id = ls.product_knowledge_id
  AND pk.deleted = FALSE
  -- Drug: the institute's mapping for the product, most used first (as _find_product_mapping)
  LEFT JOIN LATERAL (
    SELECT
      pm.eaushadhi_drug_id,
      dr.name
    FROM
      care_dvdms_dvdmsproductmapping pm
      JOIN care_dvdms_dvdmsdrug dr ON dr.id = pm.drug_id
    WHERE
      pm.institute_id = inst.id
      AND pm.product_knowledge_id = ls.product_knowledge_id
      AND pm.deleted = FALSE
    ORDER BY
      pm.usage_count DESC,
      pm.modified_date DESC
    LIMIT
      1
  ) drug ON TRUE
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
WHERE
  f.deleted = FALSE
  AND f.is_active = TRUE
  AND f.is_public = TRUE [[AND st.eaushadhi_store_id = {{store_id}}]]
  -- Mandatory date parameter, deliberately non-filtering.
  -- This card reports a LIVE inventory position read from emr_inventoryitem.net_content.
  -- CARE stores no stock history, so the position cannot be rewound to a past date. The
  -- parameter is required only so the dashboard date filter binds to every card; the
  -- quantities below are CURRENT stock whatever date is selected.
  AND {{report_date}} IS NOT NULL
GROUP BY
  f.id,
  st.eaushadhi_store_id,
  st.eaushadhi_store_name,
  dist.name,
  pk.id,
  drug.eaushadhi_drug_id,
  drug.name
ORDER BY
  "STORE_NAME",
  "DRUG_ITEM_NAME";