begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(65);

select extensions.has_table('public', 'measurement_units', 'measurement unit reference exists');
select extensions.has_table('public', 'observation_fields', 'observation field reference exists');
select extensions.has_table('public', 'observation_sources', 'observation sources exist');
select extensions.has_table('public', 'observation_streams', 'observation streams exist');
select extensions.has_table('public', 'observation_calibrations', 'calibration history exists');
select extensions.has_table('public', 'stream_observations', 'typed observation ledger exists');
select extensions.has_table('public', 'observation_quality_findings', 'quality findings use child rows');
select extensions.has_table('public', 'activity_trigger_evaluations', 'trigger evaluation header exists');
select extensions.has_table(
  'public', 'activity_trigger_predicate_evaluations', 'predicate evidence rows exist'
);
select extensions.has_table(
  'public', 'activity_trigger_evaluation_work_areas', 'evaluation area snapshots exist'
);

select extensions.is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'measurement_units',
        'observation_fields',
        'observation_sources',
        'observation_streams',
        'observation_calibrations',
        'stream_observations',
        'observation_quality_findings',
        'activity_trigger_evaluations',
        'activity_trigger_predicate_evaluations',
        'activity_trigger_evaluation_work_areas'
      )
      and data_type in ('json', 'jsonb')
  ),
  0,
  'phase 2B persists no JSON or JSONB columns'
);

select extensions.ok(
  exists (
    select 1 from public.measurement_units
    where code = 'degC' and quantity_kind = 'TEMPERATURE'
  ),
  'canonical temperature unit is seeded'
);

select extensions.ok(
  exists (
    select 1 from public.observation_fields
    where code = 'sensor.temperature_c'
      and value_type = 'NUMERIC'
      and canonical_unit_code = 'degC'
  ),
  'smart-farm temperature field is typed and unit-bound'
);

insert into auth.users (id, email)
values
  ('15000000-0000-4000-8000-000000000001', 'phase2b-owner@example.test'),
  ('15000000-0000-4000-8000-000000000002', 'phase2b-worker@example.test'),
  ('15000000-0000-4000-8000-000000000003', 'phase2b-outsider@example.test');

insert into public.farms (
  id, slug, name, region, country_code, latitude, longitude, timezone, created_by
)
values (
  '25000000-0000-4000-8000-000000000001',
  'phase2b-farm',
  'Phase 2B Farm',
  'Test Region',
  'KR',
  37.5,
  127.0,
  'Asia/Seoul',
  '15000000-0000-4000-8000-000000000001'
);

insert into public.farm_memberships (farm_id, user_id, role)
values
  (
    '25000000-0000-4000-8000-000000000001',
    '15000000-0000-4000-8000-000000000001',
    'owner'
  ),
  (
    '25000000-0000-4000-8000-000000000001',
    '15000000-0000-4000-8000-000000000002',
    'worker'
  );

insert into public.farm_work_areas (
  id, farm_id, code, name, area_type, is_active
)
values (
  '45000000-0000-4000-8000-000000000001',
  '25000000-0000-4000-8000-000000000001',
  'GH-01',
  'Greenhouse 01',
  'greenhouse',
  true
);

insert into public.cultivation_cycles (
  id, farm_id, crop, variety, planted_at, growth_stage, status
)
values (
  '35000000-0000-4000-8000-000000000001',
  '25000000-0000-4000-8000-000000000001',
  'tomato',
  'phase2b-cycle',
  current_date,
  'test-stage',
  'active'
);

create temporary table phase2b_clock (base_at timestamptz not null);
insert into phase2b_clock
values (date_trunc('second', now()) - interval '6 hours');
grant select on phase2b_clock to authenticated, anon;

set local role authenticated;
set local request.jwt.claim.sub = '15000000-0000-4000-8000-000000000001';

select extensions.lives_ok(
  $$
    select public.create_observation_source(
      '25000000-0000-4000-8000-000000000001',
      'GH01-GATEWAY',
      'Greenhouse gateway',
      'SENSOR_GATEWAY',
      'test-provider',
      'gateway-01'
    )
  $$,
  'owner creates a sensor observation source'
);

select extensions.lives_ok(
  $$
    select public.create_observation_stream(
      '25000000-0000-4000-8000-000000000001',
      (select id from public.observation_sources where source_code = 'GH01-GATEWAY'),
      'sensor.temperature_c',
      'GH01-TEMP',
      'Greenhouse temperature',
      '45000000-0000-4000-8000-000000000001',
      5,
      true
    )
  $$,
  'owner creates a calibrated temperature stream'
);

