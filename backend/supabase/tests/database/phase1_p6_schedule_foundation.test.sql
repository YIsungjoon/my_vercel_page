begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(38);

select extensions.has_table('public', 'schedule_projects', 'schedule projects table exists');
select extensions.has_table('public', 'schedule_calendars', 'schedule calendars table exists');
select extensions.has_table(
  'public',
  'schedule_calendar_working_periods',
  'calendar working periods table exists'
);
select extensions.has_table(
  'public',
  'schedule_calendar_exceptions',
  'calendar exceptions table exists'
);
select extensions.has_table('public', 'schedule_wbs_nodes', 'WBS table exists');
select extensions.has_table('public', 'schedule_activities', 'activities table exists');
select extensions.has_table(
  'public',
  'schedule_activity_work_areas',
  'activity work areas table exists'
);
select extensions.has_table(
  'public',
  'schedule_activity_relationships',
  'activity relationships table exists'
);
select extensions.has_table(
  'public',
  'task_activity_links',
  'task activity compatibility links table exists'
);

select extensions.is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'schedule_activities'
      and column_name in (
        'early_start_at',
        'early_finish_at',
        'late_start_at',
        'late_finish_at',
        'total_float_minutes',
        'free_float_minutes',
        'is_critical',
        'current_start_at',
        'current_finish_at'
      )
  ),
  0,
  'calculated schedule results are not stored in the activity input ledger'
);

insert into auth.users (id, email)
values
  ('11000000-0000-4000-8000-000000000001', 'phase1-owner@example.test'),
  ('11000000-0000-4000-8000-000000000002', 'phase1-worker@example.test'),
  ('11000000-0000-4000-8000-000000000003', 'phase1-outsider@example.test');

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
    '21000000-0000-4000-8000-000000000001',
    'phase1-farm-one',
    'Phase 1 Farm One',
    'Test Region',
    'KR',
    37.5,
    127.0,
    'Asia/Seoul',
    '11000000-0000-4000-8000-000000000001'
  ),
  (
    '21000000-0000-4000-8000-000000000002',
    'phase1-farm-two',
    'Phase 1 Farm Two',
    'Test Region',
    'KR',
    36.5,
    128.0,
    'Asia/Seoul',
    '11000000-0000-4000-8000-000000000001'
  );

