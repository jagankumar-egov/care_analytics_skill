#!/usr/bin/env python3
"""Build dashboard-configs/radiology.json from the radiology KPI SQL files."""
import hashlib, json, pathlib, uuid

REPO = pathlib.Path(__file__).resolve().parent.parent
SQLD = REPO / "dashboard-configs/sql/radiology-kpis"
OUT  = REPO / "dashboard-configs/radiology.json"

DATABASE_ID   = 2      # placeholder: the CARE application database in the target Metabase
COLLECTION_ID = 4      # placeholder: the collection the cards live in
DASHBOARD_ID  = 101
TS            = "2026-11-26T00:00:00Z"
MB_VERSION    = "v0.63.16.8 (f4eec95)"

ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

def entity_id(seed: str) -> str:
    h = hashlib.sha256(seed.encode()).digest()
    return "".join(ALPHABET[b % 64] for b in h[:21])

def tag_id(seed: str) -> str:
    return str(uuid.UUID(hashlib.md5(seed.encode()).hexdigest()))

def param_id(seed: str) -> str:
    return hashlib.md5(seed.encode()).hexdigest()[:8]

# Dashboard-level filters. Dates are text tags cast in SQL (`{{start_date}}::DATE`),
# matching the convention already used by the DVDMS dashboard in this repo.
PARAMS = [
    ("start_date",    "Start Date",   "string/=", "string", ["past30days"]),
    ("end_date",      "End Date",     "string/=", "string", None),
    ("facility_id",   "Facility ID",  "string/=", "id",     None),
    ("min_age_hours", "Min Age (hrs)","string/=", "string", None),
]
PARAM_IDS = {slug: param_id("radiology:" + slug) for slug, *_ in PARAMS}

TABS = [
    (1, "Rollout & Usage"),
    (2, "Turnaround & Backlog"),
    (3, "Operations & Data Quality"),
]

