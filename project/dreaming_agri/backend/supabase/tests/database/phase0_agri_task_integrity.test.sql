begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(24);

select extensions.has_table(
  'public',
  'agri_operation_types',
  'agricultural operation types table exists'
);
select extensions.has_table(
  'public',
  'farm_work_areas',
  'farm work areas table exists'
);
select extensions.has_table(
  'public',
  'cultivation_cycle_areas',
  'cultivation cycle area links table exists'
);
select extensions.has_table(
  'public',
  'task_work_areas',
  'task work area links table exists'
);
select extensions.has_column(
  'public',
  'tasks',
  'cultivation_cycle_id',
  'tasks carry cultivation cycle context'
);
select extensions.has_column(
  'public',
  'tasks',
  'operation_type_code',
  'tasks carry a stable operation code'
);
select extensions.has_column(
  'public',
  'task_logs',
  'actor_id',
  'task logs identify the actor'
);
select extensions.is(
  (select count(*)::integer from public.agri_operation_types),
  6,
  'six baseline agricultural operation types are seeded'
);

insert into auth.users (id, email)
values
  ('10000000-0000-4000-8000-000000000001', 'phase0-owner@example.test'),
  ('10000000-0000-4000-8000-000000000002', 'phase0-outsider@example.test');

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
    '20000000-0000-4000-8000-000000000001',
    'phase0-farm-one',
    'Phase 0 Farm One',
    'Test Region',
    'KR',
    37.5,
    127.0,
    'Asia/Seoul',
    '10000000-0000-4000-8000-000000000001'
  ),
  (
    '20000000-0000-4000-8000-000000000002',
    'phase0-farm-two',
    'Phase 0 Farm Two',
    'Test Region',
    'KR',
    36.5,
    128.0,
    'Asia/Seoul',
    '10000000-0000-4000-8000-000000000001'
  );

insert into public.farm_memberships (farm_id, user_id, role)
values (
  '20000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000001',
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
    '30000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    'tomato',
    'test-one',
    current_date,
    '영양생장기',
    'active'
  ),
  (
    '30000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    'paprika',
    'test-two',
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
    '40000000-0000-4000-8000-000000000001',
    '20000000-0000-4000-8000-000000000001',
    'GH-01',
    'Greenhouse 1',
    'greenhouse'
  ),
  (
    '40000000-0000-4000-8000-000000000002',
    '20000000-0000-4000-8000-000000000002',
    'GH-02',
    'Greenhouse 2',
    'greenhouse'
  );

set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000001';
set local request.jwt.claims =
  '{sub:10000000-0000-4000-8000-000000000001,role:authenticated}';

select extensions.lives_ok(
  $$
    select public.create_farm_task(
      target_farm_id := '20000000-0000-4000-8000-000000000001',
      task_title := 'Phase 0 linked task',
      task_scheduled_date := current_date,
      task_category := '환경관리',
      target_work_area_ids := array[
        '40000000-0000-4000-8000-000000000001'::uuid
      ]
    )
  $$,
  'owner can atomically create a farm-context task'
);

select extensions.is(
  (
    select cultivation_cycle_id
    from public.tasks
    where title = 'Phase 0 linked task'
  ),
  '30000000-0000-4000-8000-000000000001'::uuid,
  'the only active cultivation cycle is linked automatically'
);

select extensions.is(
  (
    select count(*)::integer
    from public.task_work_areas
    where task_id = (
      select id from public.tasks where title = 'Phase 0 linked task'
    )
  ),
  1,
  'requested work area is linked to the task'
);

select extensions.throws_ok(
  $$
    insert into public.task_logs (task_id, farm_id, action, note)
    select
      id,
      '20000000-0000-4000-8000-000000000001',
      'completed',
      'must be blocked'
    from public.tasks
    where title = 'Phase 0 linked task'
  $$,
  '42501',
  null,
  'authenticated users cannot insert task logs directly'
);

