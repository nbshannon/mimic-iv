WITH
  code AS (
  SELECT
    poe_detail.subject_id,
    poe.hadm_id,
    MAX(CASE
        WHEN poe_detail.field_value = "DNAR (DO NOT attempt resuscitation for cardiac arrest)" OR poe_detail.field_value = "Do not resuscitate (DNR/DNI)" THEN TRUE
      ELSE
      FALSE
    END
      ) AS code_dnar
  FROM
    `physionet-data.mimic_hosp.poe_detail` poe_detail
  INNER JOIN
    `physionet-data.mimic_hosp.poe` poe
  ON
    poe_detail.poe_id = poe.poe_id
  GROUP BY
    poe.hadm_id,
    poe_detail.subject_id ),
  filtering AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    transfers.careunit AS prior_unit,
    icustays.los,
    sepsis3.sepsis3,
    code.code_dnar
  FROM
    `physionet-data.mimic_icu.icustays` icustays
  INNER JOIN
    `physionet-data.mimic_core.transfers` transfers
  ON
    icustays.hadm_id = transfers.hadm_id
    AND icustays.intime = transfers.outtime
  INNER JOIN
    `physionet-data.mimic_derived.sepsis3` sepsis3
  ON
    icustays.stay_id = sepsis3.stay_id
  INNER JOIN
    code
  ON
    code.hadm_id = icustays.hadm_id ),
  cohort AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id
  FROM
    filtering
  WHERE
    prior_unit IN ('Emergency Department',
      'Emergency Department Observation')
    AND los >= 3
    AND sepsis3 = TRUE
    AND code_dnar = FALSE ),
  icu_details AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    CASE
      WHEN admissions.deathtime BETWEEN icustays.intime AND icustays.outtime THEN 1
      WHEN admissions.deathtime <= icustays.intime THEN 1 -- sometimes there are typographical errors in the death date
      WHEN admissions.dischtime <= icustays.outtime AND admissions.discharge_location = 'DEAD/EXPIRED' THEN 1
    ELSE
    0
  END
    AS icustay_expire_flag,
    admissions.hospital_expire_flag,
    icustays.los AS los_icu,
    DATETIME_DIFF(admissions.dischtime, admissions.admittime, HOUR)/24 AS los_hospital,
    CASE
      WHEN (DENSE_RANK() OVER (PARTITION BY icustays.hadm_id ORDER BY icustays.intime DESC))>1 THEN 1
    ELSE
    0
  END
    AS icu_readmission
  FROM
    `physionet-data.mimic_icu.icustays` icustays
  INNER JOIN
    `physionet-data.mimic_core.admissions` admissions
  ON
    icustays.hadm_id = admissions.hadm_id )
SELECT
  cohort.subject_id,
  cohort.hadm_id,
  cohort.stay_id,
  icu_details.icustay_expire_flag,
  icu_details.hospital_expire_flag,
  icu_details.los_icu,
  icu_details.los_hospital,
  icu_details.icu_readmission
FROM
  cohort
LEFT JOIN
  icu_details
ON
  cohort.stay_id = icu_details.stay_id