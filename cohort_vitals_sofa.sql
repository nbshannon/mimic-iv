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
),

co AS
(
  select cohort.subject_id, cohort.stay_id, cohort.hadm_id
  , hr
  , DATETIME_SUB(icustay_hourly.endtime, INTERVAL '1' HOUR) AS starttime
  , icustay_hourly.endtime
  from cohort
inner join
 `physionet-data.mimic_derived.icustay_hourly` icustay_hourly
    ON cohort.stay_id = icustay_hourly.stay_id
),

 vs AS
(
  select
  co.subject_id
  , co.hadm_id
  , co.stay_id
  , co.hr
  , co.starttime
  , co.endtime
  , avg(vs.sbp) as sbp
  , avg(vs.dbp) as dbp
  , avg(vs.heart_rate) as heart_rate
  from co
  left join `physionet-data.mimic_derived.vitalsign` vs
    on co.stay_id = vs.stay_id
    and co.starttime < vs.charttime
    and co.endtime >= vs.charttime
  group by co.subject_id, co.hadm_id, co.stay_id, co.hr,co.starttime,co.endtime
)

select
 vs.*
, sofa.sofa_24hours

from vs
inner join `physionet-data.mimic_derived.sofa` sofa
on vs.stay_id = sofa.stay_id and vs.hr = sofa.hr
