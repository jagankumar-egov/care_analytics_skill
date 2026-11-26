# Enum / Choices Catalog

Every enum-ish class and choices constant found in the scanned source, grouped by file. Values listed are the **stored database values**. Columns whose shard shows a bare `choices=Symbol` (unresolved), and spec-layer enums for columns with no `choices=` at all (common on EMR status/category columns), can be looked up here by name — prefer the definition whose file matches the column's `source:` or resource module.

## app/care_radiology/src/care_radiology/api/specs/modality.py

- `ModalityCodeChoices`: AR, BMD, BDUS, EPS, CR, CT, DX, ECG, ES, XC, GM, HD, IO, IVOCT, IVUS, KER, LEN, MR, MG, NM, OAM, OCT, OPM, OP, OPR, OPT, OPV, OSS, PX, PT, RF, RG, SM, SRF, US, VA, XA

## app/care_radiology/src/care_radiology/models/imaging_study.py

- `ImagingStudyStatus`: ACTIVE, IN_PROGRESS, COMPLETED, CANCELLED

## care/emr/resources/account/spec.py

- `AccountStatusOptions`: active, inactive, entered_in_error, on_hold
- `AccountBillingStatusOptions`: open, carecomplete_notbilled, billing, closed_baddebt, closed_voided, closed_completed, closed_combined

## care/emr/resources/activity_definition/spec.py

- `ActivityDefinitionStatusOptions`: draft, active, retired, unknown
- `ActivityDefinitionKindOptions`: service_request
- `ActivityDefinitionCategoryOptions`: laboratory, imaging, counselling, surgical_procedure, education

## care/emr/resources/allergy_intolerance/spec.py

- `ClinicalStatusChoices`: active, inactive, resolved
- `VerificationStatusChoices`: unconfirmed, presumed, confirmed, refuted, entered_in_error
- `CategoryChoices`: food, medication, environment, biologic
- `CriticalityChoices`: low, high, unable_to_assess
- `AllergyIntoleranceTypeOptions`: allergy, intolerance

## care/emr/resources/charge_item/spec.py

- `ChargeItemStatusOptions`: billable, not_billable, aborted, billed, paid, entered_in_error
- `ChargeItemResourceOptions`: service_request, medication_dispense, appointment, bed_association

## care/emr/resources/charge_item_definition/spec.py

- `ChargeItemDefinitionStatusOptions`: draft, active, retired

## care/emr/resources/common/contact_point.py

- `ContactPointSystemChoices`: phone, fax, email, pager, url, sms, other
- `ContactPointUseChoices`: home, work, temp, old, mobile

## care/emr/resources/common/mail_type.py

- `MailTypeChoices`: create_password, reset_password

## care/emr/resources/common/monetary_component.py

- `MonetaryComponentType`: base, surcharge, discount, tax, informational
- `DiscountApplicability`: total_asc, total_desc

## care/emr/resources/condition/spec.py

- `ClinicalStatusChoices`: active, recurrence, relapse, inactive, remission, resolved, unknown
- `VerificationStatusChoices`: unconfirmed, provisional, differential, confirmed, refuted, entered_in_error
- `CategoryChoices`: problem_list_item, encounter_diagnosis, chronic_condition
- `SeverityChoices`: mild, moderate, severe

## care/emr/resources/consent/spec.py

- `ConsentStatusChoices`: draft, active, inactive, not_done, entered_in_error
- `VerificationType`: family, validation
- `DecisionType`: deny, permit
- `CategoryChoice`: research, patient_privacy, treatment, dnr, comfort_care, acd, adr

## care/emr/resources/device/spec.py

- `DeviceStatusChoices`: active, inactive, entered_in_error
- `DeviceAvailabilityStatusChoices`: lost, damaged, destroyed, available

## care/emr/resources/diagnostic_report/spec.py

- `DiagnosticReportStatusChoices`: registered, partial, preliminary, final

## care/emr/resources/encounter/constants.py

