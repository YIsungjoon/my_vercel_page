begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(49);

insert into auth.users (id, email)
values
  ('13000000-0000-4000-8000-000000000001', 'phase1c-owner@example.test'),
  ('13000000-0000-4000-8000-000000000002', 'phase1c-worker@example.test');

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
values (
  '23000000-0000-4000-8000-000000000001',
  'phase1c-farm',
  'Phase 1C Farm',
  'Test Region',
  'KR',
  37.5,
  127.0,
  'Asia/Seoul',
  '13000000-0000-4000-8000-000000000001'
);

insert into public.farm_memberships (farm_id, user_id, role)
values
  (
    '23000000-0000-4000-8000-000000000001',
    '13000000-0000-4000-8000-000000000001',
    'owner'
  ),
  (
    '23000000-0000-4000-8000-000000000001',
    '13000000-0000-4000-8000-000000000002',
    'worker'
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
values (
  '33000000-0000-4000-8000-000000000001',
  '23000000-0000-4000-8000-000000000001',
  'tomato',
  'phase1c-cycle',
  current_date,
  'test-stage',
  'active'
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
    '43000000-0000-4000-8000-000000000001',
    '23000000-0000-4000-8000-000000000001',
    'GH-01',
    'Greenhouse 1',
    'greenhouse'
  ),
  (
    '43000000-0000-4000-8000-000000000002',
    '23000000-0000-4000-8000-000000000001',
    'GH-02',
    'Greenhouse 2',
    'greenhouse'
  );

set local role authenticated;
set local request.jwt.claim.sub = '13000000-0000-4000-8000-000000000001';

select extensions.lives_ok(
  $$
    select public.create_schedule_project(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_cycle_id := '33000000-0000-4000-8000-000000000001',
      project_code := 'LIFECYCLE-PROJECT',
      project_name := 'Lifecycle Project',
      project_timezone := 'Asia/Seoul',
      root_wbs_code := 'ROOT',
      root_wbs_name := 'Lifecycle Root',
      calendar_code := 'DEFAULT',
      calendar_name := 'Default Calendar',
      calendar_working_periods := jsonb_build_array(
        jsonb_build_object(
          'weekday', 1, 'start_time', '08:00', 'end_time', '17:00'
        )
      )
    )
  $$,
  'owner creates the lifecycle test project'
);

select extensions.lives_ok(
  $$
    select public.create_activity_template(
      '23000000-0000-4000-8000-000000000001',
      'USED-TEMPLATE',
      'Used template',
      'other'
    )
  $$,
  'owner creates the template used by rules'
);

select extensions.lives_ok(
  $$
    select public.create_activity_template(
      '23000000-0000-4000-8000-000000000001',
      'DISPOSABLE-TEMPLATE',
      'Disposable template',
      'other'
    )
  $$,
  'owner creates a disposable template'
);

select extensions.lives_ok(
  $$
    select public.create_activity_recurrence_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'ACTIVE-RECURRENCE',
      rule_name := 'Active recurrence',
      recurrence_frequency := 'WEEKLY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '06:00',
      rule_status := 'ACTIVE',
      recurrence_weekdays := array[1, 3]::smallint[]
    )
  $$,
  'owner creates an active recurrence rule'
);

select extensions.lives_ok(
  $$
    select public.create_activity_trigger_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'ACTIVE-TRIGGER',
      rule_name := 'Active trigger',
      trigger_event_type := 'SENSOR_OBSERVATION',
      rule_status := 'ACTIVE',
      predicate_field_codes := array['sensor.temperature_c'],
      predicate_operators := array['GTE'],
      predicate_numeric_values := array[30::numeric],
      predicate_text_values := array[null::text],
      predicate_boolean_values := array[null::boolean],
      predicate_unit_codes := array['degC'],
      predicate_window_minutes := array[15],
      target_work_area_ids := array[
        '43000000-0000-4000-8000-000000000001'::uuid
      ]
    )
  $$,
  'owner creates an active trigger rule'
);

select extensions.lives_ok(
  $$
    select public.create_activity_recurrence_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'DRAFT-RECURRENCE',
      rule_name := 'Draft recurrence',
      recurrence_frequency := 'DAILY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '07:00'
    )
  $$,
  'owner creates a draft recurrence rule'
);

select extensions.lives_ok(
  $$
    select public.create_activity_trigger_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'DRAFT-TRIGGER',
      rule_name := 'Draft trigger',
      trigger_event_type := 'MANUAL'
    )
  $$,
  'owner creates a draft trigger rule'
);

