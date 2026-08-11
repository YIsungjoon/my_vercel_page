begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(52);

select extensions.has_table(
  'public',
  'activity_rule_runs',
  'activity rule execution ledger exists'
);
select extensions.has_table(
  'public',
  'activity_proposals',
  'activity proposal ledger exists'
);
select extensions.has_table(
  'public',
  'activity_proposal_work_areas',
  'proposal work areas use a relational child table'
);
select extensions.has_table(
  'public',
  'activity_proposal_decisions',
  'proposal decisions use an append-only relation'
);
select extensions.has_table(
  'public',
  'activity_proposal_applications',
  'proposal application receipts exist'
);

select extensions.is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'activity_rule_runs',
        'activity_proposals',
        'activity_proposal_work_areas',
        'activity_proposal_decisions',
        'activity_proposal_applications'
      )
      and data_type in ('json', 'jsonb')
  ),
  0,
  'phase 2A ledgers contain no JSON or JSONB persistence columns'
);

insert into auth.users (id, email)
values
  ('14000000-0000-4000-8000-000000000001', 'phase2a-owner@example.test'),
  ('14000000-0000-4000-8000-000000000002', 'phase2a-worker@example.test'),
  ('14000000-0000-4000-8000-000000000003', 'phase2a-outsider@example.test');

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
  '24000000-0000-4000-8000-000000000001',
  'phase2a-farm',
  'Phase 2A Farm',
  'Test Region',
  'KR',
  37.5,
  127.0,
  'Asia/Seoul',
  '14000000-0000-4000-8000-000000000001'
);

insert into public.farm_memberships (farm_id, user_id, role)
values
  (
    '24000000-0000-4000-8000-000000000001',
    '14000000-0000-4000-8000-000000000001',
    'owner'
  ),
  (
    '24000000-0000-4000-8000-000000000001',
    '14000000-0000-4000-8000-000000000002',
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
  '34000000-0000-4000-8000-000000000001',
  '24000000-0000-4000-8000-000000000001',
  'tomato',
  'phase2a-cycle',
  current_date,
  'test-stage',
  'active'
);

set local role authenticated;
set local request.jwt.claim.sub = '14000000-0000-4000-8000-000000000001';

select extensions.lives_ok(
  $$
    select public.create_schedule_project(
      target_farm_id := '24000000-0000-4000-8000-000000000001',
      target_cycle_id := '34000000-0000-4000-8000-000000000001',
      project_code := 'EXECUTION-PROJECT',
      project_name := 'Execution Project',
      project_timezone := 'Asia/Seoul',
      root_wbs_code := 'ROOT',
      root_wbs_name := 'Execution Root',
      calendar_code := 'DEFAULT',
      calendar_name := 'Default Calendar',
      calendar_working_periods := jsonb_build_array(
        jsonb_build_object(
          'weekday', 1, 'start_time', '08:00', 'end_time', '17:00'
        )
      )
    )
  $$,
  'owner creates the execution test project'
);

select extensions.lives_ok(
  $$
    select public.create_activity_template(
      target_farm_id := '24000000-0000-4000-8000-000000000001',
      template_code := 'DAILY-TEMPLATE',
      template_name := 'Daily crop inspection',
      target_operation_type_code := 'environment_control',
      template_default_duration_minutes := 30
    )
  $$,
  'owner creates the proposal template'
);

select extensions.lives_ok(
  $$
    select public.create_activity_recurrence_rule(
      target_farm_id := '24000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'DAILY-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'DAILY-CHECK',
      rule_name := 'Daily crop check',
      recurrence_frequency := 'DAILY',
      recurrence_starts_on := current_date,
      recurrence_occurrence_time := '06:00',
      rule_status := 'ACTIVE',
      generation_horizon_days := 30
    )
  $$,
  'owner creates an active daily recurrence rule'
);