select extensions.ok(
  (
    select unit_code = 'degC'
      and requires_calibration
      and work_area_id = '45000000-0000-4000-8000-000000000001'::uuid
    from public.observation_streams
    where stream_code = 'GH01-TEMP'
  ),
  'stream inherits canonical unit and work area'
);

select extensions.throws_ok(
  $$
    select public.create_observation_stream(
      '25000000-0000-4000-8000-000000000001',
      (select id from public.observation_sources where source_code = 'GH01-GATEWAY'),
      'weather.temperature_c',
      'INVALID-WEATHER',
      'Invalid weather stream'
    )
  $$,
  'P0001',
  null,
  'sensor source cannot use a weather field'
);

select extensions.lives_ok(
  $$
    select public.record_observation_calibration(
      '25000000-0000-4000-8000-000000000001',
      (select id from public.observation_streams where stream_code = 'GH01-TEMP'),
      'TEMP-CAL-001',
      (select base_at - interval '1 day' from phase2b_clock),
      (select base_at + interval '1 day' from phase2b_clock),
      'KOLAS-TRACEABLE',
      'CERT-001',
      'Test Lab'
    )
  $$,
  'owner records a bounded calibration period'
);

select extensions.throws_ok(
  $$
    select public.record_observation_calibration(
      '25000000-0000-4000-8000-000000000001',
      (select id from public.observation_streams where stream_code = 'GH01-TEMP'),
      'TEMP-CAL-OVERLAP',
      (select base_at from phase2b_clock),
      (select base_at + interval '2 days' from phase2b_clock)
    )
  $$,
  'P0001',
  null,
  'valid calibration periods cannot overlap'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      target_stream_id := (
        select id from public.observation_streams where stream_code = 'GH01-TEMP'
      ),
      observation_observed_at := (
        select base_at - interval '1 minute' from phase2b_clock
      ),
      observation_idempotency_key := 'temp-reading:base-001',
      observation_numeric_value := 32,
      observation_received_at := (
        select base_at - interval '1 minute' from phase2b_clock
      ),
      source_sequence := 'temp-001'
    )
  $$,
  'calibrated on-time numeric observation is recorded'
);

select extensions.ok(
  (
    select quality_status = 'VALID'
      and calibration_id is not null
      and numeric_value = 32
    from public.stream_observations
    where idempotency_key = 'temp-reading:base-001'
  ),
  'valid observation preserves calibration and typed value'
);

select extensions.throws_ok(
  $$
    select public.record_stream_observation(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      target_stream_id := (
        select id from public.observation_streams where stream_code = 'GH01-TEMP'
      ),
      observation_observed_at := now(),
      observation_idempotency_key := 'temp-reading:two-values',
      observation_numeric_value := 30,
      observation_text_value := 'thirty'
    )
  $$,
  'P0001',
  null,
  'observation requires exactly one typed value'
);

select extensions.lives_ok(
  $$
    select public.create_observation_stream(
      '25000000-0000-4000-8000-000000000001',
      (select id from public.observation_sources where source_code = 'GH01-GATEWAY'),
      'sensor.humidity_pct',
      'GH01-HUMIDITY',
      'Greenhouse humidity',
      '45000000-0000-4000-8000-000000000001',
      5,
      false
    )
  $$,
  'owner creates a humidity stream'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      target_stream_id := (
        select id from public.observation_streams where stream_code = 'GH01-HUMIDITY'
      ),
      observation_observed_at := (
        select base_at - interval '1 minute' from phase2b_clock
      ),
      observation_idempotency_key := 'humidity-reading:base-001',
      observation_numeric_value := 85,
      observation_received_at := (
        select base_at - interval '1 minute' from phase2b_clock
      ),
      source_sequence := 'humidity-001'
    )
  $$,
  'humidity evidence is recorded for trigger evaluation'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      target_stream_id := (
        select id from public.observation_streams where stream_code = 'GH01-HUMIDITY'
      ),
      observation_observed_at := date_trunc('second', now()) - interval '1 minute',
      observation_idempotency_key := 'humidity-reading:idempotent-001',
      observation_numeric_value := 84,
      source_sequence := 'humidity-idempotent-001'
    )
  $$,
  'observation can use a server receipt timestamp'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      target_stream_id := (
        select id from public.observation_streams where stream_code = 'GH01-HUMIDITY'
      ),
      observation_observed_at := date_trunc('second', now()) - interval '1 minute',
      observation_idempotency_key := 'humidity-reading:idempotent-001',
      observation_numeric_value := 84,
      source_sequence := 'humidity-idempotent-001'
    )
  $$,
  'same observation key retries without a new server timestamp conflict'
);

