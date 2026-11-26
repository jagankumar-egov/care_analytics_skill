# Radiology KPIs (`care_radiology`)

Metabase cards for the CARE radiology plugin, aimed at a deployment that is about
to go live or has just gone live. The dashboard that wires these together is
`dashboard-configs/radiology.json` ("Radiology Operations", 3 tabs).

## Cards

| # | File | Card | Answers |
|---|------|------|---------|
| 1 | `kpi1-facility-readiness.sql` | Radiology Readiness & Adoption by Facility | Is radiology configured here, and is anyone using it? |
| 2 | `kpi2-order-volume-daily.sql` | Imaging Order Volume (daily) | Is usage growing, and in which procedures? |
| 3 | `kpi3-study-funnel.sql` | Imaging Study Funnel | Where do orders fall out between request and report? |
| 4 | `kpi4-turnaround-times.sql` | Turnaround Time by Study | Which individual studies are slow, and at which leg? |
| 5 | `kpi5-tat-summary.sql` | Turnaround Time Summary (p50 / p90) | What is the SLA picture per facility and procedure? |
| 6 | `kpi6-pending-backlog-aging.sql` | Open Backlog & Aging | What is open right now, how old, blocked on what? |
| 7 | `kpi7-modality-devices.sql` | Modality & DICOM Enabler Inventory | Which machines are registered, assigned and on the worklist? |
| 8 | `kpi8-pacs-storage-growth.sql` | PACS Storage Growth & Archival | How fast is imaging accumulating; what has been archived? |
| 9 | `kpi9-reporting-productivity.sql` | Reporting Productivity & Template Adoption | Who is reporting, how fast, how much from templates? |
| 10 | `kpi10-integration-and-data-quality.sql` | Integration & Data-Quality Exceptions | What is failing silently? |
| 11 | `kpi11-mpps-webhook-volume.sql` | MPPS Webhook Volume (daily) | Are the modalities still talking to CARE? |

## Parameters

Dashboard-level filters, wired to every card that uses them:

| Slug | Type | Notes |
|------|------|-------|
| `start_date` | text | IST date, inclusive. Cast in SQL as `{{start_date}}::DATE`. |
| `end_date` | text | IST date, inclusive; the SQL adds a day for an exclusive upper bound. |
| `facility_id` | text | Facility `external_id` (UUID). Optional on every card. |
| `min_age_hours` | text | KPI 6 only. Optional. |

All windows are computed in `Asia/Kolkata`, the same convention the DVDMS cards
in this repo use.

## Tables these cards read

Plugin tables (app label `care_radiology`, Django default table names). Full
shards now live in `skills/care-analytics/schema/tables/`:

| Table | Base | Notes |
|-------|------|-------|
| `care_radiology_imagingstudy` | `BaseModel` | One row per radiology order. **No** `meta`/`history`/`created_by_id`. `status` ∈ `ACTIVE`, `IN_PROGRESS`, `COMPLETED`, `CANCELLED`. `service_request_id` is nullable. |
| `care_radiology_dicomstudy` | `EMRBaseModel` | One row per DICOM study UID. `number_of_series` / `number_of_instances` are NULL until CARE syncs metadata from DCM4CHEE. |
| `care_radiology_radiologywebhooklogs` | `EMRBaseModel` | `type = 'MPPS'`, `raw_data = {"service_request_id": "<uuid>", "study_status": "IN_PROGRESS|COMPLETED|CANCELLED"}`. |
| `care_radiology_observationtemplate` | `EMRBaseModel` | Per-facility report templates, keyed to an `ObservationDefinition`. |
| `care_radiology_accessionsequence` | plain `Model` | Per (facility, category, year) counter. No `deleted`/`created_date`. |

Core CARE tables: `emr_servicerequest`, `emr_diagnosticreport`, `emr_observation`,
`emr_activitydefinition`, `emr_resourcecategory`, `emr_encounter`, `emr_patient`,
`emr_device`, `emr_facilitylocation`, `emr_tagconfig`, `emr_organization`,
`facility_facility`, `users_user`.

## How a study is identified as radiology

