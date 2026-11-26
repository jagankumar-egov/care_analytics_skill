# care_radiology_dicomstudy (DicomStudy)

app: care_radiology | source: app/care_radiology/src/care_radiology/models/dicom_study.py
bases: EMRBaseModel (inherited columns: `_base_models.md`)

## Columns

- `imaging_study` foreign_key -> care_radiology_imagingstudy [col: imaging_study_id]
- `dicom_study_uid` string(500) idx
- `is_archived` boolean default=False
- `archive_reason` string
- `archived_datetime` datetime NULL
- `archived_by` foreign_key -> users_user [col: archived_by_id] NULL
- `number_of_series` integer NULL
- `number_of_instances` integer NULL

JSONB shapes (`history`, `meta`): `jsonb/care_radiology_dicomstudy.md`

## Model meta

```json
{
 "constraints": "[models.UniqueConstraint(fields=['imaging_study', 'dicom_study_uid'], condition=models.Q(is_archived=False), name='unique_imaging_study_active_study_uid')]",
 "ordering": [
  "-created_date",
  "-id"
 ]
}
```
