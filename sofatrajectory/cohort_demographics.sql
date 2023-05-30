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

cohort as (    
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
  AND code_dnar = FALSE
)

SELECT
  cohort.subject_id,
  cohort.hadm_id,
  cohort.stay_id,
  icustay_detail.gender,
  icustay_detail.admission_age,
  icustay_detail.first_hosp_stay,
  icustay_detail.first_icu_stay,
  admissions.ethnicity,
  admissions.insurance,
  first_day_weight.weight_admit,
  first_day_weight.weight,
  height.height,
  charlson.*
FROM
cohort
left join
  `physionet-data.mimic_icu.icustays` icustays
on
cohort.stay_id = icustays.stay_id
left JOIN
  `physionet-data.mimic_derived.icustay_detail` icustay_detail
ON
  icustays.stay_id = icustay_detail.stay_id
left JOIN
  `physionet-data.mimic_core.admissions` admissions
ON
  icustays.subject_id = admissions.subject_id
  AND icustays.hadm_id = admissions.hadm_id
left JOIN
  `physionet-data.mimic_derived.charlson` charlson
ON
  icustays.subject_id = charlson.subject_id
  AND icustays.hadm_id = charlson.hadm_id
left JOIN
  `physionet-data.mimic_derived.first_day_weight` first_day_weight
ON
  icustays.stay_id = first_day_weight.stay_id
left JOIN
  `physionet-data.mimic_derived.height` height
ON
  icustays.stay_id = height.stay_id