select extensions.throws_ok(
  $$truncate table public.task_logs$$,
  '42501',
  null,
  'authenticated users cannot bypass RLS with truncate'
);

select extensions.lives_ok(
  $$
    select public.record_task_action(
      '20000000-0000-4000-8000-000000000001',
      (select id from public.tasks where title = 'Phase 0 linked task'),
      'issue',
      'phase 0 issue',
      null,
      '기타',
      true,
      'Phase 0 follow-up',
      current_date + 1
    )
  $$,
  'task action RPC records a log and creates a follow-up'
);

select extensions.is(
  (
    select actor_id
    from public.task_logs
    where note like 'phase 0 issue%'
  ),
  '10000000-0000-4000-8000-000000000001'::uuid,
  'task action RPC records the authenticated actor'
);

select extensions.is(
  (
    select cultivation_cycle_id
    from public.tasks
    where title = 'Phase 0 follow-up'
  ),
  '30000000-0000-4000-8000-000000000001'::uuid,
  'follow-up inherits cultivation cycle context'
);

select extensions.is(
  (
    select count(*)::integer
    from public.task_work_areas
    where task_id = (
      select id from public.tasks where title = 'Phase 0 follow-up'
    )
  ),
  1,
  'follow-up inherits work area context'
);

select extensions.is(
  jsonb_array_length(
    public.record_task_action(
      '20000000-0000-4000-8000-000000000001',
      (select id from public.tasks where title = 'Phase 0 linked task'),
      'completed',
      'response contract check'
    ) -> 'task' -> 'work_area_ids'
  ),
  1,
  'task action response preserves work area context'
);

reset role;

select extensions.throws_ok(
  $$
    insert into public.tasks (
      farm_id,
      title,
      scheduled_date,
      category,
      parent_task_id
    )
    select
      '20000000-0000-4000-8000-000000000002',
      'Cross-farm parent',
      current_date,
      '기타',
      id
    from public.tasks
    where title = 'Phase 0 linked task'
  $$,
  '23503',
  null,
  'a parent task from another farm is rejected'
);

select extensions.throws_ok(
  $$
    insert into public.task_logs (task_id, farm_id, action, note)
    select
      id,
      '20000000-0000-4000-8000-000000000002',
      'completed',
      'cross-farm log'
    from public.tasks
    where title = 'Phase 0 linked task'
  $$,
  '23503',
  null,
  'a task log cannot reference a task from another farm'
);

select extensions.throws_ok(
  $$
    insert into public.task_work_areas (farm_id, task_id, work_area_id)
    select
      '20000000-0000-4000-8000-000000000001',
      id,
      '40000000-0000-4000-8000-000000000002'
    from public.tasks
    where title = 'Phase 0 linked task'
  $$,
  '23503',
  null,
  'a task cannot link a work area from another farm'
);

select extensions.throws_ok(
  $$
    insert into public.tasks (
      farm_id,
      cultivation_cycle_id,
      title,
      scheduled_date,
      category
    )
    values (
      '20000000-0000-4000-8000-000000000002',
      '30000000-0000-4000-8000-000000000001',
      'Cross-farm cycle',
      current_date,
      '기타'
    )
  $$,
  '23503',
  null,
  'a task cannot link a cultivation cycle from another farm'
);

set local role authenticated;
set local request.jwt.claim.sub = '10000000-0000-4000-8000-000000000002';
set local request.jwt.claims =
  '{sub:10000000-0000-4000-8000-000000000002,role:authenticated}';

select extensions.is(
  (
    select count(*)::integer
    from public.farm_work_areas
    where farm_id = '20000000-0000-4000-8000-000000000001'
  ),
  0,
  'non-members cannot read another farm work areas'
);

select extensions.is(
  (select count(*)::integer from public.agri_operation_types),
  6,
  'authenticated users can read operation type reference data'
);

select * from extensions.finish();

rollback;