select extensions.lives_ok(
  $$
    select public.create_activity_recurrence_rule(
      target_farm_id := '24000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'
      ),
      target_template_id := (
        select id from public.activity_templates where template_code = 'DAILY-TEMPLATE'
      ),
      target_wbs_id := (
        select id
        from public.schedule_wbs_nodes
        where project_id = (
          select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'
        )
          and wbs_code = 'ROOT'
      ),
      rule_code := 'FUTURE-CHECK',
      rule_name := 'Future crop check',
      recurrence_frequency := 'DAILY',
      recurrence_starts_on := current_date + 10,
      recurrence_occurrence_time := '07:00',
      rule_status := 'ACTIVE',
      generation_horizon_days := 30
    )
  $$,
  'owner creates a future recurrence rule for skipped runs'
);

select extensions.lives_ok(
  $$
    select public.materialize_activity_recurrence_rule(
      target_farm_id := '24000000-0000-4000-8000-000000000001',
      target_project_id := (
        select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'
      ),
      target_rule_id := (
        select id from public.activity_recurrence_rules where rule_code = 'DAILY-CHECK'
      ),
      expected_rule_version := 1,
      target_window_start := current_date,
      target_window_end := current_date + 2,
      run_idempotency_key := 'daily-check:window-001'
    )
  $$,
  'active recurrence materializes a three-day proposal window'
);

select extensions.ok(
  (
    select status = 'SUCCEEDED'
      and outcome_code = 'PROPOSALS_CREATED'
      and finished_at is not null
    from public.activity_rule_runs
    where idempotency_key = 'daily-check:window-001'
  ),
  'materialization run records a successful terminal outcome'
);

select extensions.ok(
  (
    select source_rule_version = 1 and source_template_version = 1
    from public.activity_rule_runs
    where idempotency_key = 'daily-check:window-001'
  ),
  'run snapshots both rule and template versions'
);

select extensions.is(
  (
    select count(*)::integer
    from public.activity_proposals
    where rule_run_id = (
      select id from public.activity_rule_runs
      where idempotency_key = 'daily-check:window-001'
    )
  ),
  3,
  'daily materialization creates one proposal per eligible date'
);

select extensions.ok(
  (
    select bool_and(status = 'PROPOSED' and version = 1)
    from public.activity_proposals
    where rule_run_id = (
      select id from public.activity_rule_runs
      where idempotency_key = 'daily-check:window-001'
    )
  ),
  'new materialized activities remain proposed'
);

select extensions.ok(
  (
    select bool_and(
      planned_finish_at - planned_start_at = interval '30 minutes'
      and planned_duration_minutes = 30
    )
    from public.activity_proposals
    where rule_run_id = (
      select id from public.activity_rule_runs
      where idempotency_key = 'daily-check:window-001'
    )
  ),
  'proposal timing snapshots the template duration'
);

select extensions.is(
  (
    select count(distinct activity_code)::integer
    from public.activity_proposals
    where rule_run_id = (
      select id from public.activity_rule_runs
      where idempotency_key = 'daily-check:window-001'
    )
  ),
  3,
  'materialized activity codes are deterministic and unique in the window'
);

select extensions.lives_ok(
  $$
    select public.materialize_activity_recurrence_rule(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (select id from public.activity_recurrence_rules where rule_code = 'DAILY-CHECK'),
      1,
      current_date,
      current_date + 2,
      'daily-check:window-001'
    )
  $$,
  'retrying a materialization with the same key returns the existing result'
);

select extensions.is(
  (
    select count(*)::integer
    from public.activity_rule_runs
    where idempotency_key = 'daily-check:window-001'
  ),
  1,
  'same-key materialization retry does not create another run'
);

select extensions.is(
  (
    select count(*)::integer
    from public.activity_proposals
    where rule_run_id = (
      select id from public.activity_rule_runs
      where idempotency_key = 'daily-check:window-001'
    )
  ),
  3,
  'same-key retry does not duplicate proposals'
);

select extensions.throws_ok(
  $$
    select public.materialize_activity_recurrence_rule(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (select id from public.activity_recurrence_rules where rule_code = 'DAILY-CHECK'),
      1,
      current_date,
      current_date + 1,
      'daily-check:window-001'
    )
  $$,
  'P0001',
  null,
  'one idempotency key cannot identify a different request'
);

