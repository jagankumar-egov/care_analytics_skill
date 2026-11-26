# care_radiology_accessionsequence (AccessionSequence)

app: care_radiology | source: app/care_radiology/src/care_radiology/models/accession_sequence.py
bases: models.Model (inherited columns: `_base_models.md`)

## Columns

- `facility` foreign_key -> facility_facility [col: facility_id]
- `resourcecategory` foreign_key -> emr_resourcecategory [col: resourcecategory_id]
- `year` integer
- `last_value` integer default=0

## Model meta

```json
{
 "constraints": "[models.UniqueConstraint(fields=['facility', 'resourcecategory', 'year'], name='uniq_facility_resource_category_year')]",
 "ordering": [
  "id"
 ]
}
```
