-- KPI 5: Hospital Inventory Position (CARE System)
WITH
  -- The reporting day, in IST. day_end is the exclusive upper bound: the position
  -- reported below is the one at the close of that day.
  bounds AS (
    SELECT
      ({{report_date}}::DATE + 1)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata' AS day_end
  ),
  -- NOTE: the ledger CTEs below deliberately mirror
  -- care/emr/resources/inventory/inventory_item/sync_inventory_item.py, which is what
  -- computes emr_inventoryitem.net_content. Do NOT add `deleted = FALSE` filters or
  -- change the status predicates in isolation: current_stock is anchored on net_content,
  -- so any rule that differs from sync_inventory_item makes every position wrong.
  stock_movements AS (
    -- Deliveries into a location
    SELECT
      o.destination_id AS location_id,
      pr.product_knowledge_id,
      COALESCE(sd.supplied_item_quantity, 0) AS quantity,
      sd.created_date AS moved_at
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
      sd.created_date
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
      COALESCE(md.when_handed_over, md.when_prepared, md.created_date)
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
      AND pr.deleted = FALSE
    WHERE
      ii.deleted = FALSE
    GROUP BY
      ii.location_id,
      pr.product_knowledge_id
  ),
  movements_after AS (
    SELECT
      m.location_id,
      m.product_knowledge_id,
      SUM(m.quantity) AS quantity
    FROM
      stock_movements m
      CROSS JOIN bounds b
    WHERE
      m.moved_at >= b.day_end
    GROUP BY
      m.location_id,
      m.product_knowledge_id
  ),
  location_stock AS (
    -- Position at the close of the reporting day. net_content is CURRENT stock and is
    -- recomputed from scratch by sync_inventory_item out of the three movement sources
    -- above -- there is no opening balance or manual adjustment -- so undoing every
    -- movement after day_end reproduces the position on that day exactly.
    -- Caveat: deliveries are timestamped by created_date, while sync_inventory_item
    -- counts an outgoing delivery from the moment it turns in_progress. A delivery
    -- created before the reporting day but only dispatched after it is treated as
    -- already gone. Same approximation KPI 3, 4 and 7 make.
    SELECT
      l.facility_id,
      cs.location_id,
      cs.product_knowledge_id,
      cs.quantity - COALESCE(ma.quantity, 0) AS quantity
    FROM
      current_stock cs
      JOIN emr_facilitylocation l ON l.id = cs.location_id
      AND l.deleted = FALSE
      LEFT JOIN movements_after ma ON ma.location_id = cs.location_id
      AND ma.product_knowledge_id = cs.product_knowledge_id
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
  -- Every other location of the facility, i.e. the substores / DDCs. DVDMSStore.location
  -- is NOT NULL, so every row falls on exactly one side of this split and the two
  -- columns always add up to AVAILABLE_INHAND_QTY.
  COALESCE(
    SUM(ls.quantity) FILTER (
      WHERE
        ls.location_id <> st.location_id
    ),
    0
  ) AS "AVAILABLE_SUBSTORE_QTY",
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
  -- District: walk UP the geo tree from the facility's own org by parent_id.
  -- Deliberately NOT geo_organization_cache. That cache is built as
  -- [*geo_organization.parent_cache, geo_organization.id] in facility.py, so when an
  -- org's own parent_cache is empty it collapses to just the leaf and every ancestor --
  -- the district included -- becomes unreachable. Observed on deployed data: a facility
  -- whose org sits at level_cache 2 had a one-element cache holding only the local_body.
  -- Walking parent_id needs no cache to be correct. ORDER BY hops takes the nearest
  -- district ancestor; the hops guard stops a cyclic tree from looping forever.
  LEFT JOIN LATERAL (
    WITH RECURSIVE up AS (
      SELECT
        o.id,
        o.parent_id,
        0 AS hops
      FROM
        emr_organization o
      WHERE
        o.id = f.geo_organization_id
        AND o.deleted = FALSE
      UNION ALL
      SELECT
        p.id,
        p.parent_id,
        u.hops + 1
      FROM
        up u
        JOIN emr_organization p ON p.id = u.parent_id
        AND p.deleted = FALSE
      WHERE
        u.hops < 10
    )
    SELECT
      o.name
    FROM
      up u
      JOIN emr_organization o ON o.id = u.id
    WHERE
      o.org_type = 'govt'
      AND o.metadata ->> 'govt_org_type' = 'district'
    ORDER BY
      u.hops
    LIMIT
      1
  ) dist ON TRUE
WHERE
  f.deleted = FALSE
  AND f.is_active = TRUE
  AND f.is_public = TRUE [[AND st.eaushadhi_store_id = {{store_id}}]]
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