begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(40);

select extensions.has_table('public', 'activity_templates', 'activity templates table exists');
select extensions.has_table(
  'public',
  'activity_recurrence_rules',
  'activity recurrence rules table exists'
);
select extensions.has_table(
  'public',
  'activity_recurrence_weekdays',
  'recurrence weekdays use a relational child table'
);
select extensions.has_table(
  'public',
  'activity_trigger_rules',
  'activity trigger rules table exists'
);
select extensions.has_table(
  'public',
  'activity_trigger_predicates',
  'trigger predicates use a relational child table'
);
select extensions.has_table(
  'public',
  'activity_trigger_rule_work_areas',
  'trigger target areas use a relational link table'
);

select extensions.is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'activity_templates',
        'activity_recurrence_rules',
        'activity_recurrence_weekdays',
        'activity_trigger_rules',
        'activity_trigger_predicates',
        'activity_trigger_rule_work_areas'
      )
      and data_type in ('json', 'jsonb')
  ),
  0,
  'phase 1B tables contain no JSON or JSONB persistence columns'
);

insert into auth.users (id, email)
values
  ('12000000-0000-4000-8000-000000000001', 'phase1b-owner@example.test'),
  ('12000000-0000-4000-8000-000000000002', 'phase1b-worker@example.test'),
  ('12000000-0000-4000-8000-000000000003', 'phase1b-outsider@example.test');

insert into public.farms (
  id,
  slug,
  name,
  region,
  country_code,
  latitude,
  longitude,
  timezone,
  created_by
)
values
  (
    '22000000-0000-4000-8000-000000000001',
    'phase1b-farm-one',
    'Phase 1B Farm One',
    'Test Region',
    'KR',
    37.5,
    127.0,
    'Asia/Seoul',
    '12000000-0000-4000-8000-000000000001'
  ),
  (
    '22000000-0000-4000-8000-000000000002',
    'phase1b-farm-two',
    'Phase 1B Farm Two',
    'Test Region',
    'KR',
    36.5,
    128.0,
    'Asia/Seoul',
    '12000000-0000-4000-8000-000000000001'
  );

insert into public.farm_memberships (farm_id, user_id, role)
values
  (
    '22000000-0000-4000-8000-000000000001',
    '12000000-0000-4000-8000-000000000001',
    'owner'
  ),
  (
    '22000000-0000-4000-8000-000000000001',
    '12000000-0000-4000-8000-000000000002',
    'worker'
  ),
  (
    '22000000-0000-4000-8000-000000000002',
    '12000000-0000-4000-8000-000000000001',
    'owner'
  );

insert into public.cultivation_cycles (
  id,
  farm_id,
  crop,
  variety,
  planted_at,
  growth_stage,
  status
)
values
  (
    '32000000-0000-4000-8000-000000000001',
    '22000000-0000-4000-8000-000000000001',
    'tomato',
    'cycle-one',
    current_date,
    'test-stage',
    'active'
  ),
  (
    '32000000-0000-4000-8000-000000000002',
    '22000000-0000-4000-8000-000000000001',
    'tomato',
    'cycle-two',
    current_date + 90,
    'test-stage',
    'planned'
  );

insert into public.farm_work_areas (
  id,
  farm_id,
  code,
  name,
  area_type
)
values
  (
    '42000000-0000-4000-8000-000000000001',
    '22000000-0000-4000-8000-000000000001',
    'GH-01',
    'Greenhouse 1',
    'greenhouse'
  ),
  (
    '42000000-0000-4000-8000-000000000002',
    '22000000-0000-4000-8000-000000000001',
    'GH-02',
    'Greenhouse 2',
    'greenhouse'
  ),
  (
    '42000000-0000-4000-8000-000000000003',
    '22000000-0000-4000-8000-000000000002',
    'OTHER-01',
    'Other Farm Area',
    'greenhouse'
  );

set local role authenticated;
set local request.jwt.claim.sub = '12000000-0000-4000-8000-000000000001';

select extensions.lives_ok(
  $$
    select public.create_schedule_project(
      target_farm_id := '22000000-0000-4000-8000-000000000001',
      target_cycle_id := '32000000-0000-4000-8000-000000000001',
      project_code := 'RULE-PROJECT-01',
      project_name := 'Rule Project One',
      project_timezone := 'Asia/Seoul',
      root_wbs_code := 'ROOT',
      root_wbs_name := 'Rule Root One',
      calendar_code := 'DEFAULT',
      calendar_name := 'Default Calendar',
      calendar_working_periods := jsonb_build_array(
        jsonb_build_object(
          'weekday', 1, 'start_time', '08:00', 'end_time', '17:00'
        )
      )
    )
  $$,
  'owner creates the first rule project'
);

