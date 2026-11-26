# care_radiology_radiologywebhooklogs (RadiologyWebhookLogs)

app: care_radiology | source: app/care_radiology/src/care_radiology/models/webhook_logs.py
bases: EMRBaseModel (inherited columns: `_base_models.md`)

## Columns

- `raw_data` jsonb
- `type` string(50)

JSONB shapes (`history`, `meta`, `raw_data`): `jsonb/care_radiology_radiologywebhooklogs.md`

## Model meta

```json
{
 "ordering": [
  "-created_date",
  "-id"
 ]
}
```