select extensions.throws_ok(
  $$
    update public.activity_templates
    set name = 'Direct update',
        version = version + 1
    where template_code = 'USED-TEMPLATE'
  $$,
  '42501',
  null,
  'authenticated managers cannot bypass template lifecycle RPCs'
);

select extensions.throws_ok(
  $$
    update public.activity_recurrence_rules
    set name = 'Direct update',
        version = version + 1
    where rule_code = 'ACTIVE-RECURRENCE'
  $$,
  '42501',
  null,
  'authenticated managers cannot bypass rule lifecycle RPCs'
);

select extensions.lives_ok(
  $$
    select public.update_activity_template(
      '23000000-0000-4000-8000-000000000001',
      (select id from public.activity_templates where template_code = 'USED-TEMPLATE'),
      1,
      'USED-TEMPLATE',
      'Used template version two',
      'other',
      'TASK_DEPENDENT',
      'DURATION',
      45,
      'Updated template',
      true
    )
  $$,
  'template update succeeds with the current version'
);

select extensions.ok(
  (
    select version = 2
      and name = 'Used template version two'
      and default_duration_minutes = 45
      and updated_by = '13000000-0000-4000-8000-000000000001'::uuid
    from public.activity_templates
    where template_code = 'USED-TEMPLATE'
  ),
  'template update increments version and records the actor'
);

select extensions.throws_ok(
  $$
    select public.update_activity_template(
      '23000000-0000-4000-8000-000000000001',
      (select id from public.activity_templates where template_code = 'USED-TEMPLATE'),
      1,
      'USED-TEMPLATE',
      'Stale update',
      'other',
      'TASK_DEPENDENT',
      'DURATION',
      45,
      null,
      true
    )
  $$,
  '40001',
  null,
  'stale template updates are rejected'
);

select extensions.throws_ok(
  $$
    select public.update_activity_template(
      '23000000-0000-4000-8000-000000000001',
      (select id from public.activity_templates where template_code = 'USED-TEMPLATE'),
      2,
      'USED-TEMPLATE',
      'Used template version two',
      'other',
      'TASK_DEPENDENT',
      'DURATION',
      45,
      'Updated template',
      false
    )
  $$,
  'P0001',
  null,
  'a template with active rules cannot be deactivated'
);

select extensions.lives_ok(
  $$
    select public.update_activity_recurrence_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_rule_id := (
        select id from public.activity_recurrence_rules where rule_code = 'ACTIVE-RECURRENCE'
      ),
      expected_version := 1,
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'ACTIVE-RECURRENCE',
      rule_name := 'Paused monthly recurrence',
      recurrence_frequency := 'MONTHLY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '06:30',
      target_calendar_id := (
        select default_calendar_id
        from public.schedule_projects
        where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_cycle_id := '33000000-0000-4000-8000-000000000001',
      rule_status := 'PAUSED',
      recurrence_interval_count := 2,
      recurrence_day_of_month := 15::smallint,
      recurrence_ends_on := current_date + 120,
      recurrence_timezone := 'Asia/Seoul',
      recurrence_weekdays := array[]::smallint[],
      generation_horizon_days := 60
    )
  $$,
  'active recurrence can transition to paused while replacing its schedule'
);

select extensions.ok(
  (
    select status = 'PAUSED'
      and frequency = 'MONTHLY'
      and day_of_month = 15
      and interval_count = 2
      and version = 2
    from public.activity_recurrence_rules
    where rule_code = 'ACTIVE-RECURRENCE'
  ),
  'recurrence update stores the replacement configuration and increments version'
);

select extensions.is(
  (
    select count(*)::integer
    from public.activity_recurrence_weekdays
    where recurrence_rule_id = (
      select id
      from public.activity_recurrence_rules
      where rule_code = 'ACTIVE-RECURRENCE'
    )
  ),
  0,
  'changing weekly recurrence to monthly removes weekday child rows'
);

select extensions.throws_ok(
  $$
    select public.update_activity_recurrence_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_rule_id := (
        select id from public.activity_recurrence_rules where rule_code = 'ACTIVE-RECURRENCE'
      ),
      expected_version := 1,
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'ACTIVE-RECURRENCE',
      rule_name := 'Stale recurrence',
      recurrence_frequency := 'MONTHLY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '06:30',
      target_calendar_id := (
        select default_calendar_id
        from public.schedule_projects
        where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_cycle_id := '33000000-0000-4000-8000-000000000001',
      rule_status := 'PAUSED',
      recurrence_interval_count := 2,
      recurrence_day_of_month := 15::smallint,
      recurrence_ends_on := current_date + 120,
      recurrence_timezone := 'Asia/Seoul',
      recurrence_weekdays := array[]::smallint[],
      generation_horizon_days := 60
    )
  $$,
  '40001',
  null,
  'stale recurrence updates are rejected'
);