select extensions.lives_ok(
  $$
    select public.create_schedule_project(
      target_farm_id := '22000000-0000-4000-8000-000000000001',
      target_cycle_id := '32000000-0000-4000-8000-000000000002',
      project_code := 'RULE-PROJECT-02',
      project_name := 'Rule Project Two',
      project_timezone := 'Asia/Seoul',
      root_wbs_code := 'ROOT',
      root_wbs_name := 'Rule Root Two',
      calendar_code := 'DEFAULT',
      calendar_name := 'Default Calendar',
      calendar_working_periods := jsonb_build_array(
        jsonb_build_object(
          'weekday', 2, 'start_time', '08:00', 'end_time', '17:00'
        )
      )
    )
  $$,
  'owner creates a second project for cross-project checks'
);

select extensions.lives_ok(
  $$
    select public.create_activity_template(
      target_farm_id := '22000000-0000-4000-8000-000000000001',
      template_code := 'IRRIGATION-BASE',
      template_name := 'Irrigation template',
      target_operation_type_code := 'irrigation_fertigation',
      template_default_duration_minutes := 30
    )
  $$,
  'owner creates an activity template'
);

select extensions.is(
  (
    select created_by
    from public.activity_templates
    where template_code = 'IRRIGATION-BASE'
  ),
  '12000000-0000-4000-8000-000000000001'::uuid,
  'activity template records the authenticated actor'
);

select extensions.lives_ok(
  $$
    select public.create_activity_recurrence_rule(
      target_farm_id := '22000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'IRRIGATION-BASE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'WEEKLY-IRRIGATION',
      rule_name := 'Weekly irrigation',
      recurrence_frequency := 'WEEKLY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '06:00',
      rule_status := 'ACTIVE',
      recurrence_weekdays := array[1, 3, 3]::smallint[]
    )
  $$,
  'owner creates an active weekly recurrence rule atomically'
);

select extensions.is(
  (
    select count(*)::integer
    from public.activity_recurrence_weekdays
    where recurrence_rule_id = (
      select id
      from public.activity_recurrence_rules
      where rule_code = 'WEEKLY-IRRIGATION'
    )
  ),
  2,
  'weekly recurrence weekdays are normalized and deduplicated'
);

select extensions.ok(
  (
    select
      recurrence.calendar_id = project.default_calendar_id
      and recurrence.cultivation_cycle_id = project.cultivation_cycle_id
      and recurrence.timezone = project.timezone
    from public.activity_recurrence_rules as recurrence
    join public.schedule_projects as project on project.id = recurrence.project_id
    where recurrence.rule_code = 'WEEKLY-IRRIGATION'
  ),
  'recurrence rule inherits project calendar, cycle, and timezone'
);

select extensions.throws_ok(
  $$
    select public.create_activity_recurrence_rule(
      target_farm_id := '22000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'IRRIGATION-BASE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'WEEKLY-NO-DAY',
      rule_name := 'Invalid weekly rule',
      recurrence_frequency := 'WEEKLY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '06:00'
    )
  $$,
  'P0001',
  null,
  'weekly recurrence creation requires a weekday'
);

select extensions.throws_ok(
  $$
    select public.create_activity_recurrence_rule(
      target_farm_id := '22000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'IRRIGATION-BASE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'DAILY-WITH-DAY',
      rule_name := 'Invalid daily rule',
      recurrence_frequency := 'DAILY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '06:00',
      recurrence_weekdays := array[1]::smallint[]
    )
  $$,
  'P0001',
  null,
  'non-weekly recurrence creation rejects weekdays'
);

select extensions.throws_ok(
  $$
    select public.create_activity_recurrence_rule(
      target_farm_id := '22000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'IRRIGATION-BASE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'MONTHLY-NO-DAY',
      rule_name := 'Invalid monthly rule',
      recurrence_frequency := 'MONTHLY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '06:00'
    )
  $$,
  'P0001',
  null,
  'monthly recurrence creation requires a day of month'
);

select extensions.throws_ok(
  $$
    select public.create_activity_recurrence_rule(
      target_farm_id := '22000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'IRRIGATION-BASE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'RULE-PROJECT-02'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'CROSS-PROJECT-WBS',
      rule_name := 'Invalid WBS project',
      recurrence_frequency := 'DAILY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '06:00'
    )
  $$,
  'P0001',
  null,
  'recurrence rules cannot use a WBS from another project'
);

