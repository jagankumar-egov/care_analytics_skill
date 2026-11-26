# care_radiology_observationtemplatedata (ObservationTemplateData)

app: care_radiology | source: app/care_radiology/src/care_radiology/models/observation_template.py
bases: models.Model (inherited columns: `_base_models.md`)

## Columns

- `template` foreign_key -> care_radiology_observationtemplate [col: template_id]
- `code` string(255)
- `value` string NULL
- `description` string NULL

## Model meta

```json
{
 "ordering": [
  "id"
 ]
}
```