select extensions.is(
  (
    select count(*)::integer from public.stream_observations
    where idempotency_key = 'humidity-reading:idempotent-001'
  ),
  1,
  'same observation key creates one immutable row'
);

select extensions.throws_ok(
  $$
    select public.record_stream_observation(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      target_stream_id := (
        select id from public.observation_streams where stream_code = 'GH01-HUMIDITY'
      ),
      observation_observed_at := date_trunc('second', now()) - interval '1 minute',
      observation_idempotency_key := 'humidity-reading:idempotent-001',
      observation_numeric_value := 83,
      source_sequence := 'humidity-idempotent-001'
    )
  $$,
  'P0001',
  null,
  'same observation key rejects a different payload'
);

select extensions.lives_ok(
  $$
    select public.create_observation_stream(
      '25000000-0000-4000-8000-000000000001',
      (select id from public.observation_sources where source_code = 'GH01-GATEWAY'),
      'sensor.soil_moisture_pct',
      'GH01-SOIL',
      'Greenhouse soil moisture',
      '45000000-0000-4000-8000-000000000001',
      5,
      true
    )
  $$,
  'owner creates a calibration-required soil stream'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      target_stream_id := (
        select id from public.observation_streams where stream_code = 'GH01-SOIL'
      ),
      observation_observed_at := now() - interval '1 minute',
      observation_idempotency_key := 'soil-reading:uncalibrated-001',
      observation_numeric_value := 41,
      observation_received_at := now() - interval '1 minute'
    )
  $$,
  'uncalibrated observation is retained with quality evidence'
);

select extensions.ok(
  (
    select observation.quality_status = 'UNCALIBRATED'
      and finding.finding_code = 'NO_VALID_CALIBRATION'
    from public.stream_observations as observation
    join public.observation_quality_findings as finding
      on finding.observation_id = observation.id
    where observation.idempotency_key = 'soil-reading:uncalibrated-001'
  ),
  'missing calibration derives an explicit finding'
);

select extensions.lives_ok(
  $$
    select public.create_observation_stream(
      '25000000-0000-4000-8000-000000000001',
      (select id from public.observation_sources where source_code = 'GH01-GATEWAY'),
      'sensor.co2_ppm',
      'GH01-CO2',
      'Greenhouse carbon dioxide',
      '45000000-0000-4000-8000-000000000001',
      1,
      false
    )
  $$,
  'owner creates a low-latency carbon dioxide stream'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      target_stream_id := (
        select id from public.observation_streams where stream_code = 'GH01-CO2'
      ),
      observation_observed_at := now() - interval '10 minutes',
      observation_idempotency_key := 'co2-reading:late-001',
      observation_numeric_value := 900,
      observation_received_at := now()
    )
  $$,
  'late observation is retained'
);

select extensions.ok(
  (
    select observation.quality_status = 'LATE'
      and finding.finding_code = 'RECEIVED_LATE'
    from public.stream_observations as observation
    join public.observation_quality_findings as finding
      on finding.observation_id = observation.id
    where observation.idempotency_key = 'co2-reading:late-001'
  ),
  'latency threshold derives an explicit finding'
);

set local request.jwt.claim.sub = '15000000-0000-4000-8000-000000000002';

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      target_stream_id := (
        select id from public.observation_streams where stream_code = 'GH01-HUMIDITY'
      ),
      observation_observed_at := (
        select base_at - interval '2 minutes' from phase2b_clock
      ),
      observation_idempotency_key := 'humidity-reading:worker-001',
      observation_numeric_value := 85,
      observation_received_at := (
        select base_at - interval '2 minutes' from phase2b_clock
      )
    )
  $$,
  'farm worker can record a stream observation'
);

select extensions.throws_ok(
  $$
    select public.create_observation_source(
      '25000000-0000-4000-8000-000000000001',
      'WORKER-SOURCE',
      'Worker source',
      'MANUAL'
    )
  $$,
  'P0001',
  null,
  'farm worker cannot create an observation source'
);

set local request.jwt.claim.sub = '15000000-0000-4000-8000-000000000003';