select extensions.throws_ok(
  $$
    select public.update_activity_recurrence_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_rule_id := (
        select id from public.activity_recurrence_rules where rule_code = 'ACTIVE-RECURRENCE'
      ),
      expected_version := 2,
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'ACTIVE-RECURRENCE',
      rule_name := 'Invalid draft recurrence',
      recurrence_frequency := 'MONTHLY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '06:30',
      target_calendar_id := (
        select default_calendar_id
        from public.schedule_projects
        where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_cycle_id := '33000000-0000-4000-8000-000000000001',
      rule_status := 'DRAFT',
      recurrence_interval_count := 2,
      recurrence_day_of_month := 15::smallint,
      recurrence_ends_on := current_date + 120,
      recurrence_timezone := 'Asia/Seoul',
      recurrence_weekdays := array[]::smallint[],
      generation_horizon_days := 60
    )
  $$,
  'P0001',
  null,
  'paused recurrence cannot transition back to draft'
);

select extensions.lives_ok(
  $$
    select public.update_activity_trigger_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_rule_id := (
        select id from public.activity_trigger_rules where rule_code = 'ACTIVE-TRIGGER'
      ),
      expected_version := 1,
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'ACTIVE-TRIGGER',
      rule_name := 'Paused humidity trigger',
      trigger_event_type := 'SENSOR_OBSERVATION',
      target_calendar_id := (
        select default_calendar_id
        from public.schedule_projects
        where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_cycle_id := '33000000-0000-4000-8000-000000000001',
      rule_status := 'PAUSED',
      predicate_match_mode := 'ANY',
      cooldown_minutes := 90,
      valid_from := null,
      valid_until := null,
      predicate_field_codes := array['sensor.humidity_pct'],
      predicate_operators := array['GTE'],
      predicate_numeric_values := array[80::numeric],
      predicate_text_values := array[null::text],
      predicate_boolean_values := array[null::boolean],
      predicate_unit_codes := array['pct'],
      predicate_window_minutes := array[30],
      target_work_area_ids := array[
        '43000000-0000-4000-8000-000000000002'::uuid,
        '43000000-0000-4000-8000-000000000002'::uuid
      ]
    )
  $$,
  'active trigger can transition to paused while replacing child rows'
);

select extensions.ok(
  (
    select status = 'PAUSED'
      and predicate_match_mode = 'ANY'
      and cooldown_minutes = 90
      and version = 2
    from public.activity_trigger_rules
    where rule_code = 'ACTIVE-TRIGGER'
  ),
  'trigger update stores lifecycle fields and increments version'
);

select extensions.ok(
  (
    select count(*) = 1
      and min(source_field_code) = 'sensor.humidity_pct'
      and min(numeric_value) = 80
    from public.activity_trigger_predicates
    where trigger_rule_id = (
      select id from public.activity_trigger_rules where rule_code = 'ACTIVE-TRIGGER'
    )
  ),
  'trigger update atomically replaces typed predicate rows'
);

select extensions.ok(
  (
    select count(*) = 1 and bool_and(is_primary)
    from public.activity_trigger_rule_work_areas
    where trigger_rule_id = (
      select id from public.activity_trigger_rules where rule_code = 'ACTIVE-TRIGGER'
    )
  ),
  'trigger update deduplicates target areas and selects one primary row'
);

select extensions.throws_ok(
  $$
    select public.update_activity_trigger_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_rule_id := (
        select id from public.activity_trigger_rules where rule_code = 'ACTIVE-TRIGGER'
      ),
      expected_version := 1,
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'ACTIVE-TRIGGER',
      rule_name := 'Stale trigger',
      trigger_event_type := 'SENSOR_OBSERVATION',
      target_calendar_id := (
        select default_calendar_id
        from public.schedule_projects
        where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_cycle_id := '33000000-0000-4000-8000-000000000001',
      rule_status := 'PAUSED',
      predicate_match_mode := 'ANY',
      cooldown_minutes := 90,
      valid_from := null,
      valid_until := null,
      predicate_field_codes := array['sensor.humidity_pct'],
      predicate_operators := array['GTE'],
      predicate_numeric_values := array[80::numeric],
      predicate_text_values := array[null::text],
      predicate_boolean_values := array[null::boolean],
      predicate_unit_codes := array['pct'],
      predicate_window_minutes := array[30],
      target_work_area_ids := array[
        '43000000-0000-4000-8000-000000000002'::uuid
      ]
    )
  $$,
  '40001',
  null,
  'stale trigger updates are rejected'
);

