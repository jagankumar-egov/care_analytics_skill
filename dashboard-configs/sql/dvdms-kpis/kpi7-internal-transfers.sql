-- KPI 7: Internal Transfers
WITH
  -- NOTE: the ledger CTEs below deliberately mirror
  -- care/emr/resources/inventory/inventory_item/sync_inventory_item.py, which is what
  -- computes emr_inventoryitem.net_content. Do NOT add `deleted = FALSE` filters or
  -- change the status predicates in isolation: current_stock is anchored on net_content,
  -- so any rule that differs from sync_inventory_item makes every stock_after wrong.
  stock_movements AS (
    -- Deliveries into a location
    SELECT
      o.destination_id AS location_id,
      pr.product_knowledge_id,
      COALESCE(sd.supplied_item_quantity, 0) AS quantity,
      sd.created_date AS moved_at,
      'delivery_in' AS movement,
      sd.id AS ref_id
    FROM
      emr_supplydelivery sd
      JOIN emr_deliveryorder o ON o.id = sd.order_id
      LEFT JOIN emr_inventoryitem sii ON sii.id = sd.supplied_inventory_item_id
      JOIN emr_product pr ON pr.id = COALESCE(sd.supplied_item_id, sii.product_id)
    WHERE
      sd.deleted = FALSE
      AND sd.status = 'completed'
    UNION ALL
    -- Deliveries out of a location
    SELECT
      o.origin_id,
      pr.product_knowledge_id,
      -COALESCE(sd.supplied_item_quantity, 0),
      sd.created_date,
      'delivery_out',
      sd.id
    FROM
      emr_supplydelivery sd
      JOIN emr_deliveryorder o ON o.id = sd.order_id
      LEFT JOIN emr_inventoryitem sii ON sii.id = sd.supplied_inventory_item_id
      JOIN emr_product pr ON pr.id = COALESCE(sd.supplied_item_id, sii.product_id)
    WHERE
      sd.deleted = FALSE
      -- sync_inventory_item subtracts outgoing stock at in_progress AND completed,
      -- so net_content already reflects in-flight transfers out of the origin.
      AND sd.status IN ('in_progress', 'completed')
      AND o.origin_id IS NOT NULL
    UNION ALL
    -- Dispenses from a location
    SELECT
      md.location_id,
      pr.product_knowledge_id,
      -md.quantity,
      COALESCE(md.when_handed_over, md.when_prepared, md.created_date),
      'dispense',
      md.id
    FROM
      emr_medicationdispense md
      JOIN emr_inventoryitem ii ON ii.id = md.item_id
      JOIN emr_product pr ON pr.id = ii.product_id
    WHERE
      md.deleted = FALSE
      AND md.status NOT IN ('cancelled', 'entered_in_error', 'stopped', 'declined')
  ),
  current_stock AS (
    SELECT
      ii.location_id,
      pr.product_knowledge_id,
      SUM(ii.net_content) AS quantity
    FROM
      emr_inventoryitem ii
      JOIN emr_product pr ON pr.id = ii.product_id
    WHERE
      ii.deleted = FALSE
    GROUP BY
      ii.location_id,
      pr.product_knowledge_id
  ),
  stock_ledger AS (
    -- Opening stock is not always recorded as a delivery, so instead of summing up from
    -- zero, start at today's stock and undo every movement after the row; that gives
    -- the location's stock just after the row's movement
    SELECT
      m.ref_id,
      m.movement,
      COALESCE(cs.quantity, 0) - COALESCE(
        SUM(m.quantity) OVER (
          PARTITION BY
            m.location_id,
            m.product_knowledge_id
          ORDER BY
            m.moved_at,
            m.movement,
            m.ref_id ROWS BETWEEN 1 FOLLOWING AND UNBOUNDED FOLLOWING
        ),
        0
      ) AS stock_after
    FROM
      stock_movements m
      LEFT JOIN current_stock cs ON cs.location_id = m.location_id
      AND cs.product_knowledge_id = m.product_knowledge_id
  )