- `StatusChoices`: planned, in_progress, on_hold, discharged, completed, cancelled, discontinued, entered_in_error, unknown
- `ClassChoices`: imp, amb, obsenc, emer, vr, hh
- `AdmitSourcesChoices`: hosp_trans, emd, outp, born, gp, mp, nursing, psych, rehab, other
- `DischargeDispositionChoices`: home, alt_home, other_hcf, hosp, long, aadvice, exp, psy, rehab, snf, oth
- `DietPreferenceChoices`: vegetarian, dairy_free, nut_free, gluten_free, vegan, halal, kosher, none
- `EncounterPriorityChoices`: ASAP, callback_results, callback_for_scheduling, elective, emergency, preop, as_needed, routine, rush_reporting, stat, timing_critical, use_as_directed, urgent

## care/emr/resources/facility_organization/spec.py

- `FacilityOrganizationTypeChoices`: dept, team, root, role, other

## care/emr/resources/favorites/spec.py

- `FavoriteResourceChoices`: activity_definition, charge_item_definition, product_knowledge, observation_definition, questionnaire, facility_organization

## care/emr/resources/file_upload/spec.py

- `FileTypeChoices`: patient, encounter, consent, diagnostic_report, service_request
- `FileCategoryChoices`: audio, xray, identity_proof, unspecified, discharge_summary, consent_attachment

## care/emr/resources/form_submission/spec.py

- `FormSubmissionStatusChoices`: draft, submitted, entered_in_error

## care/emr/resources/healthcare_service/spec.py

- `HealthcareServiceInternalType`: pharmacy, lab, scheduling, store

## care/emr/resources/inventory/inventory_item/spec.py

- `InventoryItemStatusOptions`: active, inactive, entered_in_error

## care/emr/resources/inventory/product/spec.py

- `ProductStatusOptions`: active, inactive, entered_in_error

## care/emr/resources/inventory/product_knowledge/spec.py

- `ProductTypeOptions`: medication, nutritional_product, consumable
- `ProductNameTypes`: trade_name, alias, original_name, preferred
- `ProductKnowledgeStatusOptions`: draft, active, retired, unknown
- `DrugCharacteristicCode`: imprint_code, size, shape, color, coating, scoring, logo, image

## care/emr/resources/inventory/supply_delivery/delivery_order.py

- `SupplyDeliveryOrderStatusOptions`: draft, pending, in_progress, completed, abandoned, entered_in_error

## care/emr/resources/inventory/supply_delivery/spec.py

- `SupplyDeliveryStatusOptions`: in_progress, completed, abandoned, entered_in_error
- `SupplyDeliveryTypeOptions`: product, device
- `SupplyDeliveryConditionOptions`: normal, damaged

## care/emr/resources/inventory/supply_request/request_order.py

- `SupplyRequestOrderStatusOptions`: draft, pending, in_progress, completed, abandoned, entered_in_error
- `SupplyRequestIntentOptions`: proposal, plan, directive, order, original_order, reflex_order, filler_order, instance_order
- `SupplyRequestCategoryOptions`: central, nonstock
- `SupplyRequestPriorityOptions`: routine, urgent, asap, stat
- `SupplyRequestReason`: patient_care, ward_stock

## care/emr/resources/inventory/supply_request/spec.py

- `SupplyRequestStatusOptions`: draft, active, suspended, cancelled, processed, completed, entered_in_error

## care/emr/resources/invoice/spec.py

- `InvoiceStatusOptions`: draft, issued, balanced, cancelled, entered_in_error

## care/emr/resources/location/spec.py

- `LocationEncounterAvailabilityStatusChoices`: planned, active, reserved, completed
- `StatusChoices`: active, inactive, unknown
- `LocationAvailabilityStatusChoices`: available, reserved
- `FacilityLocationOperationalStatusChoices`: C, H, O, U, K, I
- `FacilityLocationModeChoices`: instance, kind
- `InventoryUsage`: store, supplier, consumption, adjustment, none
- `FacilityLocationFormChoices`: si, bu, wi, wa, lvl, co, ro, bd, ve, ho, ca, rd, area, jdn, vi