insert into public.farm_memberships (farm_id, user_id, role)
values
  (
    '21000000-0000-4000-8000-000000000001',
    '11000000-0000-4000-8000-000000000001',
    'owner'
  ),
  (
    '21000000-0000-4000-8000-000000000001',
    '11000000-0000-4000-8000-000000000002',
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
values
  (
    '31000000-0000-4000-8000-000000000001',
    '21000000-0000-4000-8000-000000000001',
    'tomato',
    'cycle-one',
    current_date,
    '영양생장기',
    'active'
  ),
  (
    '31000000-0000-4000-8000-000000000002',
    '21000000-0000-4000-8000-000000000001',
    'tomato',
    'cycle-two',
    current_date + 100,
    '육묘기',
    'planned'
  ),
  (
    '31000000-0000-4000-8000-000000000003',
    '21000000-0000-4000-8000-000000000002',
    'paprika',
    'other-farm',
    current_date,
    '영양생장기',
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
    '41000000-0000-4000-8000-000000000001',
    '21000000-0000-4000-8000-000000000001',
    'GH-01',
    'Greenhouse 1',
    'greenhouse'
  ),
  (
    '41000000-0000-4000-8000-000000000002',
    '21000000-0000-4000-8000-000000000001',
    'GH-02',
    'Greenhouse 2',
    'greenhouse'
  );

insert into public.tasks (
  id,
  farm_id,
  cultivation_cycle_id,
  title,
  scheduled_date,
  category
)
values (
  '51000000-0000-4000-8000-000000000001',
  '21000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000001',
  'Legacy phase 1 task',
  current_date,
  '환경관리'
);

set local role authenticated;
set local request.jwt.claim.sub = '11000000-0000-4000-8000-000000000001';

select extensions.lives_ok(
  $$
    select public.create_schedule_project(
      target_farm_id := '21000000-0000-4000-8000-000000000001',
      target_cycle_id := '31000000-0000-4000-8000-000000000001',
      project_code := 'P6-CYCLE-01',
      project_name := 'Phase 1 Cycle One',
      project_timezone := 'Asia/Seoul',
      root_wbs_code := 'ROOT',
      root_wbs_name := 'Cycle One Root',
      calendar_code := 'DEFAULT',
      calendar_name := 'Default Calendar',
      calendar_working_periods := jsonb_build_array(
        jsonb_build_object(
          'weekday', 1, 'start_time', '08:00', 'end_time', '12:00'
        ),
        jsonb_build_object(
          'weekday', 1, 'start_time', '13:00', 'end_time', '17:00'
        )
      )
    )
  $$,
  'owner creates project, default calendar, periods, and root WBS atomically'
);

select extensions.is(
  (
    select count(*)::integer
    from public.schedule_wbs_nodes
    where project_id = (
      select id from public.schedule_projects where project_code = 'P6-CYCLE-01'
    )
      and parent_id is null
  ),
  1,
  'project has exactly one root WBS'
);

select extensions.ok(
  (
    select default_calendar_id is not null
    from public.schedule_projects
    where project_code = 'P6-CYCLE-01'
  ),
  'project has a default calendar'
);

select extensions.is(
  (
    select count(*)::integer
    from public.schedule_calendar_working_periods
    where project_id = (
      select id from public.schedule_projects where project_code = 'P6-CYCLE-01'
    )
  ),
  2,
  'project creation stores all working periods'
);

select extensions.throws_ok(
  $$
    insert into public.schedule_calendar_working_periods (
      farm_id,
      project_id,
      calendar_id,
      weekday,
      start_time,
      end_time
    )
    select
      farm_id,
      id,
      default_calendar_id,
      1,
      '11:00',
      '14:00'
    from public.schedule_projects
    where project_code = 'P6-CYCLE-01'
  $$,
  'P0001',
  null,
  'overlapping calendar periods are rejected'
);

select extensions.throws_ok(
  $$
    insert into public.schedule_wbs_nodes (
      farm_id,
      project_id,
      parent_id,
      wbs_code,
      name,
      created_by
    )
    select
      farm_id,
      id,
      null,
      'SECOND-ROOT',
      'Second Root',
      '11000000-0000-4000-8000-000000000001'
    from public.schedule_projects
    where project_code = 'P6-CYCLE-01'
  $$,
  '23505',
  null,
  'a second project root WBS is rejected'
);

select extensions.lives_ok(
  $$
    select public.create_schedule_wbs_node(
      '21000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'P6-CYCLE-01'),
      (
        select id
        from public.schedule_wbs_nodes
        where wbs_code = 'ROOT'
          and project_id = (
            select id from public.schedule_projects where project_code = 'P6-CYCLE-01'
          )
      ),
      'GH.10',
      'Facility preparation',
      null,
      10
    )
  $$,
  'owner creates a child WBS'
);

select extensions.lives_ok(
  $$
    select public.create_schedule_wbs_node(
      '21000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'P6-CYCLE-01'),
      (
        select id
        from public.schedule_wbs_nodes
        where wbs_code = 'GH.10'
          and project_id = (
            select id from public.schedule_projects where project_code = 'P6-CYCLE-01'
          )
      ),
      'GH.10.10',
      'Cleaning',
      null,
      10
    )
  $$,
  'owner creates a grandchild WBS'
);

select extensions.throws_ok(
  $$
    update public.schedule_wbs_nodes
    set parent_id = (
      select id
      from public.schedule_wbs_nodes
      where wbs_code = 'GH.10.10'
        and project_id = (
          select id from public.schedule_projects where project_code = 'P6-CYCLE-01'
        )
    )
    where wbs_code = 'GH.10'
      and project_id = (
        select id from public.schedule_projects where project_code = 'P6-CYCLE-01'
      )
  $$,
  'P0001',
  null,
  'a WBS hierarchy cycle is rejected'
);

select extensions.lives_ok(
  $$
    select public.create_schedule_activity(
      target_farm_id := '21000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'P6-CYCLE-01'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where wbs_code = 'GH.10'
          and project_id = (
            select id from public.schedule_projects where project_code = 'P6-CYCLE-01'
          )
      ),
      activity_code := 'ACT-A',
      activity_name := 'Prepare greenhouse',
      activity_type := 'TASK_DEPENDENT',
      target_operation_type_code := 'environment_control',
      activity_planned_duration_minutes := 120,
      target_work_area_ids := array[
        '41000000-0000-4000-8000-000000000001'::uuid
      ],
      target_task_id := '51000000-0000-4000-8000-000000000001',
      task_link_type := 'MIGRATED'
    )
  $$,
  'owner creates an activity with farm context and a legacy task link'
);

