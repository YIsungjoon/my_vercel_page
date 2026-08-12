begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(46);

select extensions.has_table(
  'public', 'observation_event_consumptions', 'event consumption ledger exists'
);
select extensions.has_table(
  'public', 'observation_event_rule_consumptions', 'event rule receipts exist'
);
select extensions.has_column(
  'public', 'activity_rule_runs', 'execution_worker_id', 'rule run records service worker actor'
);
select extensions.has_column(
  'public', 'activity_proposals', 'created_by_worker_id', 'proposal records service creator'
);
select extensions.has_column(
  'public', 'activity_proposals', 'updated_by_worker_id', 'proposal records service updater'
);

select extensions.is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'observation_event_consumptions',
        'observation_event_rule_consumptions'
      )
      and data_type in ('json', 'jsonb')
  ),
  0,
  'phase 2D persists no JSON or JSONB columns'
);

select extensions.ok(
  has_function_privilege(
    'service_role',
    'public.consume_observation_outbox_message(uuid,uuid,text,integer)',
    'EXECUTE'
  ),
  'service role can invoke the observation consumer'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.consume_observation_outbox_message(uuid,uuid,text,integer)',
    'EXECUTE'
  ),
  'authenticated clients cannot invoke the observation consumer'
);
select extensions.ok(
  has_function_privilege(
    'service_role',
    'public.claim_outbox_topic_messages(text,text,integer,integer)',
    'EXECUTE'
  ),
  'service role can claim one outbox topic'
);

insert into auth.users (id, email)
values
  ('18000000-0000-4000-8000-000000000001', 'phase2d-owner@example.test'),
  ('18000000-0000-4000-8000-000000000002', 'phase2d-worker@example.test');

insert into public.farms (
  id, slug, name, region, country_code, latitude, longitude, timezone, created_by
)
values (
  '28000000-0000-4000-8000-000000000001',
  'phase2d-farm',
  'Phase 2D Farm',
  'Test Region',
  'KR',
  35.8,
  126.8,
  'Asia/Seoul',
  '18000000-0000-4000-8000-000000000001'
);

insert into public.farm_memberships (farm_id, user_id, role)
values
  (
    '28000000-0000-4000-8000-000000000001',
    '18000000-0000-4000-8000-000000000001',
    'owner'
  ),
  (
    '28000000-0000-4000-8000-000000000001',
    '18000000-0000-4000-8000-000000000002',
    'worker'
  );

insert into public.cultivation_cycles (
  id, farm_id, crop, variety, planted_at, growth_stage, status
)
values (
  '38000000-0000-4000-8000-000000000001',
  '28000000-0000-4000-8000-000000000001',
  'tomato',
  'phase2d-cycle',
  current_date,
  'test-stage',
  'active'
);

create temporary table phase2d_clock (observed_at timestamptz not null);
insert into phase2d_clock values (date_trunc('second', now()) - interval '1 minute');
grant select on phase2d_clock to authenticated, service_role;

create temporary table phase2d_refs (
  label text primary key,
  farm_id uuid not null,
  message_id uuid not null,
  event_id uuid not null
);
grant select, insert on phase2d_refs to authenticated, service_role;

set local role authenticated;
set local request.jwt.claim.sub = '18000000-0000-4000-8000-000000000001';
set local request.jwt.claim.role = 'authenticated';

select extensions.lives_ok(
  $$
    select public.create_observation_source(
      '28000000-0000-4000-8000-000000000001',
      'PHASE2D-WEATHER',
      'Phase 2D weather source',
      'WEATHER_API',
      'phase2d-provider'
    )
  $$,
  'owner creates the weather source'
);

select extensions.lives_ok(
  $$
    select public.create_observation_stream(
      '28000000-0000-4000-8000-000000000001',
      (select id from public.observation_sources where source_code = 'PHASE2D-WEATHER'),
      'weather.temperature_c',
      'PHASE2D-TEMP-A',
      'Phase 2D temperature A'
    )
  $$,
  'owner creates the first temperature stream'
);

select extensions.lives_ok(
  $$
    select public.create_observation_stream(
      '28000000-0000-4000-8000-000000000001',
      (select id from public.observation_sources where source_code = 'PHASE2D-WEATHER'),
      'weather.temperature_c',
      'PHASE2D-TEMP-B',
      'Phase 2D temperature B'
    )
  $$,
  'owner creates the second temperature stream'
);

