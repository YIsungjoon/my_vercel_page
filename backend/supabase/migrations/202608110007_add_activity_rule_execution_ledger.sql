-- Phase 2A: relational rule runs, activity proposals, decisions, and receipts.

create table public.activity_rule_runs (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  run_kind text not null,
  recurrence_rule_id uuid,
  trigger_rule_id uuid,
  source_rule_version integer not null,
  source_template_version integer not null,
  idempotency_key text not null,
  window_start_date date,
  window_end_date date,
  status text not null default 'RUNNING',
  outcome_code text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint activity_rule_runs_farm_project_id_id_key
    unique (farm_id, project_id, id),
  constraint activity_rule_runs_project_idempotency_key
    unique (project_id, idempotency_key),
  constraint activity_rule_runs_kind_check
    check (run_kind in ('RECURRENCE_MATERIALIZATION', 'TRIGGER_EVALUATION')),
  constraint activity_rule_runs_source_check
    check (
      (
        run_kind = 'RECURRENCE_MATERIALIZATION'
        and recurrence_rule_id is not null
        and trigger_rule_id is null
      )
      or (
        run_kind = 'TRIGGER_EVALUATION'
        and recurrence_rule_id is null
        and trigger_rule_id is not null
      )
    ),
  constraint activity_rule_runs_version_check check (source_rule_version >= 1),
  constraint activity_rule_runs_template_version_check
    check (source_template_version >= 1),
  constraint activity_rule_runs_idempotency_format_check
    check (idempotency_key ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$'),
  constraint activity_rule_runs_window_check
    check (
      (window_start_date is null and window_end_date is null)
      or (
        window_start_date is not null
        and window_end_date is not null
        and window_end_date >= window_start_date
      )
    ),
  constraint activity_rule_runs_recurrence_window_check
    check (
      run_kind <> 'RECURRENCE_MATERIALIZATION'
      or window_start_date is not null
    ),
  constraint activity_rule_runs_status_check
    check (status in ('RUNNING', 'SUCCEEDED', 'FAILED', 'SKIPPED')),
  constraint activity_rule_runs_finish_check
    check (
      (status = 'RUNNING' and finished_at is null)
      or (status <> 'RUNNING' and finished_at is not null)
    ),
  constraint activity_rule_runs_project_same_farm_fkey
    foreign key (farm_id, project_id)
    references public.schedule_projects(farm_id, id)
    on delete cascade,
  constraint activity_rule_runs_recurrence_same_project_fkey
    foreign key (farm_id, project_id, recurrence_rule_id)
    references public.activity_recurrence_rules(farm_id, project_id, id)
    on delete restrict,
  constraint activity_rule_runs_trigger_same_project_fkey
    foreign key (farm_id, project_id, trigger_rule_id)
    references public.activity_trigger_rules(farm_id, project_id, id)
    on delete restrict
);

create unique index activity_rule_runs_recurrence_window_idx
on public.activity_rule_runs(
  recurrence_rule_id,
  source_rule_version,
  window_start_date,
  window_end_date
)
where run_kind = 'RECURRENCE_MATERIALIZATION';

create table public.activity_proposals (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  rule_run_id uuid not null,
  proposal_key text not null,
  template_id uuid not null,
  template_version integer not null,
  wbs_id uuid not null,
  calendar_id uuid not null,
  cultivation_cycle_id uuid,
  operation_type_code text not null,
  activity_code text not null,
  name text not null,
  description text,
  activity_type text not null,
  percent_complete_type text not null,
  planned_start_at timestamptz not null,
  planned_finish_at timestamptz not null,
  planned_duration_minutes integer not null,
  status text not null default 'PROPOSED',
  version integer not null default 1,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint activity_proposals_farm_project_id_id_key
    unique (farm_id, project_id, id),
  constraint activity_proposals_project_key
    unique (project_id, proposal_key),
  constraint activity_proposals_run_start_key
    unique (rule_run_id, planned_start_at),
  constraint activity_proposals_key_format_check
    check (proposal_key ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{7,191}$'),
  constraint activity_proposals_template_version_check check (template_version >= 1),
  constraint activity_proposals_code_format_check
    check (activity_code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'),
  constraint activity_proposals_type_check
    check (activity_type in (
      'TASK_DEPENDENT',
      'RESOURCE_DEPENDENT',
      'LEVEL_OF_EFFORT',
      'START_MILESTONE',
      'FINISH_MILESTONE',
      'WBS_SUMMARY'
    )),
  constraint activity_proposals_percent_type_check
    check (percent_complete_type in ('DURATION', 'UNITS', 'PHYSICAL')),
  constraint activity_proposals_duration_check check (planned_duration_minutes >= 0),
  constraint activity_proposals_milestone_duration_check
    check (
      activity_type not in ('START_MILESTONE', 'FINISH_MILESTONE')
      or planned_duration_minutes = 0
    ),
  constraint activity_proposals_range_check
    check (planned_finish_at >= planned_start_at),
  constraint activity_proposals_status_check
    check (status in ('PROPOSED', 'APPROVED', 'REJECTED', 'APPLIED')),
  constraint activity_proposals_version_check check (version >= 1),
  constraint activity_proposals_run_same_project_fkey
    foreign key (farm_id, project_id, rule_run_id)
    references public.activity_rule_runs(farm_id, project_id, id)
    on delete restrict,
  constraint activity_proposals_template_same_farm_fkey
    foreign key (farm_id, template_id)
    references public.activity_templates(farm_id, id)
    on delete restrict,
  constraint activity_proposals_wbs_same_project_fkey
    foreign key (farm_id, project_id, wbs_id)
    references public.schedule_wbs_nodes(farm_id, project_id, id)
    on delete restrict,
  constraint activity_proposals_calendar_same_project_fkey
    foreign key (farm_id, project_id, calendar_id)
    references public.schedule_calendars(farm_id, project_id, id)
    on delete restrict,
  constraint activity_proposals_cycle_same_farm_fkey
    foreign key (farm_id, cultivation_cycle_id)
    references public.cultivation_cycles(farm_id, id)
    on delete set null (cultivation_cycle_id),
  constraint activity_proposals_operation_type_fkey
    foreign key (operation_type_code)
    references public.agri_operation_types(code)
);

create table public.activity_proposal_work_areas (
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  proposal_id uuid not null,
  work_area_id uuid not null,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (proposal_id, work_area_id),
  constraint activity_proposal_areas_proposal_same_project_fkey
    foreign key (farm_id, project_id, proposal_id)
    references public.activity_proposals(farm_id, project_id, id)
    on delete cascade,
  constraint activity_proposal_areas_area_same_farm_fkey
    foreign key (farm_id, work_area_id)
    references public.farm_work_areas(farm_id, id)
    on delete restrict
);

create unique index activity_proposal_areas_one_primary_idx
on public.activity_proposal_work_areas(proposal_id)
where is_primary;

create table public.activity_proposal_decisions (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  proposal_id uuid not null,
  decision text not null,
  reason_code text,
  note text,
  decided_by uuid not null references auth.users(id) on delete restrict,
  decided_at timestamptz not null default now(),
  constraint activity_proposal_decisions_proposal_key unique (proposal_id),
  constraint activity_proposal_decisions_decision_check
    check (decision in ('APPROVED', 'REJECTED')),
  constraint activity_proposal_decisions_reason_format_check
    check (
      reason_code is null
      or reason_code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'
    ),
  constraint activity_proposal_decisions_proposal_same_project_fkey
    foreign key (farm_id, project_id, proposal_id)
    references public.activity_proposals(farm_id, project_id, id)
    on delete restrict
);

create table public.activity_proposal_applications (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  proposal_id uuid not null,
  activity_id uuid not null,
  idempotency_key text not null,
  applied_by uuid not null references auth.users(id) on delete restrict,
  applied_at timestamptz not null default now(),
  constraint activity_proposal_applications_proposal_key unique (proposal_id),
  constraint activity_proposal_applications_activity_key unique (activity_id),
  constraint activity_proposal_applications_project_idempotency_key
    unique (project_id, idempotency_key),
  constraint activity_proposal_applications_idempotency_format_check
    check (idempotency_key ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$'),
  constraint activity_proposal_applications_proposal_same_project_fkey
    foreign key (farm_id, project_id, proposal_id)
    references public.activity_proposals(farm_id, project_id, id)
    on delete restrict,
  constraint activity_proposal_applications_activity_same_project_fkey
    foreign key (farm_id, project_id, activity_id)
    references public.schedule_activities(farm_id, project_id, id)
    on delete restrict
);

create index activity_rule_runs_project_created_idx
on public.activity_rule_runs(project_id, created_at desc);

create index activity_proposals_project_status_start_idx
on public.activity_proposals(project_id, status, planned_start_at);

create trigger set_activity_proposals_updated_at
before update on public.activity_proposals
for each row execute function public.set_updated_at();

create trigger validate_activity_proposal_version_increment
before update on public.activity_proposals
for each row execute function public.validate_activity_model_version_increment();

create or replace function public.validate_activity_proposal_status_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (
    (old.status = 'PROPOSED' and new.status in ('APPROVED', 'REJECTED'))
    or (old.status = 'APPROVED' and new.status = 'APPLIED')
  ) then
    raise exception 'Activity proposal status transition from % to % is not allowed',
      old.status,
      new.status;
  end if;

  return new;
end;
$$;

create trigger validate_activity_proposal_status_transition
before update of status on public.activity_proposals
for each row execute function public.validate_activity_proposal_status_transition();

create or replace function public.activity_rule_run_response(target_run_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_run public.activity_rule_runs;
  selected_proposals jsonb;
begin
  select *
  into selected_run
  from public.activity_rule_runs
  where id = target_run_id;

  if not found then
    raise exception 'Activity rule run was not found';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(proposal) order by proposal.planned_start_at),
    '[]'::jsonb
  )
  into selected_proposals
  from public.activity_proposals as proposal
  where proposal.rule_run_id = selected_run.id;

  return jsonb_build_object(
    'run', to_jsonb(selected_run),
    'proposals', selected_proposals
  );
end;
$$;

create or replace function public.materialize_activity_recurrence_rule(
  target_farm_id uuid,
  target_project_id uuid,
  target_rule_id uuid,
  expected_rule_version integer,
  target_window_start date,
  target_window_end date,
  run_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  current_rule public.activity_recurrence_rules;
  current_template public.activity_templates;
  existing_run public.activity_rule_runs;
  created_run public.activity_rule_runs;
  proposal_count integer;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to materialize a recurrence rule';
  end if;

  if nullif(trim(run_idempotency_key), '') is null
     or trim(run_idempotency_key) !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$' then
    raise exception 'A valid run idempotency key is required';
  end if;

  select *
  into existing_run
  from public.activity_rule_runs
  where project_id = target_project_id
    and idempotency_key = trim(run_idempotency_key);

  if found then
    if existing_run.farm_id <> target_farm_id
       or existing_run.run_kind <> 'RECURRENCE_MATERIALIZATION'
       or existing_run.recurrence_rule_id <> target_rule_id
       or existing_run.source_rule_version <> expected_rule_version
       or existing_run.window_start_date <> target_window_start
       or existing_run.window_end_date <> target_window_end then
      raise exception 'Run idempotency key is already used by another request';
    end if;

    return public.activity_rule_run_response(existing_run.id);
  end if;

  select *
  into current_rule
  from public.activity_recurrence_rules
  where farm_id = target_farm_id
    and project_id = target_project_id
    and id = target_rule_id
  for share;

  if not found then
    raise exception 'Recurrence rule was not found for this project';
  end if;

  if current_rule.status <> 'ACTIVE' then
    raise exception 'Only an active recurrence rule can be materialized';
  end if;

  if current_rule.version <> expected_rule_version then
    raise exception using
      errcode = '40001',
      message = 'Recurrence rule version conflict';
  end if;

  select *
  into current_template
  from public.activity_templates
  where farm_id = target_farm_id
    and id = current_rule.template_id
    and is_active;

  if not found then
    raise exception 'An active activity template is required for materialization';
  end if;

  if target_window_start is null
     or target_window_end is null
     or target_window_end < target_window_start then
    raise exception 'A valid materialization date window is required';
  end if;

  if target_window_start < current_date then
    raise exception 'Materialization cannot create past occurrences';
  end if;

  if target_window_end > current_date + current_rule.generation_horizon_days then
    raise exception 'Materialization window exceeds the rule generation horizon';
  end if;

  if target_window_end - target_window_start + 1
     > current_rule.generation_horizon_days then
    raise exception 'Materialization window is larger than the generation horizon';
  end if;

  if exists (
    select 1
    from public.activity_rule_runs
    where recurrence_rule_id = current_rule.id
      and source_rule_version = current_rule.version
      and window_start_date = target_window_start
      and window_end_date = target_window_end
  ) then
    raise exception 'This recurrence rule version and window were already materialized';
  end if;

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
    created_by
  )
  values (
    target_farm_id,
    target_project_id,
    'RECURRENCE_MATERIALIZATION',
    current_rule.id,
    current_rule.version,
    current_template.version,
    trim(run_idempotency_key),
    target_window_start,
    target_window_end,
    'RUNNING',
    auth.uid()
  )
  returning * into created_run;

  with candidate_dates as (
    select generated_date::date as occurrence_date
    from generate_series(
      target_window_start::timestamp,
      target_window_end::timestamp,
      interval '1 day'
    ) as dates(generated_date)
  ),
  eligible_dates as (
    select candidate.occurrence_date
    from candidate_dates as candidate
    where candidate.occurrence_date >= current_rule.starts_on
      and (
        current_rule.ends_on is null
        or candidate.occurrence_date <= current_rule.ends_on
      )
      and (
        (
          current_rule.frequency = 'DAILY'
          and (
            (candidate.occurrence_date - current_rule.starts_on)
            % current_rule.interval_count
          ) = 0
        )
        or (
          current_rule.frequency = 'WEEKLY'
          and (
            ((candidate.occurrence_date - current_rule.starts_on) / 7)
            % current_rule.interval_count
          ) = 0
          and exists (
            select 1
            from public.activity_recurrence_weekdays as weekday
            where weekday.recurrence_rule_id = current_rule.id
              and weekday.weekday = extract(dow from candidate.occurrence_date)::integer
          )
        )
        or (
          current_rule.frequency = 'MONTHLY'
          and extract(day from candidate.occurrence_date)::integer
            = current_rule.day_of_month
          and (
            (
              extract(year from candidate.occurrence_date)::integer * 12
              + extract(month from candidate.occurrence_date)::integer
              - extract(year from current_rule.starts_on)::integer * 12
              - extract(month from current_rule.starts_on)::integer
            ) % current_rule.interval_count
          ) = 0
        )
      )
  ),
  occurrences as (
    select
      eligible.occurrence_date,
      (
        eligible.occurrence_date + current_rule.occurrence_time
      ) at time zone current_rule.timezone as planned_start_at
    from eligible_dates as eligible
  )
  insert into public.activity_proposals (
    farm_id,
    project_id,
    rule_run_id,
    proposal_key,
    template_id,
    template_version,
    wbs_id,
    calendar_id,
    cultivation_cycle_id,
    operation_type_code,
    activity_code,
    name,
    description,
    activity_type,
    percent_complete_type,
    planned_start_at,
    planned_finish_at,
    planned_duration_minutes,
    status,
    created_by,
    updated_by
  )
  select
    target_farm_id,
    target_project_id,
    created_run.id,
    'recurrence:' || current_rule.id::text
      || ':v' || current_rule.version::text
      || ':' || to_char(occurrence.planned_start_at at time zone 'UTC', 'YYYYMMDDHH24MI'),
    current_template.id,
    current_template.version,
    current_rule.wbs_id,
    current_rule.calendar_id,
    current_rule.cultivation_cycle_id,
    current_template.operation_type_code,
    current_rule.rule_code
      || '-' || to_char(occurrence.occurrence_date, 'YYYYMMDD')
      || '-' || to_char(current_rule.occurrence_time, 'HH24MI'),
    current_template.name,
    current_template.description,
    current_template.activity_type,
    current_template.percent_complete_type,
    occurrence.planned_start_at,
    occurrence.planned_start_at
      + make_interval(mins => current_template.default_duration_minutes),
    current_template.default_duration_minutes,
    'PROPOSED',
    auth.uid(),
    auth.uid()
  from occurrences as occurrence;

  get diagnostics proposal_count = row_count;

  update public.activity_rule_runs
  set status = case when proposal_count = 0 then 'SKIPPED' else 'SUCCEEDED' end,
      outcome_code = case
        when proposal_count = 0 then 'NO_OCCURRENCES'
        else 'PROPOSALS_CREATED'
      end,
      finished_at = now()
  where id = created_run.id
  returning * into created_run;

  return public.activity_rule_run_response(created_run.id);
end;
$$;

create or replace function public.decide_activity_proposal(
  target_farm_id uuid,
  target_project_id uuid,
  target_proposal_id uuid,
  expected_version integer,
  proposal_decision text,
  decision_reason_code text default null,
  decision_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_proposal public.activity_proposals;
  updated_proposal public.activity_proposals;
  created_decision public.activity_proposal_decisions;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to decide an activity proposal';
  end if;

  if proposal_decision not in ('APPROVED', 'REJECTED') then
    raise exception 'Proposal decision must be approved or rejected';
  end if;

  if proposal_decision = 'REJECTED'
     and nullif(trim(decision_reason_code), '') is null
     and nullif(trim(decision_note), '') is null then
    raise exception 'A rejected proposal requires a reason code or note';
  end if;

  select *
  into current_proposal
  from public.activity_proposals
  where farm_id = target_farm_id
    and project_id = target_project_id
    and id = target_proposal_id
  for update;

  if not found then
    raise exception 'Activity proposal was not found for this project';
  end if;

  if current_proposal.version <> expected_version then
    raise exception using
      errcode = '40001',
      message = 'Activity proposal version conflict';
  end if;

  if current_proposal.status <> 'PROPOSED' then
    raise exception 'Only a proposed activity can receive a decision';
  end if;

  update public.activity_proposals
  set status = proposal_decision,
      updated_by = auth.uid(),
      version = current_proposal.version + 1
  where id = current_proposal.id
  returning * into updated_proposal;

  insert into public.activity_proposal_decisions (
    farm_id,
    project_id,
    proposal_id,
    decision,
    reason_code,
    note,
    decided_by
  )
  values (
    target_farm_id,
    target_project_id,
    current_proposal.id,
    proposal_decision,
    nullif(trim(decision_reason_code), ''),
    nullif(trim(decision_note), ''),
    auth.uid()
  )
  returning * into created_decision;

  return jsonb_build_object(
    'proposal', to_jsonb(updated_proposal),
    'decision', to_jsonb(created_decision)
  );
end;
$$;

create or replace function public.activity_proposal_application_response(
  target_application_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_application public.activity_proposal_applications;
  selected_proposal public.activity_proposals;
  selected_activity public.schedule_activities;
begin
  select *
  into selected_application
  from public.activity_proposal_applications
  where id = target_application_id;

  if not found then
    raise exception 'Activity proposal application was not found';
  end if;

  select *
  into selected_proposal
  from public.activity_proposals
  where id = selected_application.proposal_id;

  select *
  into selected_activity
  from public.schedule_activities
  where id = selected_application.activity_id;

  return jsonb_build_object(
    'proposal', to_jsonb(selected_proposal),
    'activity', to_jsonb(selected_activity),
    'application', to_jsonb(selected_application)
  );
end;
$$;

create or replace function public.apply_activity_proposal(
  target_farm_id uuid,
  target_project_id uuid,
  target_proposal_id uuid,
  expected_version integer,
  application_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_proposal public.activity_proposals;
  updated_proposal public.activity_proposals;
  existing_application public.activity_proposal_applications;
  created_application public.activity_proposal_applications;
  created_activity public.schedule_activities;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to apply an activity proposal';
  end if;

  if nullif(trim(application_idempotency_key), '') is null
     or trim(application_idempotency_key) !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$' then
    raise exception 'A valid application idempotency key is required';
  end if;

  select *
  into existing_application
  from public.activity_proposal_applications
  where project_id = target_project_id
    and proposal_id = target_proposal_id;

  if found then
    if existing_application.farm_id <> target_farm_id
       or existing_application.idempotency_key
          <> trim(application_idempotency_key) then
      raise exception 'Proposal was already applied with another idempotency key';
    end if;

    return public.activity_proposal_application_response(existing_application.id);
  end if;

  if exists (
    select 1
    from public.activity_proposal_applications
    where project_id = target_project_id
      and idempotency_key = trim(application_idempotency_key)
  ) then
    raise exception 'Application idempotency key is already used by another proposal';
  end if;

  select *
  into current_proposal
  from public.activity_proposals
  where farm_id = target_farm_id
    and project_id = target_project_id
    and id = target_proposal_id
  for update;

  if not found then
    raise exception 'Activity proposal was not found for this project';
  end if;

  if current_proposal.version <> expected_version then
    raise exception using
      errcode = '40001',
      message = 'Activity proposal version conflict';
  end if;

  if current_proposal.status <> 'APPROVED' then
    raise exception 'Only an approved activity proposal can be applied';
  end if;

  insert into public.schedule_activities (
    farm_id,
    project_id,
    wbs_id,
    calendar_id,
    cultivation_cycle_id,
    operation_type_code,
    activity_code,
    name,
    description,
    activity_type,
    status,
    percent_complete_type,
    planned_start_at,
    planned_finish_at,
    planned_duration_minutes,
    remaining_duration_minutes,
    created_by,
    updated_by
  )
  values (
    current_proposal.farm_id,
    current_proposal.project_id,
    current_proposal.wbs_id,
    current_proposal.calendar_id,
    current_proposal.cultivation_cycle_id,
    current_proposal.operation_type_code,
    current_proposal.activity_code,
    current_proposal.name,
    current_proposal.description,
    current_proposal.activity_type,
    'NOT_STARTED',
    current_proposal.percent_complete_type,
    current_proposal.planned_start_at,
    current_proposal.planned_finish_at,
    current_proposal.planned_duration_minutes,
    current_proposal.planned_duration_minutes,
    auth.uid(),
    auth.uid()
  )
  returning * into created_activity;

  insert into public.schedule_activity_work_areas (
    farm_id,
    project_id,
    activity_id,
    work_area_id,
    is_primary
  )
  select
    area.farm_id,
    area.project_id,
    created_activity.id,
    area.work_area_id,
    area.is_primary
  from public.activity_proposal_work_areas as area
  where area.proposal_id = current_proposal.id;

  update public.activity_proposals
  set status = 'APPLIED',
      updated_by = auth.uid(),
      version = current_proposal.version + 1
  where id = current_proposal.id
  returning * into updated_proposal;

  insert into public.activity_proposal_applications (
    farm_id,
    project_id,
    proposal_id,
    activity_id,
    idempotency_key,
    applied_by
  )
  values (
    target_farm_id,
    target_project_id,
    updated_proposal.id,
    created_activity.id,
    trim(application_idempotency_key),
    auth.uid()
  )
  returning * into created_application;

  return public.activity_proposal_application_response(created_application.id);
end;
$$;

alter table public.activity_rule_runs enable row level security;
alter table public.activity_proposals enable row level security;
alter table public.activity_proposal_work_areas enable row level security;
alter table public.activity_proposal_decisions enable row level security;
alter table public.activity_proposal_applications enable row level security;

create policy members_read_activity_rule_runs
on public.activity_rule_runs
for select to authenticated
using (public.is_farm_member(farm_id));

create policy members_read_activity_proposals
on public.activity_proposals
for select to authenticated
using (public.is_farm_member(farm_id));

create policy members_read_activity_proposal_areas
on public.activity_proposal_work_areas
for select to authenticated
using (public.is_farm_member(farm_id));

create policy members_read_activity_proposal_decisions
on public.activity_proposal_decisions
for select to authenticated
using (public.is_farm_member(farm_id));

create policy members_read_activity_proposal_applications
on public.activity_proposal_applications
for select to authenticated
using (public.is_farm_member(farm_id));

grant select on table
  public.activity_rule_runs,
  public.activity_proposals,
  public.activity_proposal_work_areas,
  public.activity_proposal_decisions,
  public.activity_proposal_applications
to authenticated;

revoke all on table
  public.activity_rule_runs,
  public.activity_proposals,
  public.activity_proposal_work_areas,
  public.activity_proposal_decisions,
  public.activity_proposal_applications
from anon;

revoke insert, update, delete, truncate, trigger, references on table
  public.activity_rule_runs,
  public.activity_proposals,
  public.activity_proposal_work_areas,
  public.activity_proposal_decisions,
  public.activity_proposal_applications
from authenticated;

revoke execute on function public.validate_activity_proposal_status_transition()
from public, anon, authenticated;
revoke execute on function public.activity_rule_run_response(uuid)
from public, anon, authenticated;
revoke execute on function public.activity_proposal_application_response(uuid)
from public, anon, authenticated;

revoke execute on function public.materialize_activity_recurrence_rule(
  uuid, uuid, uuid, integer, date, date, text
) from public, anon;
revoke execute on function public.decide_activity_proposal(
  uuid, uuid, uuid, integer, text, text, text
) from public, anon;
revoke execute on function public.apply_activity_proposal(
  uuid, uuid, uuid, integer, text
) from public, anon;

grant execute on function public.materialize_activity_recurrence_rule(
  uuid, uuid, uuid, integer, date, date, text
) to authenticated;
grant execute on function public.decide_activity_proposal(
  uuid, uuid, uuid, integer, text, text, text
) to authenticated;
grant execute on function public.apply_activity_proposal(
  uuid, uuid, uuid, integer, text
) to authenticated;