The plugin's `post_save` signal on `ServiceRequest` creates an `ImagingStudy`
when `service_request.category == CARE_RADIOLOGY_RADIOLOGY_CATEGORY`
(**default `"imaging"`, configurable per deployment**). The matching
`ActivityDefinition.classification` is also `'imaging'`. If a deployment
overrides that setting, change the literal in KPI 1 — every other card drives
off the `care_radiology_imagingstudy` rows themselves and needs no change.

## Measurement caveats — read before quoting these numbers

1. **There are no per-status timestamps on an imaging study.** `ImagingStudy`
   keeps one `status` column. Scan start and scan end are reconstructed from
   `care_radiology_radiologywebhooklogs`, which is the only durable record of
   those transitions.
2. **A logged MPPS event is "accepted", not "applied".** The log row is written
   *before* `process_mpps_webhook()` runs, so a 404 (wrong facility, unknown
   service request) or a tag-config failure still leaves a log row. KPI 11
   reports `LOGGED` and `APPLIED` side by side for exactly this reason.
3. **`IMAGES_AT` is upload time, not acquisition time.** It is
   `care_radiology_dicomstudy.created_date` — when the file landed in CARE. The
   DICOM acquisition timestamp lives in the PACS and is never copied into a CARE
   table.
4. **Report finalisation time is approximate.** `emr_diagnosticreport` has no
   `finalised_at`; the cards use `modified_date` of the first report that reached
   `status = 'final'`, so a report edited after sign-off reports its last edit.
   Reporter attribution uses `updated_by_id` for the same reason.
5. **Device volume is room volume.** CARE stores no link from an imaging study to
   the device that acquired it — the worklist matches orders to devices by room
   (`ActivityDefinition.locations` ∩ `Device.current_location`). Per-machine
   throughput needs the Station Name from the PACS.
6. **KPI 6 deliberately ignores the date filter.** A backlog is about what is open
   now; the oldest items are the ones that matter.
7. **Storage is counted in DICOM instances, not bytes.** CARE holds no size field.
8. Every card filters `deleted = FALSE` and exposes `external_id`, never the
   internal integer `id`.

## Verification status

The catalog in `skills/care-analytics/schema/` now **includes the radiology
tables** — regenerated from the local `care` checkout (`ee23dedf8`, branch
`dev`) with the plugin source from the local `care_radiology` checkout
(`77ffad6`, branch `optimise`). That run was purely additive: six new table
shards, three new JSONB shards, an `ImagingStudyStatus` entry in `_enums.md`,
and zero changes to any existing core table shard.

The plugin's `origin/main` carries the same models and migrations (through
`0025`), and the three commits `optimise` is ahead by touch only docker-compose,
server timing and DICOM-read code — so this catalog matches the `@main` version
`plug_config.py` deploys.

Every qualified column reference in these 11 files (580 of them) was checked
against that catalog and resolves. The SQL also parses as PostgreSQL. It has
**not** been executed against a live database, so row counts, index behaviour
and query cost are unverified.

`plugs.json` at the repo root now pins the plugin, so `scripts/build.sh` and CI
pick it up without passing `ADDITIONAL_PLUGS`:

```bash
scripts/build.sh                              # uses plugs.json
CARE_ROOT=~/Office/Work/repo/Care/care scripts/build.sh   # against a local care checkout
```

Note the plugin lives at **`care-ecosystem/care_radiology`**, not `ohcnetwork` —
that is what `plug_config.py` installs.

Curated semantics the generator cannot derive (the MPPS payload shape, the
"accepted ≠ applied" rule, the missing per-status timestamps) are recorded in
`skills/care-analytics/notes/care_radiology_imagingstudy.md` and
`notes/care_radiology_radiologywebhooklogs.md`, which regeneration never
overwrites.

## Loading the dashboard

`dashboard-configs/radiology.json` is in the same shape as `dvdms.json` — a
Metabase dashboard document with its cards inlined. Three values are placeholders
for the target instance and must be set before import:

- `database_id` / `dataset_query.database` — `2` (the CARE application database)
- `collection_id` — `4`
- `id`, `card.id`, `dashcard.id`, `tabs[].id` — placeholder integers

Suggested charts are set per card (`bar` for KPI 2 and 11, `line` for KPI 8,
`table` elsewhere); `result_metadata` is left empty for Metabase to recompute on
first run.