select extensions.lives_ok(
  $$
    select public.create_observation_stream(
      '28000000-0000-4000-8000-000000000001',
      (select id from public.observation_sources where source_code = 'PHASE2D-WEATHER'),
      'weather.humidity_pct',
      'PHASE2D-HUMIDITY',
      'Phase 2D humidity'
    )
  $$,
  'owner creates an unrelated humidity stream'
);

select extensions.lives_ok(
  $$
    select public.create_schedule_project(
      target_farm_id := '28000000-0000-4000-8000-000000000001',
      target_cycle_id := '38000000-0000-4000-8000-000000000001',
      project_code := 'PHASE2D-PROJECT',
      project_name := 'Phase 2D Project',
      project_timezone := 'Asia/Seoul',
      root_wbs_code := 'ROOT',
      root_wbs_name := 'Phase 2D Root',
      calendar_code := 'DEFAULT',
      calendar_name := 'Default Calendar',
      calendar_working_periods := jsonb_build_array(
        jsonb_build_object('weekday', 1, 'start_time', '08:00', 'end_time', '17:00')
      )
    )
  $$,
  'owner creates a schedule project'
);

select extensions.lives_ok(
  $$
    select public.create_activity_template(
      target_farm_id := '28000000-0000-4000-8000-000000000001',
      template_code := 'PHASE2D-HEAT',
      template_name := 'Phase 2D heat inspection',
      target_operation_type_code := 'environment_control',
      template_default_duration_minutes := 30
    )
  $$,
  'owner creates a trigger proposal template'
);

select extensions.lives_ok(
  $$
    select public.create_activity_trigger_rule(
      target_farm_id := '28000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'PHASE2D-PROJECT'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'PHASE2D-HEAT'
      ),
      target_wbs_id := (
        select id from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'PHASE2D-PROJECT'
        ) and wbs_code = 'ROOT'
      ),
      rule_code := 'PHASE2D-HOT',
      rule_name := 'Phase 2D hot weather',
      trigger_event_type := 'WEATHER_OBSERVATION',
      rule_status := 'ACTIVE',
      predicate_match_mode := 'ALL',
      predicate_field_codes := array['weather.temperature_c'],
      predicate_operators := array['GTE'],
      predicate_numeric_values := array[25::numeric],
      predicate_text_values := array[null::text],
      predicate_boolean_values := array[null::boolean],
      predicate_unit_codes := array['degC'],
      predicate_window_minutes := array[60]
    )
  $$,
  'owner creates an active temperature trigger rule'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      '28000000-0000-4000-8000-000000000001',
      (select id from public.observation_streams where stream_code = 'PHASE2D-TEMP-A'),
      (select observed_at from phase2d_clock),
      'phase2d:temperature:a',
      30,
      null,
      null,
      (select observed_at from phase2d_clock),
      'VALID',
      'phase2d-temp-a'
    )
  $$,
  'first temperature observation emits an event'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      '28000000-0000-4000-8000-000000000001',
      (select id from public.observation_streams where stream_code = 'PHASE2D-TEMP-B'),
      (select observed_at from phase2d_clock),
      'phase2d:temperature:b',
      31,
      null,
      null,
      (select observed_at from phase2d_clock),
      'VALID',
      'phase2d-temp-b'
    )
  $$,
  'second same-time temperature observation emits an event'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      '28000000-0000-4000-8000-000000000001',
      (select id from public.observation_streams where stream_code = 'PHASE2D-HUMIDITY'),
      (select observed_at from phase2d_clock),
      'phase2d:humidity:a',
      80,
      null,
      null,
      (select observed_at from phase2d_clock),
      'VALID',
      'phase2d-humidity-a'
    )
  $$,
  'unrelated humidity observation emits an event'
);

insert into phase2d_refs (label, farm_id, message_id, event_id)
select
  case observation.idempotency_key
    when 'phase2d:temperature:a' then 'temp-a'
    when 'phase2d:temperature:b' then 'temp-b'
    else 'humidity'
  end,
  observation.farm_id,
  message.id,
  event.id