## care/emr/resources/medication/administration/spec.py

- `MedicationAdministrationStatus`: completed, not_done, entered_in_error, stopped, in_progress, on_hold, unknown, cancelled
- `MedicationAdministrationCategory`: inpatient, outpatient, community, discharge
- `MedicationAdministrationPerformerFunction`: performer, verifier, witness

## care/emr/resources/medication/dispense/dispense_order.py

- `MedicationDispenseOrderStatusOptions`: draft, in_progress, completed, abandoned, entered_in_error

## care/emr/resources/medication/dispense/spec.py

- `MedicationDispenseStatus`: preparation, in_progress, cancelled, on_hold, completed, entered_in_error, stopped, declined
- `MedicationDispenseNotPerformedReason`: outofstock, washout, surg, sintol, sddi, sdupther, saig, preg
- `MedicationDispenseCategory`: inpatient, outpatient, community, discharge
- `SubstitutionType`: E, EC, BC, G, TE, TB, TG, F, N
- `SubstitutionReason`: CT, FP, OS, RR
- `CreateDispenseOrderStatusOptions`: draft, in_progress

## care/emr/resources/medication/request/spec.py

- `MedicationRequestStatus`: active, on_hold, ended, stopped, completed, cancelled, entered_in_error, draft, unknown
- `StatusReason`: altchoice, clarif, drughigh, hospadm, labint, non_avail, preg, salg, sddi, sdupther, sintol, surg, washout
- `MedicationRequestIntent`: proposal, plan, order, original_order, reflex_order, filler_order, instance_order
- `MedicationRequestPriority`: routine, urgent, asap, stat
- `MedicationRequestCategory`: inpatient, outpatient, community, discharge
- `MedicationRequestDispenseStatus`: complete, partial, incomplete, declined
- `TimingUnit`: s, min, h, d, wk, mo, a
- `DoseType`: ordered, calculated

## care/emr/resources/medication/request_prescription/spec.py

- `MedicationRequestPrescriptionStatus`: active, on_hold, ended, stopped, completed, cancelled, entered_in_error, draft

## care/emr/resources/medication/statement/spec.py

- `MedicationStatementStatus`: active, on_hold, completed, stopped, unknown, entered_in_error, not_taken, intended
- `MedicationStatementInformationSourceType`: related_person, practitioner, patient

## care/emr/resources/meta_artifact/spec.py

- `MetaArtifactAssociatingTypeChoices`: patient, encounter
- `MetaArtifactObjectTypeChoices`: drawing

## care/emr/resources/mfa/spec.py

- `LoginMethod`: totp, backup

## care/emr/resources/observation/spec.py

- `ObservationStatus`: final, amended, entered_in_error
- `PerformerType`: related_person, user

## care/emr/resources/observation_definition/spec.py

- `ObservationCategoryChoices`: social_history, vital_signs, imaging, laboratory, procedure, survey, exam, therapy, activity
- `ObservationStatusChoices`: draft, active, retired, unknown

## care/emr/resources/organization/spec.py

- `OrganizationTypeChoices`: team, govt, role, product_supplier

## care/emr/resources/patient/spec.py

- `BloodGroupChoices`: A_negative, A_positive, B_negative, B_positive, AB_negative, AB_positive, O_negative, O_positive, unknown
- `GenderChoices`: male, female, non_binary, transgender

## care/emr/resources/patient_identifier/spec.py

- `PatientIdentifierUse`: usual, official, temp, secondary, old
- `PatientIdentifierStatus`: draft, active, inactive

## care/emr/resources/payment_reconciliation/spec.py

- `PaymentReconciliationTypeOptions`: payment, adjustment, advance
- `PaymentReconciliationStatusOptions`: active, cancelled, draft, entered_in_error
- `PaymentReconciliationKindOptions`: deposit, periodic_payment, online, kiosk
- `PaymentReconciliationIssuerTypeOptions`: patient, insurer
- `PaymentReconciliationOutcomeOptions`: queued, complete, error, partial
- `PaymentReconciliationPaymentMethodOptions`: cash, ccca, cchk, cdac, chck, ddpo, debc