select extensions.is(
  (
    select cultivation_cycle_id
    from public.schedule_activities
    where activity_code = 'ACT-A'
  ),
  '31000000-0000-4000-8000-000000000001'::uuid,
  'activity inherits the project cultivation cycle'
);

select extensions.is(
  (
    select count(*)::integer
    from public.schedule_activity_work_areas
    where activity_id = (
      select id from public.schedule_activities where activity_code = 'ACT-A'
    )
  ),
  1,
  'activity stores its work area link'
);

select extensions.is(
  (
    select count(*)::integer
    from public.task_activity_links
    where task_id = '51000000-0000-4000-8000-000000000001'
      and activity_id = (
        select id from public.schedule_activities where activity_code = 'ACT-A'
      )
  ),
  1,
  'activity creation stores the compatibility task link'
);

select extensions.is(
  (
    select created_by
    from public.task_activity_links
    where task_id = '51000000-0000-4000-8000-000000000001'
  ),
  '11000000-0000-4000-8000-000000000001'::uuid,
  'task activity link records the authenticated actor'
);

select extensions.lives_ok(
  $$
    select public.create_schedule_activity(
      target_farm_id := '21000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'P6-CYCLE-01'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where wbs_code = 'GH.10.10'
          and project_id = (
            select id from public.schedule_projects where project_code = 'P6-CYCLE-01'
          )
      ),
      activity_code := 'ACT-B',
      activity_name := 'Clean greenhouse',
      activity_type := 'TASK_DEPENDENT',
      target_operation_type_code := 'other',
      activity_planned_duration_minutes := 180
    )
  $$,
  'owner creates a second activity'
);

select extensions.lives_ok(
  $$
    select public.create_schedule_relationship(
      '21000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'P6-CYCLE-01'),
      (select id from public.schedule_activities where activity_code = 'ACT-A'),
      (select id from public.schedule_activities where activity_code = 'ACT-B'),
      'FS',
      30
    )
  $$,
  'owner creates an FS relationship with lag'
);

select extensions.is(
  (
    select relationship_type
    from public.schedule_activity_relationships
    where predecessor_activity_id = (
      select id from public.schedule_activities where activity_code = 'ACT-A'
    )
  ),
  'FS',
  'relationship type is stored as a stable P6 code'
);

select extensions.throws_ok(
  $$
    select public.create_schedule_relationship(
      '21000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'P6-CYCLE-01'),
      (select id from public.schedule_activities where activity_code = 'ACT-B'),
      (select id from public.schedule_activities where activity_code = 'ACT-A'),
      'FS',
      0
    )
  $$,
  'P0001',
  null,
  'a relationship network cycle is rejected'
);

select extensions.throws_ok(
  $$
    select public.create_schedule_relationship(
      '21000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'P6-CYCLE-01'),
      (select id from public.schedule_activities where activity_code = 'ACT-A'),
      (select id from public.schedule_activities where activity_code = 'ACT-A'),
      'FS',
      0
    )
  $$,
  'P0001',
  null,
  'a self relationship is rejected'
);