from public.stream_observations as observation
join public.domain_events as event on event.observation_id = observation.id
join public.outbox_messages as message on message.event_id = event.id
where observation.idempotency_key in (
  'phase2d:temperature:a', 'phase2d:temperature:b', 'phase2d:humidity:a'
);

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.lives_ok(
  $$
    select public.claim_outbox_topic_messages(
      'observation.recorded.v1', 'phase2d-dispatcher', 3, 300
    )
  $$,
  'dispatcher claims the observation topic messages'
);

reset role;

select extensions.is(
  (
    select count(*)::integer from public.outbox_messages
    where farm_id = '28000000-0000-4000-8000-000000000001'
      and status = 'CLAIMED'
      and locked_by = 'phase2d-dispatcher'
  ),
  3,
  'topic claim locks all three due observation messages'
);

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.lives_ok(
  $$
    select public.consume_observation_outbox_message(
      farm_id, message_id, 'phase2d-dispatcher', 1
    ) from phase2d_refs where label = 'temp-a'
  $$,
  'first temperature event evaluates the matching rule'
);

select extensions.lives_ok(
  $$
    select public.consume_observation_outbox_message(
      farm_id, message_id, 'phase2d-dispatcher', 1
    ) from phase2d_refs where label = 'temp-b'
  $$,
  'second same-time event reuses the trigger run'
);

select extensions.lives_ok(
  $$
    select public.consume_observation_outbox_message(
      farm_id, message_id, 'phase2d-dispatcher', 1
    ) from phase2d_refs where label = 'humidity'
  $$,
  'unrelated field event completes without evaluating a rule'
);

reset role;

select extensions.ok(
  (
    select matching_rule_count = 1
      and evaluated_rule_count = 1
      and reused_rule_count = 0
      and status = 'COMPLETED'
    from public.observation_event_consumptions as consumption
    join phase2d_refs as reference on reference.event_id = consumption.event_id
    where reference.label = 'temp-a'
  ),
  'first event records one newly evaluated rule'
);

select extensions.ok(
  (
    select matching_rule_count = 1
      and evaluated_rule_count = 0
      and reused_rule_count = 1
      and status = 'COMPLETED'
    from public.observation_event_consumptions as consumption
    join phase2d_refs as reference on reference.event_id = consumption.event_id
    where reference.label = 'temp-b'
  ),
  'same-time event records one reused rule run'
);

select extensions.ok(
  (
    select matching_rule_count = 0
      and evaluated_rule_count = 0
      and reused_rule_count = 0
      and status = 'COMPLETED'
    from public.observation_event_consumptions as consumption
    join phase2d_refs as reference on reference.event_id = consumption.event_id
    where reference.label = 'humidity'
  ),
  'unrelated field records a completed zero-rule receipt'
);

select extensions.is(
  (
    select count(*)::integer from public.activity_rule_runs
    where trigger_rule_id = (
      select id from public.activity_trigger_rules where rule_code = 'PHASE2D-HOT'
    )
  ),
  1,
  'same rule version and event time create one trigger run'
);

select extensions.ok(
  (
    select created_by is null
      and execution_worker_id = 'phase2d-dispatcher'
      and status = 'SUCCEEDED'
      and outcome_code = 'PROPOSAL_CREATED'
    from public.activity_rule_runs
    where trigger_rule_id = (
      select id from public.activity_trigger_rules where rule_code = 'PHASE2D-HOT'
    )
  ),
  'service trigger run preserves the worker actor'
);

select extensions.ok(
  (
    select created_by is null
      and updated_by is null
      and created_by_worker_id = 'phase2d-dispatcher'
      and updated_by_worker_id = 'phase2d-dispatcher'
      and status = 'PROPOSED'
    from public.activity_proposals
    where rule_run_id = (
      select id from public.activity_rule_runs
      where trigger_rule_id = (
        select id from public.activity_trigger_rules where rule_code = 'PHASE2D-HOT'
      )
    )
  ),
  'service-created proposal preserves worker creator and updater'
);

