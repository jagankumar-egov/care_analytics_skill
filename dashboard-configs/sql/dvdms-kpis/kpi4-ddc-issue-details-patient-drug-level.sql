-- KPI 4: Active DDC Issue Details (Patient and Drug Level)
WITH
  timing_units (code, days) AS (
    VALUES
      ('s', 1 / 86400.0),
      ('min', 1 / 1440.0),
      ('h', 1 / 24.0),
      ('d', 1.0),
      ('wk', 7.0),
      ('mo', 30.0),
      ('a', 365.0)
  ),
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
      0 AS is_dispense,
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
      0,
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
      1,
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
    -- zero, start at today's stock and undo every movement after the row; on a dispense
    -- row that gives the stock just after that dispense
    SELECT
      m.ref_id AS dispense_id,
      m.is_dispense,
      COALESCE(cs.quantity, 0) - COALESCE(
        SUM(m.quantity) OVER (
          PARTITION BY
            m.location_id,
            m.product_knowledge_id
          ORDER BY
            m.moved_at,
            m.is_dispense,
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
  -- eAushadhi's store type (sststrTypeName) is only read from the lookup API to group
  -- the store picker; the store mapping never persists it, so STORE_TYPE stays NULL
  -- until that mapping writes the type into meta.
  st.meta ->> 'store_type' AS "STORE_TYPE",
  -- The DDC counter the dispense happened at, as in KPI 2
  l.name AS "DDC_NAME",
  mrp.meta ->> 'eaushadhi_prescription_id' AS "PRESCRIPTION_ID",
  (COALESCE(md.when_handed_over, md.when_prepared, md.created_date) AT TIME ZONE 'Asia/Kolkata')::DATE AS "DISPENSE_DATE",
  uhid.value AS "PATIENT_UHID",
  ab.abha_number AS "ABHA_ID",
  drug.eaushadhi_drug_id AS "DRUG_ID",
  pk.name AS "PATIENT_WISE_DRUG_SENT",
  NULLIF(drug.brand_id, '') AS "DRUG_BRAND_DETAILS",
  pr.batch ->> 'lot_number' AS "BATCH_NUMBER",
  (pr.expiration_date AT TIME ZONE 'Asia/Kolkata')::DATE AS "EXPIRY_DATE",
  -- Times this drug was sent to this patient, within the filtered rows
  COUNT(*) OVER (
    PARTITION BY
      md.patient_id,
      pr.product_knowledge_id
  ) AS "SENT_COUNT",
  sl.stock_after + md.quantity AS "STORES_AVAILABLE_STOCK",
  qp.quantity AS "QUANTITY_REQUESTED",
  md.quantity AS "QUANTITY_SENT",
  sl.stock_after AS "UPDATED_INVENTORY_QUANTITY"
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
  JOIN emr_inventoryitem ii ON ii.id = md.item_id
  AND ii.deleted = FALSE
  JOIN emr_product pr ON pr.id = ii.product_id
  AND pr.deleted = FALSE
  JOIN emr_productknowledge pk ON pk.id = pr.product_knowledge_id
  AND pk.deleted = FALSE
  JOIN emr_patient p ON p.id = md.patient_id
  AND p.deleted = FALSE
  LEFT JOIN emr_medicationrequest mr ON mr.id = md.authorizing_request_id
  AND mr.deleted = FALSE
  LEFT JOIN emr_medicationrequestprescription mrp ON mrp.id = mr.prescription_id
  AND mrp.deleted = FALSE
  LEFT JOIN abdm_abhanumber ab ON ab.patient_id = p.id
  AND ab.deleted = FALSE
  LEFT JOIN stock_ledger sl ON sl.dispense_id = md.id
  AND sl.is_dispense = 1
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
  -- Drug: the institute's mapping for the product, most used first (as _find_product_mapping)
  LEFT JOIN LATERAL (
    SELECT
      pm.eaushadhi_drug_id,
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
  -- Quantity requested: dose x frequency x (duration / period), summed over dosage instructions
  LEFT JOIN LATERAL (
    SELECT
      SUM(
        (di -> 'dose_and_rate' -> 'dose_quantity' ->> 'value')::NUMERIC
        * (di -> 'timing' -> 'repeat' ->> 'frequency')::NUMERIC
        * (di -> 'timing' -> 'repeat' -> 'bounds_duration' ->> 'value')::NUMERIC * bu.days
        / NULLIF((di -> 'timing' -> 'repeat' ->> 'period')::NUMERIC * pu.days, 0)
      ) AS quantity
    FROM
      jsonb_array_elements(COALESCE(mr.dosage_instruction, '[]'::JSONB)) di
      -- LEFT, not INNER, for intent only: PRN / as-needed instructions carry no `timing`
      -- block. Either join yields the same number today (SUM skips the NULL the LEFT join
      -- produces, just as INNER skipped the dropped row), but LEFT makes it explicit that
      -- an un-schedulable instruction contributes nothing rather than being filtered away.
      -- Note the result is NULL, not 0, when every instruction is PRN -- that is correct:
      -- a PRN prescription has no fixed total quantity.
      LEFT JOIN timing_units bu ON bu.code = di -> 'timing' -> 'repeat' -> 'bounds_duration' ->> 'unit'
      LEFT JOIN timing_units pu ON pu.code = di -> 'timing' -> 'repeat' ->> 'period_unit'
  ) qp ON TRUE
WHERE
  md.deleted = FALSE
  AND md.status NOT IN ('cancelled', 'entered_in_error', 'stopped', 'declined')
  [[AND st.eaushadhi_store_id = {{store_id}}]]
  -- Mandatory: no [[ ]], so Metabase requires the parameter.
  AND (COALESCE(md.when_handed_over, md.when_prepared, md.created_date) AT TIME ZONE 'Asia/Kolkata')::DATE = {{dispense_date}}
  -- Optional: the DDC counter, matched by name as in KPI 7
  [[AND l.name = {{location_name}}]]
ORDER BY
  md.patient_id,
  pk.name,
  COALESCE(md.when_handed_over, md.when_prepared, md.created_date) DESC,
  md.id DESC;