## care/emr/resources/questionnaire/spec.py

- `EnableOperator`: exists, equals, not_equals, greater, less, greater_or_equals, less_or_equals
- `EnableBehavior`: all, any
- `DisabledDisplay`: hidden, protected
- `QuestionType`: group, boolean, decimal, integer, string, text, display, date, dateTime, time, choice, url, quantity, structured
- `AnswerConstraint`: required, optional
- `QuestionnaireStatus`: active, retired, draft
- `SubjectType`: patient, encounter

## care/emr/resources/questionnaire_response/spec.py

- `QuestionnaireResponseStatusChoices`: completed, entered_in_error

## care/emr/resources/report/template/spec.py

- `TemplateStatusOptions`: draft, active, retired
- `TemplateFormatOptions`: pdf, html

## care/emr/resources/resource_category/spec.py

- `ResourceCategoryResourceTypeOptions`: product_knowledge, activity_definition, charge_item_definition

## care/emr/resources/resource_request/spec.py

- `StatusChoices`: pending, approved, rejected, cancelled, transportation_to_be_arranged, transfer_in_progress, completed
- `CategoryChoices`: patient_care, comfort_devices, medicines, financial, supplies, other

## care/emr/resources/scheduling/schedule/spec.py

- `SlotTypeOptions`: open, appointment, closed
- `SchedulableResourceTypeOptions`: practitioner, location, healthcare_service

## care/emr/resources/scheduling/slot/spec.py

- `BookingStatusChoices`: proposed, pending, booked, arrived, fulfilled, cancelled, noshow, entered_in_error, checked_in, waitlist, in_consultation, rescheduled

## care/emr/resources/scheduling/token/spec.py

- `TokenStatusOptions`: UNFULFILLED, CREATED, IN_PROGRESS, FULFILLED, CANCELLED, ENTERED_IN_ERROR

## care/emr/resources/scheduling/token_sub_queue/spec.py

- `TokenSubQueueStatusOptions`: active, inactive

## care/emr/resources/service_request/spec.py

- `ServiceRequestStatusChoices`: draft, active, on_hold, entered_in_error, ended, completed, revoked
- `ServiceRequestIntentChoices`: proposal, plan, directive, order
- `ServiceRequestPriorityChoices`: routine, urgent, asap, stat

## care/emr/resources/specimen/spec.py

- `SpecimenStatusOptions`: draft, available, unavailable, unsatisfactory, entered_in_error

## care/emr/resources/specimen_definition/spec.py

- `SpecimenDefinitionStatusOptions`: draft, active, retired
- `PreferenceOptions`: preferred, alternate
- `HandlingConditionOptions`: room, refrigerated, frozen

## care/emr/resources/tag/config_spec.py

- `TagCategoryChoices`: diet, drug, lab, admin, contact, clinical, behavioral, research, advance_directive, safety
- `TagResource`: encounter, activity_definition, service_request, charge_item, charge_item_definition, patient, token_booking, medication_request_prescription, supply_request_order, supply_delivery_order, account, location
- `TagStatus`: active, archived

## care/emr/resources/valueset/spec.py

- `ValueSetStatusOptions`: draft, active, retired, unknown

## care/facility/models/facility.py

- `HubRelationship`: 1, 2
- `FacilityFeature`: 1, 2, 3, 4, 5, 6
- `FACILITY_TYPES`: 1, 2, 3, 4, 5, 6, 7, 9, 10, 800, 802, 803, 830, 840, 860, 870, 900, 910, 1010, 1100, 1200, 1300, 1400, 1500, 1510, 1600, 3000, 3001, 4000
- `DOCTOR_TYPES`: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64

## care/users/models.py

- `GENDER_CHOICES`: 1, 2, 3