select extensions.throws_ok(
  $$
    select public.update_activity_trigger_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_rule_id := (
        select id from public.activity_trigger_rules where rule_code = 'ACTIVE-TRIGGER'
      ),
      expected_version := 2,
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'ACTIVE-TRIGGER',
      rule_name := 'Invalid draft trigger',
      trigger_event_type := 'SENSOR_OBSERVATION',
      target_calendar_id := (
        select default_calendar_id
        from public.schedule_projects
        where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_cycle_id := '33000000-0000-4000-8000-000000000001',
      rule_status := 'DRAFT',
      predicate_match_mode := 'ANY',
      cooldown_minutes := 90,
      valid_from := null,
      valid_until := null,
      predicate_field_codes := array['sensor.humidity_pct'],
      predicate_operators := array['GTE'],
      predicate_numeric_values := array[80::numeric],
      predicate_text_values := array[null::text],
      predicate_boolean_values := array[null::boolean],
      predicate_unit_codes := array['pct'],
      predicate_window_minutes := array[30],
      target_work_area_ids := array[
        '43000000-0000-4000-8000-000000000002'::uuid
      ]
    )
  $$,
  'P0001',
  null,
  'paused trigger cannot transition back to draft'
);

select extensions.lives_ok(
  $$
    select public.update_activity_template(
      '23000000-0000-4000-8000-000000000001',
      (select id from public.activity_templates where template_code = 'USED-TEMPLATE'),
      2,
      'USED-TEMPLATE',
      'Used template version two',
      'other',
      'TASK_DEPENDENT',
      'DURATION',
      45,
      'Updated template',
      false
    )
  $$,
  'template can be deactivated after all active rules are paused'
);

select extensions.ok(
  (
    select not is_active and version = 3
    from public.activity_templates
    where template_code = 'USED-TEMPLATE'
  ),
  'template deactivation increments its version'
);

select extensions.throws_ok(
  $$
    select public.update_activity_recurrence_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_rule_id := (
        select id from public.activity_recurrence_rules where rule_code = 'ACTIVE-RECURRENCE'
      ),
      expected_version := 2,
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'ACTIVE-RECURRENCE',
      rule_name := 'Cannot activate',
      recurrence_frequency := 'WEEKLY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '06:30',
      target_calendar_id := (
        select default_calendar_id
        from public.schedule_projects
        where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_cycle_id := '33000000-0000-4000-8000-000000000001',
      rule_status := 'ACTIVE',
      recurrence_interval_count := 1,
      recurrence_day_of_month := null,
      recurrence_ends_on := current_date + 120,
      recurrence_timezone := 'Asia/Seoul',
      recurrence_weekdays := array[2, 4]::smallint[],
      generation_horizon_days := 60
    )
  $$,
  'P0001',
  null,
  'a paused rule cannot activate while its template is inactive'
);

select extensions.lives_ok(
  $$
    select public.update_activity_template(
      '23000000-0000-4000-8000-000000000001',
      (select id from public.activity_templates where template_code = 'USED-TEMPLATE'),
      3,
      'USED-TEMPLATE',
      'Used template version two',
      'other',
      'TASK_DEPENDENT',
      'DURATION',
      45,
      'Updated template',
      true
    )
  $$,
  'inactive template can be reactivated with the current version'
);

select extensions.lives_ok(
  $$
    select public.update_activity_recurrence_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_rule_id := (
        select id from public.activity_recurrence_rules where rule_code = 'ACTIVE-RECURRENCE'
      ),
      expected_version := 2,
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'ACTIVE-RECURRENCE',
      rule_name := 'Reactivated weekly recurrence',
      recurrence_frequency := 'WEEKLY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '06:30',
      target_calendar_id := (
        select default_calendar_id
        from public.schedule_projects
        where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_cycle_id := '33000000-0000-4000-8000-000000000001',
      rule_status := 'ACTIVE',
      recurrence_interval_count := 1,
      recurrence_day_of_month := null,
      recurrence_ends_on := current_date + 120,
      recurrence_timezone := 'Asia/Seoul',
      recurrence_weekdays := array[2, 4]::smallint[],
      generation_horizon_days := 60
    )
  $$,
  'paused recurrence can reactivate after its template is active'
);