# (file, card name, description, display, viz settings, tab, row, col, w, h)
CARDS = [
    ("kpi1-facility-readiness.sql", "Radiology Readiness & Adoption by Facility",
     "Configuration completeness and usage per facility. ROLLOUT_STAGE and GAPS are the go-live checklist.",
     "table", {"table.cell_column": "IMAGING_ORDERS_IN_PERIOD", "table.pivot_column": "ROLLOUT_STAGE"},
     1, 0, 0, 24, 9),
    ("kpi2-order-volume-daily.sql", "Imaging Order Volume (daily)",
     "Orders per facility, day and procedure, with the lifecycle status mix.",
     "bar", {"graph.dimensions": ["ORDER_DATE", "PROCEDURE_CATEGORY"],
             "graph.metrics": ["ORDERS"],
             "stackable.stack_type": "stacked",
             "graph.x_axis.title_text": "Order date",
             "graph.y_axis.title_text": "Imaging orders"},
     1, 9, 0, 12, 9),
    ("kpi3-study-funnel.sql", "Imaging Study Funnel",
     "Order -> accession -> scan -> images -> report, with the drop-off at each stage.",
     "table", {"table.cell_column": "END_TO_END_PCT"},
     1, 9, 12, 12, 9),

    ("kpi5-tat-summary.sql", "Turnaround Time Summary (p50 / p90)",
     "Median and p90 hours per leg. The *_N columns say how many studies each percentile is based on.",
     "table", {"table.cell_column": "TOTAL_TAT_P50_HRS"},
     2, 0, 0, 24, 8),
    ("kpi4-turnaround-times.sql", "Turnaround Time by Study",
     "Study-level drill-through behind the TAT summary. Filter CURRENT_STAGE to isolate a queue.",
     "table", {"table.cell_column": "TOTAL_TAT_HRS"},
     2, 8, 0, 24, 10),
    ("kpi6-pending-backlog-aging.sql", "Open Backlog & Aging",
     "Every open study with its age and blocking stage. Ignores the date filter on purpose.",
     "table", {"table.cell_column": "AGE_HOURS", "table.pivot_column": "BLOCKED_AT"},
     2, 18, 0, 24, 10),

    ("kpi11-mpps-webhook-volume.sql", "MPPS Webhook Volume (daily)",
     "Modality -> CARE integration heartbeat. A gap here freezes every study at ACTIVE.",
     "bar", {"graph.dimensions": ["EVENT_DATE"],
             "graph.metrics": ["SCAN_STARTED", "SCAN_COMPLETED", "SCAN_CANCELLED"],
             "stackable.stack_type": "stacked",
             "graph.x_axis.title_text": "Date",
             "graph.y_axis.title_text": "MPPS events"},
     3, 0, 0, 12, 7),
    ("kpi10-integration-and-data-quality.sql", "Integration & Data-Quality Exceptions",
     "Silent failures nobody will report: missing accessions, scanned-but-no-images, unmatched webhooks.",
     "table", {"table.cell_column": "COUNT"},
     3, 0, 12, 12, 7),
    ("kpi7-modality-devices.sql", "Modality & DICOM Enabler Inventory",
     "Device roster, worklist eligibility and last sync. Volume columns are ROOM volume, not per-machine.",
     "table", {"table.cell_column": "ROOM_STUDIES_IN_PERIOD", "table.pivot_column": "ON_WORKLIST"},
     3, 7, 0, 24, 9),
    ("kpi8-pacs-storage-growth.sql", "PACS Storage Growth & Archival",
     "DICOM instances accumulating per facility per month, with archival and unsynced studies.",
     "line", {"graph.dimensions": ["MONTH", "PROCEDURE_CATEGORY"],
              "graph.metrics": ["CUMULATIVE_LIVE_INSTANCES"],
              "graph.x_axis.title_text": "Month",
              "graph.y_axis.title_text": "Live DICOM instances"},
     3, 16, 0, 12, 8),
    ("kpi9-reporting-productivity.sql", "Reporting Productivity & Template Adoption",
     "Reports finalised per radiologist, order-to-report latency, and share of templated observations.",
     "table", {"table.cell_column": "REPORTS_FINALISED"},
     3, 16, 12, 12, 8),
]


def tags_for(sql: str, card_slug: str):
    """Template tags + card parameters for the dashboard filters this SQL uses."""
    tags, params = [], []
    for slug, name, ptype, _section, _default in PARAMS:
        if "{{%s}}" % slug not in sql:
            continue
        tid = tag_id(f"{card_slug}:{slug}")
        tags.append({"id": tid, "type": "text", "name": slug, "display-name": name})
        params.append({"id": tid, "type": ptype,
                       "target": ["variable", ["template-tag", slug]],
                       "name": name, "slug": slug, "isMultiSelect": False})
    return tags, params