select extensions.lives_ok(
  $$
    select public.create_schedule_project(
      target_farm_id := '21000000-0000-4000-8000-000000000001',
      target_cycle_id := '31000000-0000-4000-8000-000000000002',
      project_code := 'P6-CYCLE-02',
      project_name := 'Phase 1 Cycle Two',
      project_timezone := 'Asia/Seoul',
      root_wbs_code := 'ROOT',
      root_wbs_name := 'Cycle Two Root',
      calendar_code := 'DEFAULT',
      calendar_name := 'Default Calendar',
      calendar_working_periods := jsonb_build_array(
        jsonb_build_object(
          'weekday', 2, 'start_time', '08:00', 'end_time', '17:00'
        )
      )
    )
  $$,
  'owner creates a second schedule project for another cycle'
);

select extensions.lives_ok(
  $$
    select public.create_schedule_activity(
      target_farm_id := '21000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'P6-CYCLE-02'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where wbs_code = 'ROOT'
          and project_id = (
            select id from public.schedule_projects where project_code = 'P6-CYCLE-02'
          )
      ),
      activity_code := 'ACT-C',
      activity_name := 'Second cycle activity',
      activity_type := 'TASK_DEPENDENT',
      activity_planned_duration_minutes := 60
    )
  $$,
  'owner creates an activity in the second project'
);

select extensions.throws_ok(
  $$
    select public.create_schedule_activity(
      target_farm_id := '21000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'P6-CYCLE-01'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where wbs_code = 'ROOT'
          and project_id = (
            select id from public.schedule_projects where project_code = 'P6-CYCLE-02'
          )
      ),
      activity_code := 'CROSS-WBS',
      activity_name := 'Cross project WBS',
      activity_type := 'TASK_DEPENDENT'
    )
  $$,
  'P0001',
  null,
  'an activity cannot use a WBS from another project'
);

select extensions.throws_ok(
  $$
    select public.create_schedule_relationship(
      '21000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'P6-CYCLE-01'),
      (select id from public.schedule_activities where activity_code = 'ACT-A'),
      (select id from public.schedule_activities where activity_code = 'ACT-C'),
      'FS',
      0
    )
  $$,
  'P0001',
  null,
  'activities from different projects cannot be related'
);

select extensions.throws_ok(
  $$
    select public.link_task_to_activity(
      '21000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'P6-CYCLE-02'),
      '51000000-0000-4000-8000-000000000001',
      (select id from public.schedule_activities where activity_code = 'ACT-C'),
      'REFERENCE',
      false
    )
  $$,
  'P0001',
  null,
  'task and activity links reject different cultivation cycles'
);

set local request.jwt.claim.sub = '11000000-0000-4000-8000-000000000002';

select extensions.is(
  (select count(*)::integer from public.schedule_projects),
  2,
  'worker farm members can read schedule projects'
);

select extensions.throws_ok(
  $$
    select public.create_schedule_wbs_node(
      '21000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'P6-CYCLE-01'),
      (
        select id
        from public.schedule_wbs_nodes
        where wbs_code = 'ROOT'
          and project_id = (
            select id from public.schedule_projects where project_code = 'P6-CYCLE-01'
          )
      ),
      'WORKER-WBS',
      'Worker must not create',
      null,
      99
    )
  $$,
  'P0001',
  null,
  'worker cannot change the schedule structure'
);

set local request.jwt.claim.sub = '11000000-0000-4000-8000-000000000003';

select extensions.is(
  (select count(*)::integer from public.schedule_projects),
  0,
  'non-members cannot read schedule projects'
);

select extensions.throws_ok(
  $$truncate table public.schedule_projects$$,
  '42501',
  null,
  'authenticated users cannot bypass schedule RLS with truncate'
);

reset role;

select * from extensions.finish();

rollback;