select extensions.is(
  (
    select count(*)::integer
    from public.activity_recurrence_weekdays
    where recurrence_rule_id = (
      select id
      from public.activity_recurrence_rules
      where rule_code = 'ACTIVE-RECURRENCE'
    )
  ),
  2,
  'reactivated weekly recurrence restores replacement weekday rows'
);

select extensions.lives_ok(
  $$
    select public.update_activity_recurrence_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_rule_id := (
        select id from public.activity_recurrence_rules where rule_code = 'ACTIVE-RECURRENCE'
      ),
      expected_version := 3,
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'ACTIVE-RECURRENCE',
      rule_name := 'Archived weekly recurrence',
      recurrence_frequency := 'WEEKLY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '06:30',
      target_calendar_id := (
        select default_calendar_id
        from public.schedule_projects
        where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_cycle_id := '33000000-0000-4000-8000-000000000001',
      rule_status := 'ARCHIVED',
      recurrence_interval_count := 1,
      recurrence_day_of_month := null,
      recurrence_ends_on := current_date + 120,
      recurrence_timezone := 'Asia/Seoul',
      recurrence_weekdays := array[2, 4]::smallint[],
      generation_horizon_days := 60
    )
  $$,
  'active recurrence can be archived'
);

select extensions.throws_ok(
  $$
    select public.update_activity_recurrence_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_rule_id := (
        select id from public.activity_recurrence_rules where rule_code = 'ACTIVE-RECURRENCE'
      ),
      expected_version := 4,
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'ACTIVE-RECURRENCE',
      rule_name := 'Archived mutation',
      recurrence_frequency := 'WEEKLY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '06:30',
      target_calendar_id := (
        select default_calendar_id
        from public.schedule_projects
        where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_cycle_id := '33000000-0000-4000-8000-000000000001',
      rule_status := 'ARCHIVED',
      recurrence_interval_count := 1,
      recurrence_day_of_month := null,
      recurrence_ends_on := current_date + 120,
      recurrence_timezone := 'Asia/Seoul',
      recurrence_weekdays := array[2, 4]::smallint[],
      generation_horizon_days := 60
    )
  $$,
  'P0001',
  null,
  'archived recurrence is immutable'
);

select extensions.throws_ok(
  $$
    select public.delete_activity_recurrence_rule(
      '23000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'),
      (select id from public.activity_recurrence_rules where rule_code = 'ACTIVE-RECURRENCE'),
      4
    )
  $$,
  'P0001',
  null,
  'archived recurrence cannot be hard deleted'
);

select extensions.lives_ok(
  $$
    select public.update_activity_trigger_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_rule_id := (
        select id from public.activity_trigger_rules where rule_code = 'ACTIVE-TRIGGER'
      ),
      expected_version := 2,
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'ACTIVE-TRIGGER',
      rule_name := 'Archived humidity trigger',
      trigger_event_type := 'SENSOR_OBSERVATION',
      target_calendar_id := (
        select default_calendar_id
        from public.schedule_projects
        where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_cycle_id := '33000000-0000-4000-8000-000000000001',
      rule_status := 'ARCHIVED',
      predicate_match_mode := 'ANY',
      cooldown_minutes := 90,
      valid_from := null,
      valid_until := null,
      predicate_field_codes := array['sensor.humidity_pct'],
      predicate_operators := array['GTE'],
      predicate_numeric_values := array[80::numeric],
      predicate_text_values := array[null::text],
      predicate_boolean_values := array[null::boolean],
      predicate_unit_codes := array['pct'],
      predicate_window_minutes := array[30],
      target_work_area_ids := array[
        '43000000-0000-4000-8000-000000000002'::uuid
      ]
    )
  $$,
  'paused trigger can be archived'
);

select extensions.throws_ok(
  $$
    select public.delete_activity_trigger_rule(
      '23000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'),
      (select id from public.activity_trigger_rules where rule_code = 'ACTIVE-TRIGGER'),
      3
    )
  $$,
  'P0001',
  null,
  'archived trigger cannot be hard deleted'
);

select extensions.lives_ok(
  $$
    select public.delete_activity_recurrence_rule(
      '23000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'),
      (select id from public.activity_recurrence_rules where rule_code = 'DRAFT-RECURRENCE'),
      1
    )
  $$,
  'draft recurrence can be hard deleted'
);

