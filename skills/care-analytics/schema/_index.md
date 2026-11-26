# CARE Physical Table Index

One line per table. Details: `tables/<db_table>.md`. JSONB shapes: `jsonb/<db_table>.md`. Inherited columns: `_base_models.md`. Enum values: `_enums.md`. SQL rules: `_conventions.md`.

## care_radiology

- `care_radiology_accessionsequence` (AccessionSequence) 4 declared cols | FK: emr_resourcecategory, facility_facility
- `care_radiology_dicomstudy` (DicomStudy) 8 declared cols, 2 jsonb | FK: care_radiology_imagingstudy, users_user
- `care_radiology_imagingstudy` (ImagingStudy) 5 declared cols | FK: emr_encounter, emr_patient, emr_servicerequest
- `care_radiology_observationtemplate` (ObservationTemplate) 5 declared cols, 2 jsonb | FK: emr_activitydefinition, emr_observationdefinition, facility_facility
- `care_radiology_observationtemplatedata` (ObservationTemplateData) 4 declared cols | FK: care_radiology_observationtemplate
- `care_radiology_radiologywebhooklogs` (RadiologyWebhookLogs) 2 declared cols, 3 jsonb

## emr

- `emr_account` (Account) 18 declared cols, 6 jsonb | FK: emr_encounter, emr_patient, facility_facility
- `emr_activitydefinition` (ActivityDefinition) 21 declared cols, 5 jsonb | FK: emr_healthcareservice, emr_resourcecategory, facility_facility
- `emr_allergyintolerance` (AllergyIntolerance) 13 declared cols, 4 jsonb | FK: emr_encounter, emr_patient
- `emr_availability` (Availability) 8 declared cols, 3 jsonb | FK: emr_schedule
- `emr_availabilityexception` (AvailabilityException) 7 declared cols, 2 jsonb | FK: emr_schedulableresource
- `emr_chargeitem` (ChargeItem) 22 declared cols, 7 jsonb | FK: emr_account, emr_chargeitemdefinition, emr_encounter, emr_invoice, emr_patient, facility_facility, users_user
- `emr_chargeitemdefinition` (ChargeItemDefinition) 13 declared cols, 4 jsonb | FK: emr_resourcecategory, facility_facility
- `emr_condition` (Condition) 12 declared cols, 6 jsonb | FK: emr_encounter, emr_patient
- `emr_consent` (Consent) 8 declared cols, 4 jsonb | FK: emr_encounter
- `emr_deliveryorder` (DeliveryOrder) 10 declared cols, 3 jsonb | FK: emr_facilitylocation, emr_invoice, emr_organization, emr_patient
- `emr_device` (Device) 20 declared cols, 4 jsonb | FK: emr_encounter, emr_facilitylocation, emr_facilityorganization, facility_facility
- `emr_deviceencounterhistory` (DeviceEncounterHistory) 4 declared cols, 2 jsonb | FK: emr_device, emr_encounter
- `emr_devicelocationhistory` (DeviceLocationHistory) 4 declared cols, 2 jsonb | FK: emr_device, emr_facilitylocation
- `emr_deviceservicehistory` (DeviceServiceHistory) 4 declared cols, 3 jsonb | FK: emr_device
- `emr_diagnosticreport` (DiagnosticReport) 9 declared cols, 4 jsonb | FK: emr_encounter, emr_patient, emr_servicerequest, facility_facility
- `emr_dispenseorder` (DispenseOrder) 8 declared cols, 2 jsonb | FK: emr_facilitylocation, emr_patient, facility_facility
- `emr_encounter` (Encounter) 17 declared cols, 7 jsonb | FK: emr_facilitylocation, emr_patient, emr_tokenbooking, facility_facility
- `emr_encounterorganization` (EncounterOrganization) 2 declared cols, 2 jsonb | FK: emr_encounter, emr_facilityorganization
- `emr_facilitylocation` (FacilityLocation) 21 declared cols, 5 jsonb | FK: emr_encounter, emr_facilitylocation, facility_facility
- `emr_facilitylocationencounter` (FacilityLocationEncounter) 5 declared cols, 2 jsonb | FK: emr_encounter, emr_facilitylocation
- `emr_facilitylocationorganization` (FacilityLocationOrganization) 2 declared cols, 2 jsonb | FK: emr_facilitylocation, emr_facilityorganization
- `emr_facilitymonetoryconfig` (FacilityMonetoryConfig) 5 declared cols, 5 jsonb | FK: facility_facility
- `emr_facilityorganization` (FacilityOrganization) 1 declared cols, 4 jsonb | FK: facility_facility
- `emr_facilityorganizationuser` (FacilityOrganizationUser) 3 declared cols, 2 jsonb | FK: emr_facilityorganization, security_rolemodel, users_user
- `emr_fileupload` (FileUpload) 10 declared cols, 2 jsonb | FK: users_user
- `emr_formsubmission` (FormSubmission) 5 declared cols, 3 jsonb | FK: emr_encounter, emr_patient, emr_questionnaire
- `emr_healthcareservice` (HealthcareService) 8 declared cols, 4 jsonb | FK: emr_facilityorganization, facility_facility
- `emr_inventoryitem` (InventoryItem) 4 declared cols, 2 jsonb | FK: emr_facilitylocation, emr_product
- `emr_invoice` (Invoice) 18 declared cols, 5 jsonb | FK: emr_account, emr_patient, facility_facility
- `emr_medicationadministration` (MedicationAdministration) 15 declared cols, 6 jsonb | FK: emr_encounter, emr_medicationrequest, emr_patient, emr_productknowledge
- `emr_medicationdispense` (MedicationDispense) 17 declared cols, 4 jsonb | FK: emr_chargeitem, emr_dispenseorder, emr_encounter, emr_facilitylocation, emr_inventoryitem, emr_medicationrequest, emr_patient
- `emr_medicationrequest` (MedicationRequest) 17 declared cols, 5 jsonb | FK: emr_encounter, emr_medicationrequestprescription, emr_patient, emr_productknowledge, users_user
- `emr_medicationrequestprescription` (MedicationRequestPrescription) 9 declared cols, 2 jsonb | FK: emr_encounter, emr_patient, users_user
- `emr_medicationstatement` (MedicationStatement) 9 declared cols, 4 jsonb | FK: emr_encounter, emr_patient
- `emr_metaartifact` (MetaArtifact) 6 declared cols, 3 jsonb
- `emr_notemessage` (NoteMessage) 3 declared cols, 3 jsonb | FK: emr_notethread
- `emr_notethread` (NoteThread) 3 declared cols, 2 jsonb | FK: emr_encounter, emr_patient
- `emr_observation` (Observation) 25 declared cols, 12 jsonb | FK: emr_diagnosticreport, emr_encounter, emr_observationdefinition, emr_patient, emr_questionnaireresponse, users_user
- `emr_observationdefinition` (ObservationDefinition) 15 declared cols, 8 jsonb | FK: facility_facility
- `emr_organization` (Organization) 1 declared cols, 4 jsonb
- `emr_organizationuser` (OrganizationUser) 3 declared cols, 2 jsonb | FK: emr_organization, security_rolemodel, users_user
- `emr_patient` (Patient) 19 declared cols, 6 jsonb | FK: emr_organization
- `emr_patientidentifier` (PatientIdentifier) 4 declared cols, 2 jsonb | FK: emr_patient, emr_patientidentifierconfig, facility_facility
- `emr_patientidentifierconfig` (PatientIdentifierConfig) 3 declared cols, 3 jsonb | FK: facility_facility
- `emr_patientorganization` (PatientOrganization) 2 declared cols, 2 jsonb | FK: emr_organization, emr_patient
- `emr_patientuser` (PatientUser) 3 declared cols, 2 jsonb | FK: emr_patient, security_rolemodel, users_user
- `emr_paymentreconciliation` (PaymentReconciliation) 20 declared cols, 3 jsonb | FK: emr_account, emr_facilitylocation, emr_invoice, facility_facility
- `emr_product` (Product) 10 declared cols, 4 jsonb | FK: emr_chargeitemdefinition, emr_productknowledge, facility_facility
- `emr_productknowledge` (ProductKnowledge) 13 declared cols, 7 jsonb | FK: emr_resourcecategory, facility_facility
- `emr_questionnaire` (Questionnaire) 10 declared cols, 4 jsonb
- `emr_questionnairefacilityorganization` (QuestionnaireFacilityOrganization) 2 declared cols, 2 jsonb | FK: emr_facilityorganization, emr_questionnaire
- `emr_questionnaireorganization` (QuestionnaireOrganization) 2 declared cols, 2 jsonb | FK: emr_organization, emr_questionnaire
- `emr_questionnaireresponse` (QuestionnaireResponse) 9 declared cols, 4 jsonb | FK: emr_encounter, emr_formsubmission, emr_patient, emr_questionnaire
- `emr_questionnaireresponsetemplate` (QuestionnaireResponseTemplate) 8 declared cols, 3 jsonb | FK: emr_questionnaire, facility_facility
- `emr_reportupload` (ReportUpload) 10 declared cols, 2 jsonb | FK: emr_template, users_user
- `emr_requestorder` (RequestOrder) 11 declared cols, 2 jsonb | FK: emr_facilitylocation, emr_organization
- `emr_resourcecategory` (ResourceCategory) 15 declared cols, 5 jsonb | FK: emr_resourcecategory, facility_facility
- `emr_resourcerequest` (ResourceRequest) 15 declared cols, 3 jsonb | FK: emr_patient, facility_facility, users_user
- `emr_resourcerequestcomment` (ResourceRequestComment) 2 declared cols, 2 jsonb | FK: emr_resourcerequest
- `emr_schedulableresource` (SchedulableResource) 5 declared cols, 2 jsonb | FK: emr_facilitylocation, emr_healthcareservice, facility_facility, users_user
- `emr_schedule` (Schedule) 8 declared cols, 2 jsonb | FK: emr_chargeitemdefinition, emr_schedulableresource
- `emr_servicerequest` (ServiceRequest) 19 declared cols, 4 jsonb | FK: emr_activitydefinition, emr_encounter, emr_healthcareservice, emr_patient, facility_facility, users_user
- `emr_specimen` (Specimen) 13 declared cols, 6 jsonb | FK: emr_encounter, emr_patient, emr_servicerequest, emr_specimendefinition, facility_facility
- `emr_specimendefinition` (SpecimenDefinition) 11 declared cols, 6 jsonb | FK: facility_facility
- `emr_supplydelivery` (SupplyDelivery) 12 declared cols, 3 jsonb | FK: emr_deliveryorder, emr_inventoryitem, emr_product, emr_supplyrequest
- `emr_supplyrequest` (SupplyRequest) 5 declared cols, 2 jsonb | FK: emr_productknowledge, emr_requestorder
- `emr_tagconfig` (TagConfig) 16 declared cols, 4 jsonb | FK: emr_facilityorganization, emr_organization, emr_tagconfig, facility_facility
- `emr_template` (Template) 10 declared cols, 3 jsonb | FK: facility_facility
- `emr_token` (Token) 10 declared cols, 2 jsonb | FK: emr_patient, emr_tokenbooking, emr_tokencategory, emr_tokenqueue, emr_tokensubqueue, facility_facility
- `emr_tokenbooking` (TokenBooking) 10 declared cols, 2 jsonb | FK: emr_chargeitem, emr_encounter, emr_patient, emr_token, emr_tokenslot, users_user
- `emr_tokencategory` (TokenCategory) 6 declared cols, 3 jsonb | FK: facility_facility
- `emr_tokenqueue` (TokenQueue) 6 declared cols, 2 jsonb | FK: emr_schedulableresource, facility_facility
- `emr_tokenslot` (TokenSlot) 5 declared cols, 2 jsonb | FK: emr_availability, emr_schedulableresource
- `emr_tokensubqueue` (TokenSubQueue) 5 declared cols, 2 jsonb | FK: emr_schedulableresource, emr_token, facility_facility
- `emr_userresourcefavorites` (UserResourceFavorites) 5 declared cols, 2 jsonb | FK: facility_facility, users_user
- `emr_uservaluesetpreference` (UserValueSetPreference) 3 declared cols, 3 jsonb | FK: emr_valueset, users_user
- `emr_valueset` (ValueSet) 6 declared cols, 3 jsonb

## facility

- `facility_facility` (Facility) 21 declared cols, 2 jsonb | FK: emr_facilityorganization, emr_organization, users_user
- `facility_facilityflag` (FacilityFlag) 1 declared cols | FK: facility_facility
- `facility_mobileotp` (MobileOTP) 4 declared cols

## security

- `security_permissionmodel` (PermissionModel) 5 declared cols
- `security_roleassociation` (RoleAssociation) 5 declared cols | FK: security_rolemodel, users_user
- `security_rolemodel` (RoleModel) 6 declared cols
- `security_rolepermission` (RolePermission) 3 declared cols | FK: security_permissionmodel, security_rolemodel

## users

- `users_plugconfig` (PlugConfig) 2 declared cols, 1 jsonb
- `users_skill` (Skill) 2 declared cols
- `users_user` (User) 30 declared cols, 3 jsonb | FK: emr_organization, facility_facility, users_skill, users_user
- `users_userflag` (UserFlag) 1 declared cols | FK: users_user
- `users_userskill` (UserSkill) 2 declared cols | FK: users_skill, users_user
