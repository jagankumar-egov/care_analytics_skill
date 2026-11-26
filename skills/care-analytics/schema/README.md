# AI Analytics Schema

Generated from the Care source tree. These files are static catalogs for AI-assisted analytics, SQL generation, and warehouse planning.

## Files

- `physical-tables.json` (at the output root, not in this directory): full machine-readable catalog (large — AI agents should NOT read this directly).
- `_index.md`: one line per table with FK edges. **Agents start here.**
- `_conventions.md`: SQL rules (soft delete, id vs external_id, JSONB access).
- `_base_models.md`: inherited base-class columns, defined once.
- `_enums.md`: every enum/choices class with stored values, grouped by source file.
- `tables/<db_table>.md`: declared columns and relations for one table.
- `jsonb/<db_table>.md`: JSONB column shapes for one table.

## Current Coverage

- Physical tables: 95
- Pydantic/spec classes read for JSONB inference: 450
- JSONB columns: 285
- JSONB columns with Pydantic spec matches: 177
- JSONB columns with JSON schema validators: 0
- JSONB columns with only default-shape hints: 108

## Analytics Notes

- Django `JSONField` is treated as PostgreSQL JSONB for analytics purposes.
- `BaseModel` descendants use `deleted` for soft deletion; analytics queries should normally filter `deleted = false`.
- `external_id` is the public UUID. The implicit `id` column is the internal integer primary key unless the model declares otherwise.
- `EMRBaseModel` descendants inherit `history`, `meta`, `created_by_id`, and `updated_by_id`.
- Only physical tables are emitted. Abstract bases and standalone spec classes are used internally and are not separate schema outputs.
- JSONB columns include `jsonb_schema`; Pydantic spec matches, JSON schema validators, default-shape hints, and referenced definitions are embedded there.
- Pydantic specs are API/resource schemas. A same-name spec field is strong evidence for JSONB shape, but custom serializers/deserializers can still change behavior.
- Fields listed under `jsonb_schema.meta_stored_fields` are stored in `meta` only for resources that set `__store_metadata__ = True`.
- Plugin models under `app/` are included as source inventory; this does not prove a plug is enabled in a runtime deployment.

## Regenerate

From the care repo root: `pipenv run python scripts/generate_ai_analytics_schema.py`
(set `AI_SCHEMA_OUTPUT_DIR` to redirect output). From the care_analytics_skill
repo: `scripts/build.sh` (supports `ADDITIONAL_PLUGS`).