select extensions.lives_ok(
  $$
    select public.create_activity_recurrence_rule(
      target_farm_id := '22000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'IRRIGATION-BASE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'DAILY-IRRIGATION',
      rule_name := 'Daily irrigation',
      recurrence_frequency := 'DAILY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '07:00'
    )
  $$,
  'owner creates a daily recurrence rule'
);

reset role;

select extensions.throws_ok(
  $$
    insert into public.activity_recurrence_weekdays (
      farm_id,
      project_id,
      recurrence_rule_id,
      weekday
    )
    select farm_id, project_id, id, 2
    from public.activity_recurrence_rules
    where rule_code = 'DAILY-IRRIGATION'
  $$,
  'P0001',
  null,
  'direct weekday rows are rejected for non-weekly rules'
);

set local role authenticated;
set local request.jwt.claim.sub = '12000000-0000-4000-8000-000000000001';

select extensions.lives_ok(
  $$
    select public.create_activity_trigger_rule(
      target_farm_id := '22000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'IRRIGATION-BASE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'WEATHER-IRRIGATION',
      rule_name := 'Weather irrigation trigger',
      trigger_event_type := 'WEATHER_OBSERVATION',
      rule_status := 'ACTIVE',
      predicate_match_mode := 'ALL',
      cooldown_minutes := 120,
      predicate_field_codes := array['weather.rainfall_mm', 'weather.temperature_c'],
      predicate_operators := array['LT', 'GTE'],
      predicate_numeric_values := array[5::numeric, 30::numeric],
      predicate_text_values := array[null::text, null::text],
      predicate_boolean_values := array[null::boolean, null::boolean],
      predicate_unit_codes := array['mm', 'degC'],
      predicate_window_minutes := array[1440, 60],
      target_work_area_ids := array[
        '42000000-0000-4000-8000-000000000001'::uuid,
        '42000000-0000-4000-8000-000000000002'::uuid
      ]
    )
  $$,
  'owner creates an active trigger with relational predicates and targets'
);

select extensions.is(
  (
    select count(*)::integer
    from public.activity_trigger_predicates
    where trigger_rule_id = (
      select id from public.activity_trigger_rules where rule_code = 'WEATHER-IRRIGATION'
    )
  ),
  2,
  'trigger predicates are stored as child rows'
);

select extensions.ok(
  (
    select numeric_value = 5
      and text_value is null
      and boolean_value is null
      and unit_code = 'mm'
    from public.activity_trigger_predicates
    where trigger_rule_id = (
      select id from public.activity_trigger_rules where rule_code = 'WEATHER-IRRIGATION'
    )
      and sequence_no = 1
  ),
  'trigger predicate keeps one typed numeric value and its unit'
);

select extensions.is(
  (
    select count(*)::integer
    from public.activity_trigger_rule_work_areas
    where trigger_rule_id = (
      select id from public.activity_trigger_rules where rule_code = 'WEATHER-IRRIGATION'
    )
  ),
  2,
  'trigger target work areas are stored as link rows'
);

select extensions.is(
  (
    select count(*)::integer
    from public.activity_trigger_rule_work_areas
    where trigger_rule_id = (
      select id from public.activity_trigger_rules where rule_code = 'WEATHER-IRRIGATION'
    )
      and is_primary
  ),
  1,
  'trigger rule has exactly one primary target area'
);

reset role;

create function pg_temp.remove_active_recurrence_weekdays(target_rule_id uuid)
returns void
language plpgsql
as $$
begin
  delete from public.activity_recurrence_weekdays
  where recurrence_rule_id = target_rule_id;
  set constraints all immediate;
end;
$$;

select extensions.throws_ok(
  $$
    select pg_temp.remove_active_recurrence_weekdays(
      (select id
       from public.activity_recurrence_rules
       where rule_code = 'WEEKLY-IRRIGATION')
    )
  $$,
  'P0001',
  null,
  'an active weekly rule cannot lose its last weekday'
);

set constraints all deferred;

create function pg_temp.remove_active_trigger_predicates(target_rule_id uuid)
returns void
language plpgsql
as $$
begin
  delete from public.activity_trigger_predicates
  where trigger_rule_id = target_rule_id;
  set constraints all immediate;
end;
$$;

select extensions.throws_ok(
  $$
    select pg_temp.remove_active_trigger_predicates(
      (select id
       from public.activity_trigger_rules
       where rule_code = 'WEATHER-IRRIGATION')
    )
  $$,
  'P0001',
  null,
  'an active non-manual trigger cannot lose its last predicate'
);

