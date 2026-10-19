-- Stock Transfers (sent & received)
-- One row per completed supply delivery line. Same shape as Issue Detail, but
-- the counterparty is a store rather than a patient.
--
-- Filters: Issue Date + Facility ID required; Location ID and Drug ID optional.
--   Location ID matches EITHER side - a store's sent and received rows both
--   appear when you filter by it.
--   Facility scope is "origin OR destination belongs to the facility", so a
--   transfer received from another facility shows up here too.
--
-- DVDMS drug identity resolves in two steps:
--   receipt   - the DVDMS inward item tied to this exact supply delivery
--               (care_dvdms_dvdmsrecorditemdelivery.supply_delivery_id)
--   catalogue - care_dvdms_dvdmsproductmapping for the product knowledge,
--               which is what internal store-to-store transfers fall back on
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
  (sd.created_date AT TIME ZONE 'Asia/Kolkata')::date AS "Transfer Date",
  orig.external_id                             AS "From Store ID",
  COALESCE(orig.name, sup.name)                AS "From Store",
  dest.external_id                             AS "To Store ID",
  dest.name                                    AS "To Store",
  pk.name                                      AS "Product",
  COALESCE(d.name, map.drug_name)              AS "Drug Name",
  sd.supplied_item_quantity                    AS "Quantity",
  COALESCE(prod.batch ->> 'lot_number', iir.batch) AS "Batch No",
  COALESCE(
    (prod.expiration_date AT TIME ZONE 'Asia/Kolkata')::date,
    iir.expiry_date
  )                                            AS "Expiry",
  COALESCE(d.drug_id, map.drug_id)             AS "Drug ID",
  COALESCE(d.brand_id, map.brand_id)           AS "Drug Brand ID"
FROM
  w
  CROSS JOIN facility_facility f
  CROSS JOIN emr_supplydelivery sd
  JOIN emr_deliveryorder dor ON dor.id = sd.order_id
  AND dor.deleted = FALSE
  JOIN emr_facilitylocation dest ON dest.id = dor.destination_id
  AND dest.deleted = FALSE
  LEFT JOIN emr_facilitylocation orig ON orig.id = dor.origin_id
  AND orig.deleted = FALSE
  LEFT JOIN emr_organization sup ON sup.id = dor.supplier_id
  AND sup.deleted = FALSE
  LEFT JOIN emr_inventoryitem ii ON ii.id = sd.supplied_inventory_item_id
  AND ii.deleted = FALSE
  JOIN emr_product prod ON prod.id = COALESCE(ii.product_id, sd.supplied_item_id)
  AND prod.deleted = FALSE
  JOIN emr_productknowledge pk ON pk.id = prod.product_knowledge_id
  AND pk.deleted = FALSE
  -- Receipt provenance: one-to-one with this supply delivery, so no guessing.
  LEFT JOIN care_dvdms_dvdmsrecorditemdelivery rid ON rid.supply_delivery_id = sd.id
  AND rid.deleted = FALSE
  AND rid.status <> 'REVERSED'
  LEFT JOIN care_dvdms_dvdmsinwarditemrecord iir ON iir.id = rid.inward_record_item_id
  AND iir.deleted = FALSE
  LEFT JOIN care_dvdms_dvdmsrecorditemorder rio ON rio.id = iir.record_order_item_id
  AND rio.deleted = FALSE
  LEFT JOIN care_dvdms_dvdmsdrug d ON d.id = rio.drug_id
  AND d.deleted = FALSE
  -- Catalogue fallback: the institute's mapping for this product knowledge.
  LEFT JOIN LATERAL (
    SELECT
      d2.drug_id,
      d2.brand_id,
      d2.name AS drug_name
    FROM
      care_dvdms_dvdmsproductmapping pm
      JOIN care_dvdms_dvdmsinstitute inst ON inst.id = pm.institute_id
      AND inst.deleted = FALSE
      AND inst.facility_id = f.id
      JOIN care_dvdms_dvdmsdrug d2 ON d2.id = pm.drug_id
      AND d2.deleted = FALSE
    WHERE
      pm.product_knowledge_id = pk.id
      AND pm.deleted = FALSE
    ORDER BY
      (pm.mapping_type = 'manual_mapping') DESC,
      pm.usage_count DESC,
      pm.last_used_date DESC NULLS LAST
    LIMIT
      1
  ) map ON TRUE
WHERE
  sd.deleted = FALSE
  AND sd.status = 'completed'
  AND f.deleted = FALSE
  AND f.external_id = {{facility_id}}::UUID
  AND (
    orig.facility_id = f.id
    OR dest.facility_id = f.id
  )
  AND (sd.created_date AT TIME ZONE 'Asia/Kolkata')::date = w.end_date
  [[AND (
    orig.external_id = {{location_id}}::UUID
    OR dest.external_id = {{location_id}}::UUID
  )]]
  [[AND COALESCE(d.drug_id, map.drug_id) = {{drug_id}}]]
ORDER BY
  COALESCE(orig.name, sup.name),
  dest.name,
  pk.name;