select extensions.throws_ok(
  $$
    select public.materialize_activity_recurrence_rule(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (select id from public.activity_recurrence_rules where rule_code = 'DAILY-CHECK'),
      1,
      current_date,
      current_date + 2,
      'daily-check:window-002'
    )
  $$,
  'P0001',
  null,
  'same rule version and window cannot run under another key'
);

select extensions.throws_ok(
  $$
    select public.materialize_activity_recurrence_rule(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (select id from public.activity_recurrence_rules where rule_code = 'DAILY-CHECK'),
      2,
      current_date + 3,
      current_date + 4,
      'daily-check:stale-001'
    )
  $$,
  '40001',
  null,
  'stale recurrence version cannot be materialized'
);

select extensions.throws_ok(
  $$
    select public.materialize_activity_recurrence_rule(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (select id from public.activity_recurrence_rules where rule_code = 'DAILY-CHECK'),
      1,
      current_date - 1,
      current_date,
      'daily-check:past-001'
    )
  $$,
  'P0001',
  null,
  'materialization cannot create past occurrences'
);

select extensions.throws_ok(
  $$
    select public.materialize_activity_recurrence_rule(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (select id from public.activity_recurrence_rules where rule_code = 'DAILY-CHECK'),
      1,
      current_date + 29,
      current_date + 31,
      'daily-check:horizon-001'
    )
  $$,
  'P0001',
  null,
  'materialization cannot exceed the configured generation horizon'
);

select extensions.lives_ok(
  $$
    select public.materialize_activity_recurrence_rule(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (select id from public.activity_recurrence_rules where rule_code = 'FUTURE-CHECK'),
      1,
      current_date,
      current_date + 2,
      'future-check:window-001'
    )
  $$,
  'a valid window with no eligible dates records a run'
);

select extensions.ok(
  (
    select status = 'SKIPPED' and outcome_code = 'NO_OCCURRENCES'
    from public.activity_rule_runs
    where idempotency_key = 'future-check:window-001'
  ),
  'no-occurrence run records an explicit skipped outcome'
);

select extensions.is(
  (
    select count(*)::integer
    from public.activity_proposals
    where rule_run_id = (
      select id from public.activity_rule_runs
      where idempotency_key = 'future-check:window-001'
    )
  ),
  0,
  'skipped no-occurrence run creates no proposals'
);

select extensions.throws_ok(
  $$
    insert into public.activity_rule_runs (
      farm_id,
      project_id,
      run_kind,
      recurrence_rule_id,
      source_rule_version,
      source_template_version,
      idempotency_key,
      window_start_date,
      window_end_date,
      status,
      finished_at,
      created_by
    )
    select
      farm_id,
      project_id,
      'RECURRENCE_MATERIALIZATION',
      id,
      version,
      1,
      'direct-run:blocked-001',
      current_date,
      current_date,
      'SKIPPED',
      now(),
      '14000000-0000-4000-8000-000000000001'
    from public.activity_recurrence_rules
    where rule_code = 'DAILY-CHECK'
  $$,
  '42501',
  null,
  'authenticated clients cannot directly insert rule runs'
);

set local request.jwt.claim.sub = '14000000-0000-4000-8000-000000000002';

select extensions.throws_ok(
  $$
    select public.materialize_activity_recurrence_rule(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (select id from public.activity_recurrence_rules where rule_code = 'DAILY-CHECK'),
      1,
      current_date + 3,
      current_date + 4,
      'worker-run:blocked-001'
    )
  $$,
  'P0001',
  null,
  'workers cannot materialize recurrence rules'
);

select extensions.is(
  (select count(*)::integer from public.activity_rule_runs),
  2,
  'worker farm members can read rule runs'
);

set local request.jwt.claim.sub = '14000000-0000-4000-8000-000000000001';

