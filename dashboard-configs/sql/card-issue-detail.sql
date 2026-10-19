-- Issue Detail (line items)
-- One row per dispensed line item. Drills into the Issue Summary card:
-- Issue Date + Facility ID are required; Location ID and Issue ID are optional
-- (blank = all DDCs / all issues for that day).
--
-- DVDMS drug identity is resolved from two sources, in order:
--   receipt   - the DVDMS inward item actually delivered into this inventory
--               item (exact: matches on supplied_inventory_item_id, so it is
--               specific to this product AND this location)
--   catalogue - care_dvdms_dvdmsproductmapping for the product knowledge, used
--               when there is no DVDMS receipt behind the stock
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
  (
    COALESCE(md.when_handed_over, md.when_prepared, md.created_date)
    AT TIME ZONE 'Asia/Kolkata'
  )::date                                      AS "Issue Date",
  loc.external_id                              AS "Location ID",
  loc.name                                     AS "Store",
  COALESCE(dord.external_id, md.external_id)   AS "Issue ID",
  pat.external_id                              AS "Patient ID",
  pk.name                                      AS "Product",
  COALESCE(rcpt.drug_name, map.drug_name)      AS "Drug Name",
  md.quantity                                  AS "Quantity",
  COALESCE(prod.batch ->> 'lot_number', rcpt.batch) AS "Batch No",
  COALESCE(
    (prod.expiration_date AT TIME ZONE 'Asia/Kolkata')::date,
    rcpt.expiry_date
  )                                            AS "Expiry",
  COALESCE(rcpt.drug_id, map.drug_id)          AS "Drug ID",
  COALESCE(rcpt.brand_id, map.brand_id)        AS "Drug Brand ID"
FROM
  w
  CROSS JOIN emr_medicationdispense md
  JOIN emr_facilitylocation loc ON loc.id = md.location_id
  AND loc.deleted = FALSE
  JOIN facility_facility f ON f.id = loc.facility_id
  AND f.deleted = FALSE
  JOIN emr_patient pat ON pat.id = md.patient_id
  AND pat.deleted = FALSE
  JOIN emr_inventoryitem ii ON ii.id = md.item_id
  AND ii.deleted = FALSE
  JOIN emr_product prod ON prod.id = ii.product_id
  AND prod.deleted = FALSE
  JOIN emr_productknowledge pk ON pk.id = prod.product_knowledge_id
  AND pk.deleted = FALSE
  LEFT JOIN emr_dispenseorder dord ON dord.id = md.order_id
  AND dord.deleted = FALSE
  -- Provenance: the DVDMS inward item delivered into THIS inventory item.
  LEFT JOIN LATERAL (
    SELECT
      d.drug_id,
      d.brand_id,
      d.name AS drug_name,
      iir.batch,
      iir.expiry_date
    FROM
      emr_supplydelivery sd
      JOIN care_dvdms_dvdmsrecorditemdelivery rid ON rid.supply_delivery_id = sd.id
      AND rid.deleted = FALSE
      AND rid.status <> 'REVERSED'
      JOIN care_dvdms_dvdmsinwarditemrecord iir ON iir.id = rid.inward_record_item_id
      AND iir.deleted = FALSE
      LEFT JOIN care_dvdms_dvdmsrecorditemorder rio ON rio.id = iir.record_order_item_id
      AND rio.deleted = FALSE
      LEFT JOIN care_dvdms_dvdmsdrug d ON d.id = rio.drug_id
      AND d.deleted = FALSE
    WHERE
      sd.supplied_inventory_item_id = md.item_id
      AND sd.deleted = FALSE
      AND sd.status = 'completed'
      AND sd.created_date <= COALESCE(
        md.when_handed_over,
        md.when_prepared,
        md.created_date
      )
    ORDER BY
      sd.created_date DESC
    LIMIT
      1
  ) rcpt ON TRUE
  -- Catalogue: the institute's DVDMS mapping for this product knowledge.
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
  [[AND COALESCE(dord.external_id, md.external_id) = {{issue_id}}::UUID]]
ORDER BY
  loc.name,
  COALESCE(dord.external_id, md.external_id),
  pk.name;
