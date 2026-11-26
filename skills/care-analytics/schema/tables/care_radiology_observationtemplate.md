# care_radiology_observationtemplate (ObservationTemplate)

app: care_radiology | source: app/care_radiology/src/care_radiology/models/observation_template.py
bases: EMRBaseModel (inherited columns: `_base_models.md`)

## Columns

- `facility` foreign_key -> facility_facility [col: facility_id]
- `title` string(255)
- `description` string NULL
- `observation_definition` foreign_key -> emr_observationdefinition [col: observation_definition_id]
- `activity_definition` foreign_key -> emr_activitydefinition [col: activity_definition_id] NULL

JSONB shapes (`history`, `meta`): `jsonb/care_radiology_observationtemplate.md`

## Model meta

```json
{
 "constraints": "[models.UniqueConstraint(fields=['facility', 'title'], name='unique_facility_observation_template_title')]",
 "indexes": "[models.Index(fields=['observation_definition', 'activity_definition'])]",
 "ordering": [
  "-created_date",
  "-id"
 ]
}
```