select extensions.lives_ok(
  $$
    select public.decide_activity_proposal(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (
        select id
        from public.activity_proposals
        where rule_run_id = (
          select id from public.activity_rule_runs
          where idempotency_key = 'daily-check:window-001'
        )
        order by planned_start_at
        limit 1
      ),
      1,
      'APPROVED',
      'MANAGER_REVIEW',
      'Approved for schedule'
    )
  $$,
  'manager approves a proposed activity'
);

select extensions.ok(
  (
    select status = 'APPROVED' and version = 2
    from public.activity_proposals
    where rule_run_id = (
      select id from public.activity_rule_runs
      where idempotency_key = 'daily-check:window-001'
    )
    order by planned_start_at
    limit 1
  ),
  'approval transitions proposal status and increments version'
);

select extensions.ok(
  (
    select decision = 'APPROVED'
      and decided_by = '14000000-0000-4000-8000-000000000001'::uuid
    from public.activity_proposal_decisions
    where proposal_id = (
      select id
      from public.activity_proposals
      where rule_run_id = (
        select id from public.activity_rule_runs
        where idempotency_key = 'daily-check:window-001'
      )
      order by planned_start_at
      limit 1
    )
  ),
  'approval decision is stored with its actor'
);

select extensions.throws_ok(
  $$
    select public.decide_activity_proposal(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (
        select id
        from public.activity_proposals
        where rule_run_id = (
          select id from public.activity_rule_runs
          where idempotency_key = 'daily-check:window-001'
        )
        order by planned_start_at
        limit 1
      ),
      2,
      'REJECTED',
      'CHANGED_MIND',
      null
    )
  $$,
  'P0001',
  null,
  'a decided proposal cannot receive a second decision'
);

select extensions.throws_ok(
  $$
    select public.decide_activity_proposal(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (
        select id
        from public.activity_proposals
        where rule_run_id = (
          select id from public.activity_rule_runs
          where idempotency_key = 'daily-check:window-001'
        )
        order by planned_start_at
        offset 1
        limit 1
      ),
      2,
      'APPROVED',
      null,
      null
    )
  $$,
  '40001',
  null,
  'stale proposal decision version is rejected'
);

select extensions.throws_ok(
  $$
    select public.apply_activity_proposal(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (
        select id
        from public.activity_proposals
        where rule_run_id = (
          select id from public.activity_rule_runs
          where idempotency_key = 'daily-check:window-001'
        )
        order by planned_start_at
        offset 1
        limit 1
      ),
      1,
      'proposal-apply:unapproved-001'
    )
  $$,
  'P0001',
  null,
  'an unapproved proposal cannot create a schedule activity'
);

select extensions.lives_ok(
  $$
    select public.apply_activity_proposal(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (
        select id
        from public.activity_proposals
        where rule_run_id = (
          select id from public.activity_rule_runs
          where idempotency_key = 'daily-check:window-001'
        )
        order by planned_start_at
        limit 1
      ),
      2,
      'proposal-apply:daily-001'
    )
  $$,
  'approved proposal applies to the P6 schedule ledger'
);

select extensions.ok(
  (
    select status = 'APPLIED' and version = 3
    from public.activity_proposals
    where rule_run_id = (
      select id from public.activity_rule_runs
      where idempotency_key = 'daily-check:window-001'
    )
    order by planned_start_at
    limit 1
  ),
  'application transitions approved proposal to applied'
);

select extensions.ok(
  (
    select activity.status = 'NOT_STARTED'
      and activity.planned_duration_minutes = proposal.planned_duration_minutes
      and activity.planned_start_at = proposal.planned_start_at
      and activity.wbs_id = proposal.wbs_id
      and activity.calendar_id = proposal.calendar_id
    from public.activity_proposal_applications as application
    join public.activity_proposals as proposal
      on proposal.id = application.proposal_id
    join public.schedule_activities as activity
      on activity.id = application.activity_id
    where application.idempotency_key = 'proposal-apply:daily-001'
  ),
  'applied activity preserves the proposal schedule snapshot'
);

