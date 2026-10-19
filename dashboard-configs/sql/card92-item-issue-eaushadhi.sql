WITH
  p AS (
    SELECT
      CASE LOWER(TRIM({{issue_date}}))
        WHEN 'today' THEN (NOW() AT TIME ZONE 'Asia/Kolkata')::date
        WHEN 'yesterday' THEN (NOW() AT TIME ZONE 'Asia/Kolkata')::date - 1
        ELSE {{issue_date}}::date
      END AS d
  )
SELECT
  loc.name AS store_name,
  dvdms.eaushadhi_issue_no AS hstnum_issue_no,
  dvdms.drug_id AS hstnum_item_id,
  dvdms.brand_id AS hstnum_itembrand_id,
  COALESCE(dvdms.batch, p2.batch ->> 'lot_number') AS hststr_batch_sl_no,
  md.quantity AS hstnum_issue_qty,
  COALESCE(
    dvdms.expiry_date,
    (p2.expiration_date AT TIME ZONE 'Asia/Kolkata')::date
  ) AS hstdt_expiry_date,
  pat.external_id AS hrgnum_puk
FROM
  p,
  emr_medicationdispense md
  JOIN emr_facilitylocation loc ON loc.id = md.location_id
  JOIN facility_facility f ON f.id = loc.facility_id
  JOIN emr_inventoryitem ii ON ii.id = md.item_id
  JOIN emr_product p2 ON p2.id = ii.product_id
  JOIN emr_patient pat ON pat.id = md.patient_id
  LEFT JOIN LATERAL (
    SELECT
      ir.eaushadhi_issue_no,
      d.drug_id,
      d.brand_id,
      iir.batch,
      iir.expiry_date
    FROM
      emr_supplydelivery sd
      JOIN emr_inventoryitem sii ON sii.id = sd.supplied_inventory_item_id
      JOIN care_dvdms_dvdmsrecorddelivery rd ON rd.delivery_order_id = sd.order_id
      AND rd.deleted = FALSE
      AND rd.status <> 'cancelled'
      JOIN care_dvdms_dvdmsinwardrecord ir ON ir.id = rd.inward_record_id
      LEFT JOIN care_dvdms_dvdmsrecorditemdelivery rid ON rid.supply_delivery_id = sd.id
      AND rid.record_delivery_id = rd.id
      AND rid.deleted = FALSE
      LEFT JOIN care_dvdms_dvdmsinwarditemrecord iir ON iir.id = rid.inward_record_item_id
      LEFT JOIN care_dvdms_dvdmsrecorditemorder rio ON rio.id = iir.record_order_item_id
      LEFT JOIN care_dvdms_dvdmsdrug d ON d.id = rio.drug_id
    WHERE
      sii.product_id = ii.product_id
      AND sd.status = 'completed'
      AND sd.deleted = FALSE
      AND sd.created_date <= COALESCE(
        md.when_handed_over,
        md.when_prepared,
        md.created_date
      )
    ORDER BY
      sd.created_date DESC
    LIMIT
      1
  ) dvdms ON TRUE
WHERE
  md.deleted = FALSE
  AND md.status = 'completed'
  AND f.external_id = {{facility_id}}::UUID
  AND (
    COALESCE(
      md.when_handed_over,
      md.when_prepared,
      md.created_date
    ) AT TIME ZONE 'Asia/Kolkata'
  )::date = p.d
ORDER BY
  COALESCE(
    md.when_handed_over,
    md.when_prepared,
    md.created_date
  ),
  "HSTNUM_ISSUE_NO";