def build():
    dashcards = []
    for i, (fname, name, desc, display, viz, tab, row, col, w, h) in enumerate(CARDS):
        sql = (SQLD / fname).read_text()
        slug = fname[:-4]
        card_id = 1000 + i
        tags, card_params = tags_for(sql, slug)
        card = {
            "id": card_id,
            "name": name,
            "description": desc,
            "entity_id": entity_id("card:" + slug),
            "type": "question",
            "display": display,
            "query_type": "native",
            "database_id": DATABASE_ID,
            "collection_id": COLLECTION_ID,
            "table_id": None,
            "source_card_id": None,
            "dashboard_id": None,
            "document_id": None,
            "card_schema": 23,
            "metabase_version": MB_VERSION,
            "dataset_query": {
                "database": DATABASE_ID,
                "lib/type": "mbql/query",
                "stages": [{
                    "lib/type": "mbql.stage/native",
                    "native": sql,
                    "template-tags": tags,
                }],
            },
            "parameters": card_params,
            "parameter_mappings": [],
            "visualization_settings": viz,
            "result_metadata": [],
            "dimension_mappings": None,
            "dimensions": None,
            "legacy_query": None,
            "archived": False,
            "archived_directly": False,
            "collection_position": None,
            "collection_preview": True,
            "cache_ttl": None,
            "cache_invalidated_at": None,
            "enable_embedding": False,
            "embedding_params": None,
            "embedding_type": None,
            "made_public_by_id": None,
            "public_uuid": None,
            "public_uuid_prefix": None,
            "initially_published_at": None,
            "moderation_reviews": [],
            "download_perms": "full",
            "can_write": True,
            "creator_id": 1,
            "created_at": TS,
            "updated_at": TS,
            "last_used_at": TS,
            "query_average_duration": None,
            "view_count": 0,
        }
        mappings = [
            {"parameter_id": PARAM_IDS[p["slug"]], "card_id": card_id,
             "target": ["variable", ["template-tag", p["slug"]]]}
            for p in card_params
        ]
        dashcards.append({
            "id": 2000 + i,
            "card_id": card_id,
            "card": card,
            "dashboard_id": DASHBOARD_ID,
            "dashboard_tab_id": tab,
            "entity_id": entity_id("dashcard:" + slug),
            "row": row, "col": col, "size_x": w, "size_y": h,
            "parameter_mappings": mappings,
            "inline_parameters": [],
            "visualization_settings": {},
            "series": [],
            "action_id": None,
            "collection_authority_level": None,
            "created_at": TS,
            "updated_at": TS,
        })

    dashboard = {
        "id": DASHBOARD_ID,
        "name": "Radiology Operations",
        "description": (
            "Go-live and steady-state metrics for the care_radiology plugin: rollout "
            "readiness, imaging volume, the order-to-report funnel, turnaround times, "
            "open backlog, PACS growth, and the integration/data-quality exceptions that "
            "fail silently. SQL sources: dashboard-configs/sql/radiology-kpis/."
        ),
        "entity_id": entity_id("dashboard:radiology-operations"),
        "collection_id": COLLECTION_ID,
        "collection_position": None,
        "collection_authority_level": None,
        "collection": None,
        "creator_id": 1,
        "created_at": TS,
        "updated_at": TS,
        "last_viewed_at": TS,
        "last-edit-info": None,
        "width": "full",
        "auto_apply_filters": False,
        "archived": False,
        "archived_directly": False,
        "can_write": True,
        "can_delete": True,
        "can_restore": False,
        "can_set_cache_policy": True,
        "cache_ttl": None,
        "enable_embedding": False,
        "embedding_params": None,
        "embedding_type": None,
        "made_public_by_id": None,
        "public_uuid": None,
        "public_uuid_prefix": None,
        "initially_published_at": None,
        "is_remote_synced": False,
        "moderation_reviews": [],
        "param_fields": {},
        "last_used_param_values": {},
        "points_of_interest": None,
        "caveats": (
            "Scan start/end come from the MPPS webhook log, which records that an event "
            "was accepted -- not that it was applied. Report timestamps use "
            "DiagnosticReport.modified_date; there is no finalised_at column. Device "
            "volume is room volume: CARE stores no study-to-device link."
        ),
        "show_in_getting_started": False,
        "position": None,
        "view_count": 0,
        "tabs": [
            {"id": tid, "dashboard_id": DASHBOARD_ID, "name": tname, "position": pos,
             "entity_id": entity_id(f"tab:{tname}"), "created_at": TS, "updated_at": TS}
            for pos, (tid, tname) in enumerate(TABS)
        ],
        "parameters": [
            {"id": PARAM_IDS[slug], "name": name, "slug": slug, "type": ptype,
             "sectionId": section, "values_query_type": "none", "isMultiSelect": False,
             **({"default": default} if default else {})}
            for slug, name, ptype, section, default in PARAMS
        ],
        "dashcards": dashcards,
    }
    OUT.write_text(json.dumps(dashboard, indent=2) + "\n")
    print(f"wrote {OUT} ({OUT.stat().st_size} bytes, {len(dashcards)} cards, {len(TABS)} tabs)")


if __name__ == "__main__":
    build()