select extensions.ok(
  (
    select idempotency_key = 'proposal-apply:daily-001'
      and applied_by = '14000000-0000-4000-8000-000000000001'::uuid
    from public.activity_proposal_applications
    where idempotency_key = 'proposal-apply:daily-001'
  ),
  'application receipt records idempotency key and actor'
);

select extensions.lives_ok(
  $$
    select public.apply_activity_proposal(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (
        select id
        from public.activity_proposals
        where rule_run_id = (
          select id from public.activity_rule_runs
          where idempotency_key = 'daily-check:window-001'
        )
        order by planned_start_at
        limit 1
      ),
      2,
      'proposal-apply:daily-001'
    )
  $$,
  'same-key application retry returns its existing receipt'
);

select extensions.is(
  (select count(*)::integer from public.schedule_activities),
  1,
  'same-key application retry creates exactly one schedule activity'
);

select extensions.throws_ok(
  $$
    select public.apply_activity_proposal(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (
        select id
        from public.activity_proposals
        where rule_run_id = (
          select id from public.activity_rule_runs
          where idempotency_key = 'daily-check:window-001'
        )
        order by planned_start_at
        limit 1
      ),
      3,
      'proposal-apply:other-001'
    )
  $$,
  'P0001',
  null,
  'an applied proposal cannot be retried under another key'
);

select extensions.throws_ok(
  $$
    select public.decide_activity_proposal(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (
        select id
        from public.activity_proposals
        where rule_run_id = (
          select id from public.activity_rule_runs
          where idempotency_key = 'daily-check:window-001'
        )
        order by planned_start_at
        offset 1
        limit 1
      ),
      1,
      'REJECTED',
      null,
      null
    )
  $$,
  'P0001',
  null,
  'rejection requires a structured reason or note'
);

select extensions.lives_ok(
  $$
    select public.decide_activity_proposal(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (
        select id
        from public.activity_proposals
        where rule_run_id = (
          select id from public.activity_rule_runs
          where idempotency_key = 'daily-check:window-001'
        )
        order by planned_start_at
        offset 1
        limit 1
      ),
      1,
      'REJECTED',
      'WEATHER_RISK',
      'Forecast risk is too high'
    )
  $$,
  'manager rejects another proposal with a reason'
);

select extensions.ok(
  (
    select decision = 'REJECTED' and reason_code = 'WEATHER_RISK'
    from public.activity_proposal_decisions
    where proposal_id = (
      select id
      from public.activity_proposals
      where rule_run_id = (
        select id from public.activity_rule_runs
        where idempotency_key = 'daily-check:window-001'
      )
      order by planned_start_at
      offset 1
      limit 1
    )
  ),
  'rejection reason is retained in the decision ledger'
);

select extensions.throws_ok(
  $$
    select public.apply_activity_proposal(
      '24000000-0000-4000-8000-000000000001',
      (select id from public.schedule_projects where project_code = 'EXECUTION-PROJECT'),
      (
        select id
        from public.activity_proposals
        where rule_run_id = (
          select id from public.activity_rule_runs
          where idempotency_key = 'daily-check:window-001'
        )
        order by planned_start_at
        offset 1
        limit 1
      ),
      2,
      'proposal-apply:rejected-001'
    )
  $$,
  'P0001',
  null,
  'rejected proposal cannot be applied'
);

set local request.jwt.claim.sub = '14000000-0000-4000-8000-000000000003';

select extensions.is(
  (select count(*)::integer from public.activity_rule_runs),
  0,
  'non-members cannot read activity rule runs'
);

select extensions.is(
  (select count(*)::integer from public.activity_proposals),
  0,
  'non-members cannot read activity proposals'
);

select extensions.throws_ok(
  $$truncate table public.activity_proposals$$,
  '42501',
  null,
  'authenticated users cannot truncate the proposal ledger'
);

reset role;

select extensions.is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and data_type in ('json', 'jsonb')
  ),
  0,
  'public schema still has no JSON or JSONB persistence columns'
);

select * from extensions.finish();

rollback;
