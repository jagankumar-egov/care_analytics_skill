-- KPI 11: MPPS Webhook Volume (daily)
--
-- The modality -> CARE integration heartbeat. A day with orders but no MPPS
-- events means the DICOM Enabler stopped calling, which silently freezes every
-- study at ACTIVE and makes the TAT cards look like a reporting problem.
--
-- The log row is written after payload validation but BEFORE the status is
-- applied, so LOGGED is "accepted", not "applied" -- compare it with APPLIED.
--
-- Parameters: {{start_date}}, {{end_date}} (IST dates, inclusive)
WITH
  bounds AS (
    SELECT
      ({{start_date}}::DATE)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata'   AS period_start,
      ({{end_date}}::DATE + 1)::TIMESTAMP AT TIME ZONE 'Asia/Kolkata' AS period_end
  ),
  events AS (
    SELECT
      (w.created_date AT TIME ZONE 'Asia/Kolkata')::DATE          AS event_date,
      w.type                                                      AS webhook_type,
      w.raw_data ->> 'study_status'                               AS study_status,
      LOWER(w.raw_data ->> 'service_request_id')                  AS sr_external_id,
      w.created_by_id,
      w.id
    FROM care_radiology_radiologywebhooklogs w
    CROSS JOIN bounds b
    WHERE w.deleted = FALSE
      AND w.created_date >= b.period_start
      AND w.created_date <  b.period_end
  )
SELECT
  e.event_date                                                                  AS "EVENT_DATE",
  e.webhook_type                                                                AS "WEBHOOK_TYPE",
  COUNT(*)                                                                      AS "LOGGED",
  COUNT(DISTINCT e.sr_external_id)                                              AS "DISTINCT_ORDERS",
  COUNT(*) FILTER (WHERE e.study_status = 'IN_PROGRESS')                        AS "SCAN_STARTED",
  COUNT(*) FILTER (WHERE e.study_status = 'COMPLETED')                          AS "SCAN_COMPLETED",
  COUNT(*) FILTER (WHERE e.study_status = 'CANCELLED')                          AS "SCAN_CANCELLED",
  COUNT(DISTINCT e.created_by_id)                                               AS "SERVICE_ACCOUNTS",
  COUNT(*) FILTER (WHERE ist.id IS NOT NULL)                                    AS "MATCHED_TO_STUDY",
  COUNT(*) FILTER (WHERE ist.id IS NULL)                                        AS "UNMATCHED",
  -- Applied = the study actually carries (or has moved past) the status sent.
  COUNT(*) FILTER (
    WHERE ist.status = e.study_status
       OR (e.study_status = 'IN_PROGRESS' AND ist.status IN ('COMPLETED', 'CANCELLED'))
  )                                                                             AS "APPLIED"
FROM events e
LEFT JOIN emr_servicerequest sr       ON sr.external_id::TEXT = e.sr_external_id AND sr.deleted = FALSE
LEFT JOIN care_radiology_imagingstudy ist
                                      ON ist.service_request_id = sr.id AND ist.deleted = FALSE
GROUP BY e.event_date, e.webhook_type
ORDER BY "EVENT_DATE" DESC;