select extensions.throws_ok(
  $$
    select public.record_stream_observation(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      target_stream_id := (
        select id from public.observation_streams where stream_code = 'GH01-HUMIDITY'
      ),
      observation_observed_at := now(),
      observation_idempotency_key := 'humidity-reading:outsider-001',
      observation_numeric_value := 85
    )
  $$,
  'P0001',
  null,
  'farm outsider cannot record observations'
);

set local request.jwt.claim.sub = '15000000-0000-4000-8000-000000000001';

select extensions.lives_ok(
  $$
    select public.create_schedule_project(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      target_cycle_id := '35000000-0000-4000-8000-000000000001',
      project_code := 'OBSERVATION-PROJECT',
      project_name := 'Observation Project',
      project_timezone := 'Asia/Seoul',
      root_wbs_code := 'ROOT',
      root_wbs_name := 'Observation Root',
      calendar_code := 'DEFAULT',
      calendar_name := 'Default Calendar',
      calendar_working_periods := jsonb_build_array(
        jsonb_build_object(
          'weekday', 1, 'start_time', '08:00', 'end_time', '17:00'
        )
      )
    )
  $$,
  'owner creates a schedule project for trigger proposals'
);

select extensions.lives_ok(
  $$
    select public.create_activity_template(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      template_code := 'HEAT-RESPONSE',
      template_name := 'Heat response inspection',
      target_operation_type_code := 'environment_control',
      template_default_duration_minutes := 45
    )
  $$,
  'owner creates the trigger proposal template'
);

select extensions.lives_ok(
  $$
    select public.create_activity_trigger_rule(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'OBSERVATION-PROJECT'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'HEAT-RESPONSE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'OBSERVATION-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'HOT-HUMID',
      rule_name := 'High temperature and humidity',
      trigger_event_type := 'SENSOR_OBSERVATION',
      rule_status := 'ACTIVE',
      predicate_match_mode := 'ALL',
      cooldown_minutes := 60,
      predicate_field_codes := array[
        'sensor.temperature_c',
        'sensor.humidity_pct'
      ],
      predicate_operators := array['GTE', 'GTE'],
      predicate_numeric_values := array[30::numeric, 80::numeric],
      predicate_text_values := array[null::text, null::text],
      predicate_boolean_values := array[null::boolean, null::boolean],
      predicate_unit_codes := array['degC', 'pct'],
      predicate_window_minutes := array[240, 240],
      target_work_area_ids := array[
        '45000000-0000-4000-8000-000000000001'::uuid
      ]
    )
  $$,
  'owner creates an active two-predicate sensor trigger'
);

select extensions.lives_ok(
  $$
    select public.evaluate_activity_trigger_rule(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'OBSERVATION-PROJECT'
      ),
      target_rule_id := (
        select id from public.activity_trigger_rules where rule_code = 'HOT-HUMID'
      ),
      expected_rule_version := 1,
      target_evaluated_at := (select base_at from phase2b_clock),
      run_idempotency_key := 'trigger-eval:match-001'
    )
  $$,
  'quality-sufficient matching observations evaluate successfully'
);

select extensions.ok(
  (
    select status = 'SUCCEEDED'
      and outcome_code = 'PROPOSAL_CREATED'
      and finished_at is not null
    from public.activity_rule_runs
    where idempotency_key = 'trigger-eval:match-001'
  ),
  'matching trigger run records a terminal proposal outcome'
);

select extensions.ok(
  (
    select predicate_count = 2
      and matched_count = 2
      and insufficient_count = 0
    from public.activity_trigger_evaluations
    where rule_run_id = (
      select id from public.activity_rule_runs
      where idempotency_key = 'trigger-eval:match-001'
    )
  ),
  'evaluation header records predicate result counts'
);

select extensions.is(
  (
    select count(*)::integer
    from public.activity_trigger_predicate_evaluations
    where rule_run_id = (
      select id from public.activity_rule_runs
      where idempotency_key = 'trigger-eval:match-001'
    )
      and result_status = 'MATCHED'
      and observation_id is not null
      and observation_quality_status = 'VALID'
      and expected_unit_code = observed_unit_code
  ),
  2,
  'each predicate links valid evidence with an exact unit'
);