SELECT
  st.eaushadhi_store_id AS "STORE_ID",
  (sd.created_date AT TIME ZONE 'Asia/Kolkata')::DATE AS "TRANSFER_DATE",
  fl.name AS "FROM_STORE",
  tl.name AS "TO_STORE",
  pk.name AS "PRODUCT",
  drug.name AS "DRUG_NAME",
  sd.supplied_item_quantity AS "QUANTITY",
  pr.batch ->> 'lot_number' AS "BATCH_NO",
  (pr.expiration_date AT TIME ZONE 'Asia/Kolkata')::DATE AS "EXPIRY",
  drug.eaushadhi_drug_id AS "DRUG_ID",
  NULLIF(drug.brand_id, '') AS "DRUG_BRAND_ID",
  slo.stock_after + COALESCE(sd.supplied_item_quantity, 0) AS "FROM_STORE_INVENTORY_STOCK_COUNT_BEFORE_TRANSACTION",
  slo.stock_after AS "FROM_STORE_INVENTORY_STOCK_COUNT_AFTER_TRANSACTION",
  sli.stock_after - COALESCE(sd.supplied_item_quantity, 0) AS "TO_STORE_INVENTORY_STOCK_COUNT_BEFORE_TRANSACTION",
  sli.stock_after AS "TO_STORE_INVENTORY_STOCK_COUNT_AFTER_TRANSACTION"
FROM
  emr_supplydelivery sd
  JOIN emr_deliveryorder o ON o.id = sd.order_id
  AND o.deleted = FALSE
  JOIN emr_facilitylocation fl ON fl.id = o.origin_id
  AND fl.deleted = FALSE
  -- A transfer: origin and destination both in the same facility
  JOIN emr_facilitylocation tl ON tl.id = o.destination_id
  AND tl.deleted = FALSE
  AND tl.facility_id = fl.facility_id
  JOIN facility_facility f ON f.id = fl.facility_id
  AND f.deleted = FALSE
  AND f.is_active = TRUE
  AND f.is_public = TRUE
  JOIN care_dvdms_dvdmsinstitute inst ON inst.facility_id = f.id
  AND inst.deleted = FALSE
  -- The facility's store (default first), as in KPI 1
  JOIN LATERAL (
    SELECT
      s2.eaushadhi_store_id
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
  LEFT JOIN emr_inventoryitem sii ON sii.id = sd.supplied_inventory_item_id
  AND sii.deleted = FALSE
  JOIN emr_product pr ON pr.id = COALESCE(sd.supplied_item_id, sii.product_id)
  AND pr.deleted = FALSE
  JOIN emr_productknowledge pk ON pk.id = pr.product_knowledge_id
  AND pk.deleted = FALSE
  LEFT JOIN stock_ledger slo ON slo.ref_id = sd.id
  AND slo.movement = 'delivery_out'
  LEFT JOIN stock_ledger sli ON sli.ref_id = sd.id
  AND sli.movement = 'delivery_in'
  -- Drug: the institute's mapping for the product, most used first (as _find_product_mapping)
  LEFT JOIN LATERAL (
    SELECT
      pm.eaushadhi_drug_id,
      dr.name,
      dr.brand_id
    FROM
      care_dvdms_dvdmsproductmapping pm
      JOIN care_dvdms_dvdmsdrug dr ON dr.id = pm.drug_id
    WHERE
      pm.institute_id = inst.id
      AND pm.product_knowledge_id = pr.product_knowledge_id
      AND pm.deleted = FALSE
    ORDER BY
      pm.usage_count DESC,
      pm.modified_date DESC
    LIMIT
      1
  ) drug ON TRUE
WHERE
  sd.deleted = FALSE
  AND sd.status = 'completed'
  [[AND st.eaushadhi_store_id = {{store_id}}]]
  -- Mandatory: no [[ ]], so Metabase requires the parameter.
  AND (sd.created_date AT TIME ZONE 'Asia/Kolkata')::DATE = {{transfer_date}}
  -- Matches either side of the transfer, as in the existing card
  [[AND {{location_name}} IN (fl.name, tl.name)]]
ORDER BY
  sd.created_date DESC,
  sd.id DESC;