select extensions.is(
  (
    select count(*)::integer
    from public.observation_event_rule_consumptions as receipt
    where receipt.rule_run_id = (
      select id from public.activity_rule_runs
      where trigger_rule_id = (
        select id from public.activity_trigger_rules where rule_code = 'PHASE2D-HOT'
      )
    )
      and receipt.dispatch_status in ('EVALUATED', 'REUSED')
  ),
  2,
  'both temperature events link to the shared trigger run'
);

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.lives_ok(
  $$
    select public.consume_observation_outbox_message(
      farm_id, message_id, 'phase2d-dispatcher', 1
    ) from phase2d_refs where label = 'temp-a'
  $$,
  'same event consumption request is idempotent'
);

reset role;

select extensions.is(
  (
    select count(*)::integer
    from public.observation_event_consumptions
    where farm_id = '28000000-0000-4000-8000-000000000001'
  ),
  3,
  'consumer retries create no duplicate consumption rows'
);

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.lives_ok(
  $$
    select public.complete_outbox_delivery(
      farm_id, message_id, 'phase2d-dispatcher', 1, true
    ) from phase2d_refs where label = 'temp-a'
  $$,
  'dispatcher publishes the first message'
);
select extensions.lives_ok(
  $$
    select public.complete_outbox_delivery(
      farm_id, message_id, 'phase2d-dispatcher', 1, true
    ) from phase2d_refs where label = 'temp-b'
  $$,
  'dispatcher publishes the reused-run message'
);
select extensions.lives_ok(
  $$
    select public.complete_outbox_delivery(
      farm_id, message_id, 'phase2d-dispatcher', 1, true
    ) from phase2d_refs where label = 'humidity'
  $$,
  'dispatcher publishes the zero-rule message'
);

reset role;

select extensions.is(
  (
    select count(*)::integer
    from public.outbox_messages as message
    join public.outbox_delivery_attempts as attempt on attempt.message_id = message.id
    where message.farm_id = '28000000-0000-4000-8000-000000000001'
      and message.status = 'PUBLISHED'
      and attempt.status = 'PUBLISHED'
  ),
  3,
  'all consumed messages and delivery attempts are published'
);

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '18000000-0000-4000-8000-000000000001';

select extensions.is(
  (select count(*)::integer from public.observation_event_consumptions),
  3,
  'farm owner can read event consumptions'
);

set local request.jwt.claim.sub = '18000000-0000-4000-8000-000000000002';

select extensions.is(
  (select count(*)::integer from public.observation_event_consumptions),
  0,
  'farm worker cannot read manager-only event consumptions'
);

select extensions.throws_ok(
  $$
    insert into public.observation_event_consumptions (
      farm_id, event_id, outbox_message_id, worker_id
    ) select farm_id, event_id, message_id, 'direct-worker'
      from phase2d_refs where label = 'temp-a'
  $$,
  '42501',
  null,
  'authenticated clients cannot directly write event consumptions'
);

set local request.jwt.claim.sub = '18000000-0000-4000-8000-000000000001';

select extensions.lives_ok(
  $$
    select public.decide_activity_proposal(
      '28000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'PHASE2D-PROJECT'),
      (select id from public.activity_proposals where status = 'PROPOSED'),
      1,
      'APPROVED',
      'MANAGER_REVIEW',
      'Approved service proposal'
    )
  $$,
  'manager approves the service-created proposal'
);

select extensions.ok(
  (
    select created_by_worker_id = 'phase2d-dispatcher'
      and updated_by = '18000000-0000-4000-8000-000000000001'::uuid
      and updated_by_worker_id is null
      and status = 'APPROVED'
    from public.activity_proposals
  ),
  'human decision replaces only the proposal update actor'
);

select extensions.ok(
  not has_function_privilege(
    'anon',
    'public.claim_outbox_topic_messages(text,text,integer,integer)',
    'EXECUTE'
  ),
  'anonymous clients cannot claim topic messages'
);

select extensions.ok(
  has_function_privilege(
    'service_role',
    'public.configure_observation_dispatch(text,text,text)',
    'EXECUTE'
  ),
  'service role can configure the dispatcher cron'
);

select extensions.is(
  (
    select count(*)::integer from public.activity_rule_runs
    where num_nonnulls(created_by, execution_worker_id) = 1
  ),
  1,
  'every Phase 2D rule run has exactly one actor'
);

select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.evaluate_activity_trigger_rule(uuid,uuid,uuid,integer,timestamptz,text)',
    'EXECUTE'
  ),
  'authenticated manager evaluation RPC remains executable'
);

select * from extensions.finish();

rollback;