select extensions.is(
  (
    select count(*)::integer
    from public.activity_proposals
    where rule_run_id = (
      select id from public.activity_rule_runs
      where idempotency_key = 'trigger-eval:match-001'
    )
      and status = 'PROPOSED'
      and planned_duration_minutes = 45
      and exists (
        select 1
        from public.activity_proposal_work_areas as area
        where area.proposal_id = activity_proposals.id
          and area.work_area_id = '45000000-0000-4000-8000-000000000001'::uuid
          and area.is_primary
      )
  ),
  1,
  'matching evaluation creates one area-bound proposal'
);

select extensions.lives_ok(
  $$
    select public.evaluate_activity_trigger_rule(
      '25000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'OBSERVATION-PROJECT'),
      (select id from public.activity_trigger_rules where rule_code = 'HOT-HUMID'),
      1,
      (select base_at from phase2b_clock),
      'trigger-eval:match-001'
    )
  $$,
  'same trigger evaluation key returns the existing result'
);

select extensions.is(
  (
    select count(*)::integer from public.activity_rule_runs
    where idempotency_key = 'trigger-eval:match-001'
  ),
  1,
  'same trigger evaluation key creates one run'
);

select extensions.throws_ok(
  $$
    select public.evaluate_activity_trigger_rule(
      '25000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'OBSERVATION-PROJECT'),
      (select id from public.activity_trigger_rules where rule_code = 'HOT-HUMID'),
      1,
      (select base_at + interval '1 minute' from phase2b_clock),
      'trigger-eval:match-001'
    )
  $$,
  'P0001',
  null,
  'same run key cannot identify another evaluation time'
);

select extensions.throws_ok(
  $$
    select public.evaluate_activity_trigger_rule(
      '25000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'OBSERVATION-PROJECT'),
      (select id from public.activity_trigger_rules where rule_code = 'HOT-HUMID'),
      1,
      (select base_at from phase2b_clock),
      'trigger-eval:duplicate-time-001'
    )
  $$,
  'P0001',
  null,
  'same rule version and time cannot use another key'
);

select extensions.lives_ok(
  $$
    select public.evaluate_activity_trigger_rule(
      '25000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'OBSERVATION-PROJECT'),
      (select id from public.activity_trigger_rules where rule_code = 'HOT-HUMID'),
      1,
      (select base_at + interval '30 minutes' from phase2b_clock),
      'trigger-eval:cooldown-001'
    )
  $$,
  'evaluation during cooldown records a skipped run'
);

select extensions.ok(
  (
    select run.status = 'SKIPPED'
      and run.outcome_code = 'COOLDOWN_ACTIVE'
      and not exists (
        select 1 from public.activity_trigger_predicate_evaluations as result
        where result.rule_run_id = run.id
      )
      and not exists (
        select 1 from public.activity_proposals as proposal
        where proposal.rule_run_id = run.id
      )
    from public.activity_rule_runs as run
    where run.idempotency_key = 'trigger-eval:cooldown-001'
  ),
  'cooldown run produces neither evidence nor proposal'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      target_stream_id := (
        select id from public.observation_streams where stream_code = 'GH01-TEMP'
      ),
      observation_observed_at := (
        select base_at + interval '90 minutes' from phase2b_clock
      ),
      observation_idempotency_key := 'temp-reading:invalid-001',
      observation_numeric_value := 35,
      observation_received_at := (
        select base_at + interval '90 minutes' from phase2b_clock
      ),
      source_quality_status := 'INVALID',
      source_sequence := 'temp-invalid-001'
    )
  $$,
  'source-invalid observation is retained for audit'
);

select extensions.lives_ok(
  $$
    select public.evaluate_activity_trigger_rule(
      '25000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'OBSERVATION-PROJECT'),
      (select id from public.activity_trigger_rules where rule_code = 'HOT-HUMID'),
      1,
      (select base_at + interval '91 minutes' from phase2b_clock),
      'trigger-eval:quality-001'
    )
  $$,
  'invalid latest evidence records an insufficient evaluation'
);