select extensions.is(
  (
    select count(*)::integer
    from public.activity_recurrence_rules
    where rule_code = 'DRAFT-RECURRENCE'
  ),
  0,
  'deleted draft recurrence no longer exists'
);

select extensions.lives_ok(
  $$
    select public.delete_activity_trigger_rule(
      '23000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'),
      (select id from public.activity_trigger_rules where rule_code = 'DRAFT-TRIGGER'),
      1
    )
  $$,
  'draft trigger can be hard deleted'
);

select extensions.is(
  (
    select count(*)::integer
    from public.activity_trigger_rules
    where rule_code = 'DRAFT-TRIGGER'
  ),
  0,
  'deleted draft trigger no longer exists'
);

select extensions.throws_ok(
  $$
    select public.create_activity_recurrence_rule(
      target_farm_id := '23000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'USED-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'LIFECYCLE-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'INVALID-PAUSED-CREATE',
      rule_name := 'Invalid paused create',
      recurrence_frequency := 'DAILY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '08:00',
      rule_status := 'PAUSED'
    )
  $$,
  'P0001',
  null,
  'new rules cannot start in paused state'
);

select extensions.throws_ok(
  $$
    select public.delete_activity_template(
      '23000000-0000-4000-8000-000000000001',
      (select id
       from public.activity_templates
       where template_code = 'DISPOSABLE-TEMPLATE'),
      1
    )
  $$,
  'P0001',
  null,
  'active disposable template cannot be deleted'
);

select extensions.lives_ok(
  $$
    select public.update_activity_template(
      '23000000-0000-4000-8000-000000000001',
      (select id
       from public.activity_templates
       where template_code = 'DISPOSABLE-TEMPLATE'),
      1,
      'DISPOSABLE-TEMPLATE',
      'Disposable template',
      'other',
      'TASK_DEPENDENT',
      'DURATION',
      0,
      null,
      false
    )
  $$,
  'unreferenced template can be deactivated'
);

select extensions.lives_ok(
  $$
    select public.delete_activity_template(
      '23000000-0000-4000-8000-000000000001',
      (select id
       from public.activity_templates
       where template_code = 'DISPOSABLE-TEMPLATE'),
      2
    )
  $$,
  'inactive unreferenced template can be deleted'
);

select extensions.is(
  (
    select count(*)::integer
    from public.activity_templates
    where template_code = 'DISPOSABLE-TEMPLATE'
  ),
  0,
  'deleted disposable template no longer exists'
);

select extensions.lives_ok(
  $$
    select public.update_activity_template(
      '23000000-0000-4000-8000-000000000001',
      (select id from public.activity_templates where template_code = 'USED-TEMPLATE'),
      4,
      'USED-TEMPLATE',
      'Used template version two',
      'other',
      'TASK_DEPENDENT',
      'DURATION',
      45,
      'Updated template',
      false
    )
  $$,
  'template can deactivate after its rules are archived'
);

select extensions.throws_ok(
  $$
    select public.delete_activity_template(
      '23000000-0000-4000-8000-000000000001',
      (select id from public.activity_templates where template_code = 'USED-TEMPLATE'),
      5
    )
  $$,
  'P0001',
  null,
  'inactive template with archived rule references is retained'
);

set local request.jwt.claim.sub = '13000000-0000-4000-8000-000000000002';

select extensions.throws_ok(
  $$
    select public.update_activity_template(
      '23000000-0000-4000-8000-000000000001',
      (select id from public.activity_templates where template_code = 'USED-TEMPLATE'),
      5,
      'USED-TEMPLATE',
      'Worker update',
      'other',
      'TASK_DEPENDENT',
      'DURATION',
      45,
      null,
      false
    )
  $$,
  'P0001',
  null,
  'workers cannot call lifecycle mutation RPCs'
);

select extensions.throws_ok(
  $$
    delete from public.activity_trigger_predicates
    where trigger_rule_id = (
      select id from public.activity_trigger_rules where rule_code = 'ACTIVE-TRIGGER'
    )
  $$,
  '42501',
  null,
  'authenticated clients cannot directly mutate rule child rows'
);

select extensions.is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and data_type in ('json', 'jsonb')
  ),
  0,
  'lifecycle implementation adds no JSON or JSONB persistence columns'
);

reset role;

select * from extensions.finish();

rollback;