set constraints all deferred;

set local role authenticated;
set local request.jwt.claim.sub = '12000000-0000-4000-8000-000000000001';

select extensions.throws_ok(
  $$
    select public.create_activity_trigger_rule(
      target_farm_id := '22000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'IRRIGATION-BASE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'ACTIVE-NO-PREDICATE',
      rule_name := 'Invalid active trigger',
      trigger_event_type := 'SENSOR_OBSERVATION',
      rule_status := 'ACTIVE'
    )
  $$,
  'P0001',
  null,
  'active non-manual trigger creation requires a predicate'
);

select extensions.throws_ok(
  $$
    select public.create_activity_trigger_rule(
      target_farm_id := '22000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'IRRIGATION-BASE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'MISMATCHED-PREDICATES',
      rule_name := 'Invalid arrays',
      trigger_event_type := 'SENSOR_OBSERVATION',
      predicate_field_codes := array['sensor.temperature_c'],
      predicate_operators := array[]::text[]
    )
  $$,
  'P0001',
  null,
  'trigger predicate arrays must have equal cardinality'
);

select extensions.throws_ok(
  $$
    select public.create_activity_trigger_rule(
      target_farm_id := '22000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'IRRIGATION-BASE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'TWO-TYPED-VALUES',
      rule_name := 'Invalid typed values',
      trigger_event_type := 'SENSOR_OBSERVATION',
      predicate_field_codes := array['sensor.temperature_c'],
      predicate_operators := array['GTE'],
      predicate_numeric_values := array[30::numeric],
      predicate_text_values := array['thirty'],
      predicate_boolean_values := array[null::boolean],
      predicate_unit_codes := array['degC'],
      predicate_window_minutes := array[15]
    )
  $$,
  'P0001',
  null,
  'each predicate accepts exactly one typed comparison value'
);

select extensions.throws_ok(
  $$
    select public.create_activity_trigger_rule(
      target_farm_id := '22000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'IRRIGATION-BASE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'RULE-PROJECT-01'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'CROSS-FARM-AREA',
      rule_name := 'Invalid target area',
      trigger_event_type := 'MANUAL',
      target_work_area_ids := array[
        '42000000-0000-4000-8000-000000000003'::uuid
      ]
    )
  $$,
  'P0001',
  null,
  'trigger rules reject target areas from another farm'
);

reset role;

select extensions.throws_ok(
  $$
    insert into public.activity_trigger_predicates (
      farm_id,
      project_id,
      trigger_rule_id,
      sequence_no,
      source_field_code,
      comparison_operator,
      numeric_value,
      text_value
    )
    select farm_id, project_id, id, 99, 'sensor.invalid', 'EQ', 1, 'one'
    from public.activity_trigger_rules
    where rule_code = 'WEATHER-IRRIGATION'
  $$,
  '23514',
  null,
  'direct predicate writes enforce one typed comparison value'
);

set local role authenticated;
set local request.jwt.claim.sub = '12000000-0000-4000-8000-000000000002';

select extensions.is(
  (select count(*)::integer from public.activity_templates),
  1,
  'worker farm members can read activity templates'
);

select extensions.is(
  (select count(*)::integer from public.activity_recurrence_rules),
  2,
  'worker farm members can read recurrence rules'
);

select extensions.is(
  (select count(*)::integer from public.activity_trigger_rules),
  1,
  'worker farm members can read trigger rules'
);

select extensions.throws_ok(
  $$
    select public.create_activity_template(
      '22000000-0000-4000-8000-000000000001',
      'WORKER-TEMPLATE',
      'Worker template',
      'other'
    )
  $$,
  'P0001',
  null,
  'workers cannot create activity templates'
);

set local request.jwt.claim.sub = '12000000-0000-4000-8000-000000000003';

select extensions.is(
  (select count(*)::integer from public.activity_templates),
  0,
  'non-members cannot read activity templates'
);

select extensions.is(
  (select count(*)::integer from public.activity_recurrence_rules),
  0,
  'non-members cannot read recurrence rules'
);

select extensions.is(
  (select count(*)::integer from public.activity_trigger_rules),
  0,
  'non-members cannot read trigger rules'
);

select extensions.throws_ok(
  $$truncate table public.activity_trigger_rules$$,
  '42501',
  null,
  'authenticated users cannot bypass trigger rule RLS with truncate'
);

reset role;

select * from extensions.finish();

rollback;