select extensions.ok(
  (
    select run.status = 'SKIPPED'
      and run.outcome_code = 'INSUFFICIENT_EVIDENCE'
      and evaluation.insufficient_count = 1
      and exists (
        select 1
        from public.activity_trigger_predicate_evaluations as result
        where result.rule_run_id = run.id
          and result.source_field_code = 'sensor.temperature_c'
          and result.result_status = 'INSUFFICIENT'
          and result.reason_code = 'OBSERVATION_INVALID'
          and result.observation_id is not null
      )
      and not exists (
        select 1 from public.activity_proposals as proposal
        where proposal.rule_run_id = run.id
      )
    from public.activity_rule_runs as run
    join public.activity_trigger_evaluations as evaluation
      on evaluation.rule_run_id = run.id
    where run.idempotency_key = 'trigger-eval:quality-001'
  ),
  'invalid evidence abstains with a stable reason and no proposal'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      target_farm_id := '25000000-0000-4000-8000-000000000001',
      target_stream_id := (
        select id from public.observation_streams where stream_code = 'GH01-TEMP'
      ),
      observation_observed_at := (
        select base_at + interval '180 minutes' from phase2b_clock
      ),
      observation_idempotency_key := 'temp-reading:low-001',
      observation_numeric_value := 25,
      observation_received_at := (
        select base_at + interval '180 minutes' from phase2b_clock
      ),
      source_sequence := 'temp-low-001'
    )
  $$,
  'later valid non-matching observation is recorded'
);

select extensions.lives_ok(
  $$
    select public.evaluate_activity_trigger_rule(
      '25000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'OBSERVATION-PROJECT'),
      (select id from public.activity_trigger_rules where rule_code = 'HOT-HUMID'),
      1,
      (select base_at + interval '181 minutes' from phase2b_clock),
      'trigger-eval:not-matched-001'
    )
  $$,
  'quality-sufficient non-matching evidence evaluates successfully'
);

select extensions.ok(
  (
    select run.status = 'SUCCEEDED'
      and run.outcome_code = 'PREDICATES_NOT_MATCHED'
      and evaluation.matched_count = 1
      and evaluation.insufficient_count = 0
      and not exists (
        select 1 from public.activity_proposals as proposal
        where proposal.rule_run_id = run.id
      )
    from public.activity_rule_runs as run
    join public.activity_trigger_evaluations as evaluation
      on evaluation.rule_run_id = run.id
    where run.idempotency_key = 'trigger-eval:not-matched-001'
  ),
  'non-matching evidence completes without a proposal'
);

select extensions.throws_ok(
  $$
    select public.evaluate_activity_trigger_rule(
      '25000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'OBSERVATION-PROJECT'),
      (select id from public.activity_trigger_rules where rule_code = 'HOT-HUMID'),
      2,
      (select base_at + interval '182 minutes' from phase2b_clock),
      'trigger-eval:stale-001'
    )
  $$,
  '40001',
  null,
  'stale trigger rule version cannot be evaluated'
);

select extensions.throws_ok(
  $$ insert into public.stream_observations default values $$,
  '42501',
  null,
  'authenticated clients cannot directly insert observation rows'
);

select extensions.throws_ok(
  $$ insert into public.activity_trigger_predicate_evaluations default values $$,
  '42501',
  null,
  'authenticated clients cannot directly insert evidence rows'
);

set local request.jwt.claim.sub = '15000000-0000-4000-8000-000000000002';

select extensions.ok(
  (select count(*) > 0 from public.stream_observations),
  'farm worker can read farm observations through RLS'
);

set local request.jwt.claim.sub = '15000000-0000-4000-8000-000000000003';

select extensions.is(
  (select count(*)::integer from public.stream_observations),
  0,
  'farm outsider cannot read observations through RLS'
);

set local role anon;
set local request.jwt.claim.sub = '';

select extensions.throws_ok(
  $$ select count(*) from public.stream_observations $$,
  '42501',
  null,
  'anonymous role has no observation table privilege'
);

select extensions.throws_ok(
  $$
    select public.evaluate_activity_trigger_rule(
      '25000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'OBSERVATION-PROJECT'),
      (select id from public.activity_trigger_rules where rule_code = 'HOT-HUMID'),
      1,
      (select base_at + interval '183 minutes' from phase2b_clock),
      'trigger-eval:anon-001'
    )
  $$,
  '42501',
  null,
  'anonymous role cannot execute trigger evaluation RPC'
);

set local role authenticated;
set local request.jwt.claim.sub = '15000000-0000-4000-8000-000000000001';

select extensions.throws_ok(
  $$
    insert into public.observation_sources (
      farm_id, source_code, name, source_kind, created_by
    )
    values (
      '25000000-0000-4000-8000-000000000001',
      'DIRECT-SOURCE',
      'Direct source',
      'MANUAL',
      '15000000-0000-4000-8000-000000000001'
    )
  $$,
  '42501',
  null,
  'even managers must create sources through RPC'
);

reset role;

select * from extensions.finish();

rollback;
