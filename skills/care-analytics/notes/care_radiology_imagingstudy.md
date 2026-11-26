# care_radiology_imagingstudy — curated notes

- (2026-11) One row per radiology order. Created by the `post_save` signal on
  `ServiceRequest` when `category == CARE_RADIOLOGY_RADIOLOGY_CATEGORY`
  (plugin setting, **default `"imaging"`**). The matching
  `emr_activitydefinition.classification` is `'imaging'` too.
- (2026-11) Inherits `BaseModel`, **not** `EMRBaseModel` — there is no `meta`,
  `history`, `created_by_id` or `updated_by_id` on this table. Attribute an
  order through `emr_servicerequest.requester_id` instead.
- (2026-11) **No per-status timestamps.** `status`
  (ACTIVE / IN_PROGRESS / COMPLETED / CANCELLED) is a single column with no
  transition history. Scan start and scan end must be reconstructed from
  `care_radiology_radiologywebhooklogs`.
- (2026-11) `service_request_id` is a nullable OneToOne. Rows with it NULL are
  orphans — invisible to the worklist and to every report join.
- (2026-11) `accession_number` is set asynchronously by the
  `assign_accession_number` Celery task, not in the signal. A NULL on a
  non-cancelled study means the task never ran: that study can never be matched
  to an incoming DICOM file.
- (2026-11) Facility is not on this table. Use
  `COALESCE(service_request.facility_id, encounter.facility_id)`.
- (2026-11) Radiology reports are core rows: `emr_diagnosticreport` joined on
  `service_request_id`, with `emr_observation.diagnostic_report_id` for the
  findings. `emr_diagnosticreport` has no `finalised_at` — use `modified_date`
  of the first row that reached `status = 'final'`, and `updated_by_id` for the
  reporting radiologist.
- (2026-11) CARE stores **no link from a study to the device that acquired it**.
  The worklist matches orders to devices by room
  (`emr_activitydefinition.locations` ∩ `emr_device.current_location_id`), so
  device-level volume is really room volume.
- (2026-11) Ready-made cards over these tables:
  `dashboard-configs/sql/radiology-kpis/`.
