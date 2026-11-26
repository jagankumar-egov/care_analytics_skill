# care_radiology_imagingstudy (ImagingStudy)

app: care_radiology | source: app/care_radiology/src/care_radiology/models/imaging_study.py
bases: BaseModel (inherited columns: `_base_models.md`)

## Columns

- `service_request` one_to_one -> emr_servicerequest [col: service_request_id] NULL
- `encounter` foreign_key -> emr_encounter [col: encounter_id]
- `patient` foreign_key -> emr_patient [col: patient_id]
- `accession_number` string(100) NULL idx
- `status` string(20) choices=[ACTIVE|IN_PROGRESS|COMPLETED|CANCELLED] default=ImagingStudyStatus.ACTIVE

## Model meta

```json
{
 "ordering": [
  "-created_date",
  "-id"
 ]
}
```
