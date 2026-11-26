# care_radiology_radiologywebhooklogs — curated notes

- (2026-11) The generated shard says `raw_data` shape is unknown — no Pydantic
  spec declares the field. The only writer is
  `FacilityExternalViewSet.update_status`, which stores the validated
  `WebhookMppsSpec` body verbatim:
  `{"service_request_id": "<uuid>", "study_status": "IN_PROGRESS|COMPLETED|CANCELLED"}`
- (2026-11) `type` is `'MPPS'` for every row written today; it is the only
  webhook the plugin logs.
- (2026-11) **A row means "accepted", not "applied".** The log is created after
  payload validation but *before* `process_mpps_webhook()` runs, so a 404
  (service request not in that facility), a missing `TagConfig`, or a study
  already COMPLETED/CANCELLED all leave a log row with no state change. Join to
  `care_radiology_imagingstudy.status` to tell the two apart.
- (2026-11) Join on text, not `::uuid`:
  `sr.external_id::TEXT = LOWER(w.raw_data ->> 'service_request_id')`. Casting
  inside a CTE can be evaluated before the filter and abort the whole query on
  one malformed row.
- (2026-11) This table is the **only** record of when a scan started or ended —
  see `care_radiology_imagingstudy.md`.
