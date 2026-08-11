-- Phase 1: P6-compatible planning input ledger.
-- Calculated schedule results, progress history, baselines, and resources are deferred.

create table public.schedule_projects (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  cultivation_cycle_id uuid,
  project_code text not null,
  name text not null,
  description text,
  status text not null default 'PLANNED',
  planned_start_at timestamptz,
  planned_finish_at timestamptz,
  data_date timestamptz,
  timezone text not null,
  default_percent_complete_type text not null default 'DURATION',
  default_calendar_id uuid,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete set null,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint schedule_projects_farm_code_key unique (farm_id, project_code),
  constraint schedule_projects_farm_id_id_key unique (farm_id, id),
  constraint schedule_projects_code_format_check
    check (project_code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'),
  constraint schedule_projects_status_check
    check (status in ('PLANNED', 'ACTIVE', 'COMPLETED', 'ON_HOLD', 'CANCELLED')),
  constraint schedule_projects_percent_complete_type_check
    check (default_percent_complete_type in ('DURATION', 'UNITS', 'PHYSICAL')),
  constraint schedule_projects_planned_range_check
    check (
      planned_finish_at is null
      or planned_start_at is null
      or planned_finish_at >= planned_start_at
    ),
  constraint schedule_projects_version_check check (version >= 1),
  constraint schedule_projects_cycle_same_farm_fkey
    foreign key (farm_id, cultivation_cycle_id)
    references public.cultivation_cycles(farm_id, id)
    on delete set null (cultivation_cycle_id)
);

create table public.schedule_calendars (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  base_calendar_id uuid,
  calendar_code text not null,
  name text not null,
  calendar_scope text not null default 'PROJECT',
  timezone text not null,
  minutes_per_day integer not null default 480,
  minutes_per_week integer not null default 2400,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint schedule_calendars_project_code_key unique (project_id, calendar_code),
  constraint schedule_calendars_project_id_id_key unique (project_id, id),
  constraint schedule_calendars_farm_project_id_id_key unique (farm_id, project_id, id),
  constraint schedule_calendars_code_format_check
    check (calendar_code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'),
  constraint schedule_calendars_scope_check check (calendar_scope = 'PROJECT'),
  constraint schedule_calendars_minutes_per_day_check
    check (minutes_per_day > 0 and minutes_per_day <= 1440),
  constraint schedule_calendars_minutes_per_week_check
    check (minutes_per_week > 0 and minutes_per_week <= 10080),
  constraint schedule_calendars_project_same_farm_fkey
    foreign key (farm_id, project_id)
    references public.schedule_projects(farm_id, id)
    on delete cascade,
  constraint schedule_calendars_base_same_project_fkey
    foreign key (project_id, base_calendar_id)
    references public.schedule_calendars(project_id, id)
    on delete set null (base_calendar_id)
);

alter table public.schedule_projects
  add constraint schedule_projects_default_calendar_same_project_fkey
  foreign key (id, default_calendar_id)
  references public.schedule_calendars(project_id, id)
  deferrable initially deferred;

create table public.schedule_calendar_working_periods (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  calendar_id uuid not null,
  weekday smallint not null,
  start_time time not null,
  end_time time not null,
  created_at timestamptz not null default now(),
  constraint schedule_calendar_working_periods_slot_key
    unique (calendar_id, weekday, start_time),
  constraint schedule_calendar_working_periods_weekday_check
    check (weekday between 0 and 6),
  constraint schedule_calendar_working_periods_range_check
    check (end_time > start_time),
  constraint schedule_calendar_working_periods_calendar_same_project_fkey
    foreign key (farm_id, project_id, calendar_id)
    references public.schedule_calendars(farm_id, project_id, id)
    on delete cascade
);

create table public.schedule_calendar_exceptions (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  calendar_id uuid not null,
  exception_date date not null,
  exception_type text not null,
  reason_code text not null default 'OTHER',
  reason text,
  start_time time,
  end_time time,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint schedule_calendar_exceptions_slot_key
    unique nulls not distinct (calendar_id, exception_date, start_time, end_time),
  constraint schedule_calendar_exceptions_type_check
    check (exception_type in ('NON_WORKING', 'WORKING')),
  constraint schedule_calendar_exceptions_reason_code_check
    check (reason_code in ('HOLIDAY', 'WEATHER', 'FARM_CLOSURE', 'SAFETY', 'OTHER')),
  constraint schedule_calendar_exceptions_time_pair_check
    check (
      (start_time is null and end_time is null)
      or (start_time is not null and end_time is not null and end_time > start_time)
    ),
  constraint schedule_calendar_exceptions_working_time_check
    check (
      exception_type <> 'WORKING'
      or (start_time is not null and end_time is not null)
    ),
  constraint schedule_calendar_exceptions_calendar_same_project_fkey
    foreign key (farm_id, project_id, calendar_id)
    references public.schedule_calendars(farm_id, project_id, id)
    on delete cascade
);

create or replace function public.validate_calendar_working_period_overlap()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.schedule_calendar_working_periods as existing
    where existing.calendar_id = new.calendar_id
      and existing.weekday = new.weekday
      and existing.id <> new.id
      and new.start_time < existing.end_time
      and new.end_time > existing.start_time
  ) then
    raise exception 'Calendar working periods cannot overlap';
  end if;

  return new;
end;
$$;

create trigger validate_schedule_calendar_working_period_overlap
before insert or update on public.schedule_calendar_working_periods
for each row execute function public.validate_calendar_working_period_overlap();

create table public.schedule_wbs_nodes (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  parent_id uuid,
  wbs_code text not null,
  name text not null,
  description text,
  sequence_no integer not null default 0,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint schedule_wbs_nodes_project_code_key unique (project_id, wbs_code),
  constraint schedule_wbs_nodes_project_id_id_key unique (project_id, id),
  constraint schedule_wbs_nodes_farm_project_id_id_key unique (farm_id, project_id, id),
  constraint schedule_wbs_nodes_code_format_check
    check (wbs_code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'),
  constraint schedule_wbs_nodes_sequence_check check (sequence_no >= 0),
  constraint schedule_wbs_nodes_project_same_farm_fkey
    foreign key (farm_id, project_id)
    references public.schedule_projects(farm_id, id)
    on delete cascade,
  constraint schedule_wbs_nodes_parent_same_project_fkey
    foreign key (farm_id, project_id, parent_id)
    references public.schedule_wbs_nodes(farm_id, project_id, id)
    on delete cascade
);

create unique index schedule_wbs_nodes_one_root_idx
on public.schedule_wbs_nodes(project_id)
where parent_id is null;

create or replace function public.validate_schedule_wbs_parent()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE'
     and old.parent_id is null
     and new.parent_id is not null then
    raise exception 'The project root WBS cannot be reparented';
  end if;

  if new.parent_id is null then
    return new;
  end if;

  if new.parent_id = new.id then
    raise exception 'A WBS node cannot be its own parent';
  end if;

  if exists (
    with recursive ancestors as (
      select node.id, node.parent_id
      from public.schedule_wbs_nodes as node
      where node.farm_id = new.farm_id
        and node.project_id = new.project_id
        and node.id = new.parent_id

      union

      select parent.id, parent.parent_id
      from public.schedule_wbs_nodes as parent
      join ancestors on ancestors.parent_id = parent.id
      where parent.farm_id = new.farm_id
        and parent.project_id = new.project_id
    )
    select 1
    from ancestors
    where id = new.id
  ) then
    raise exception 'A WBS hierarchy cycle is not allowed';
  end if;

  return new;
end;
$$;

create trigger validate_schedule_wbs_parent
before insert or update of farm_id, project_id, parent_id
on public.schedule_wbs_nodes
for each row execute function public.validate_schedule_wbs_parent();

create table public.schedule_activities (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  wbs_id uuid not null,
  calendar_id uuid not null,
  cultivation_cycle_id uuid,
  operation_type_code text not null default 'other',
  activity_code text not null,
  name text not null,
  description text,
  activity_type text not null default 'TASK_DEPENDENT',
  status text not null default 'NOT_STARTED',
  percent_complete_type text not null default 'DURATION',
  planned_start_at timestamptz,
  planned_finish_at timestamptz,
  planned_duration_minutes integer not null default 0,
  actual_start_at timestamptz,
  actual_finish_at timestamptz,
  remaining_duration_minutes integer,
  primary_constraint_type text,
  primary_constraint_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete set null,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint schedule_activities_project_code_key unique (project_id, activity_code),
  constraint schedule_activities_project_id_id_key unique (project_id, id),
  constraint schedule_activities_farm_project_id_id_key unique (farm_id, project_id, id),
  constraint schedule_activities_code_format_check
    check (activity_code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'),
  constraint schedule_activities_type_check
    check (activity_type in (
      'TASK_DEPENDENT',
      'RESOURCE_DEPENDENT',
      'LEVEL_OF_EFFORT',
      'START_MILESTONE',
      'FINISH_MILESTONE',
      'WBS_SUMMARY'
    )),
  constraint schedule_activities_status_check
    check (status in ('NOT_STARTED', 'IN_PROGRESS', 'COMPLETED')),
  constraint schedule_activities_percent_complete_type_check
    check (percent_complete_type in ('DURATION', 'UNITS', 'PHYSICAL')),
  constraint schedule_activities_duration_check
    check (
      planned_duration_minutes >= 0
      and (remaining_duration_minutes is null or remaining_duration_minutes >= 0)
    ),
  constraint schedule_activities_milestone_duration_check
    check (
      activity_type not in ('START_MILESTONE', 'FINISH_MILESTONE')
      or planned_duration_minutes = 0
    ),
  constraint schedule_activities_planned_range_check
    check (
      planned_finish_at is null
      or planned_start_at is null
      or planned_finish_at >= planned_start_at
    ),
  constraint schedule_activities_actual_range_check
    check (
      actual_finish_at is null
      or actual_start_at is not null and actual_finish_at >= actual_start_at
    ),
  constraint schedule_activities_status_actual_dates_check
    check (
      (status = 'NOT_STARTED' and actual_start_at is null and actual_finish_at is null)
      or (status = 'IN_PROGRESS' and actual_start_at is not null and actual_finish_at is null)
      or (status = 'COMPLETED' and actual_start_at is not null and actual_finish_at is not null)
    ),
  constraint schedule_activities_constraint_type_check
    check (
      primary_constraint_type is null
      or primary_constraint_type in (
        'START_ON',
        'START_ON_OR_AFTER',
        'FINISH_ON',
        'FINISH_ON_OR_BEFORE',
        'MANDATORY_START',
        'MANDATORY_FINISH'
      )
    ),
  constraint schedule_activities_constraint_pair_check
    check (
      (primary_constraint_type is null and primary_constraint_at is null)
      or (primary_constraint_type is not null and primary_constraint_at is not null)
    ),
  constraint schedule_activities_version_check check (version >= 1),
  constraint schedule_activities_project_same_farm_fkey
    foreign key (farm_id, project_id)
    references public.schedule_projects(farm_id, id)
    on delete cascade,
  constraint schedule_activities_wbs_same_project_fkey
    foreign key (farm_id, project_id, wbs_id)
    references public.schedule_wbs_nodes(farm_id, project_id, id)
    on delete restrict,
  constraint schedule_activities_calendar_same_project_fkey
    foreign key (farm_id, project_id, calendar_id)
    references public.schedule_calendars(farm_id, project_id, id)
    on delete restrict,
  constraint schedule_activities_cycle_same_farm_fkey
    foreign key (farm_id, cultivation_cycle_id)
    references public.cultivation_cycles(farm_id, id)
    on delete set null (cultivation_cycle_id),
  constraint schedule_activities_operation_type_fkey
    foreign key (operation_type_code)
    references public.agri_operation_types(code)
);

create table public.schedule_activity_work_areas (
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  activity_id uuid not null,
  work_area_id uuid not null,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (activity_id, work_area_id),
  constraint schedule_activity_work_areas_activity_same_project_fkey
    foreign key (farm_id, project_id, activity_id)
    references public.schedule_activities(farm_id, project_id, id)
    on delete cascade,
  constraint schedule_activity_work_areas_area_same_farm_fkey
    foreign key (farm_id, work_area_id)
    references public.farm_work_areas(farm_id, id)
    on delete cascade
);

create unique index schedule_activity_work_areas_one_primary_idx
on public.schedule_activity_work_areas(activity_id)
where is_primary;

create table public.schedule_activity_relationships (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  predecessor_activity_id uuid not null,
  successor_activity_id uuid not null,
  relationship_type text not null default 'FS',
  lag_minutes integer not null default 0,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint schedule_activity_relationships_edge_key
    unique (
      predecessor_activity_id,
      successor_activity_id,
      relationship_type
    ),
  constraint schedule_activity_relationships_type_check
    check (relationship_type in ('FS', 'SS', 'FF', 'SF')),
  constraint schedule_activity_relationships_no_self_check
    check (predecessor_activity_id <> successor_activity_id),
  constraint schedule_activity_relationships_predecessor_same_project_fkey
    foreign key (farm_id, project_id, predecessor_activity_id)
    references public.schedule_activities(farm_id, project_id, id)
    on delete cascade,
  constraint schedule_activity_relationships_successor_same_project_fkey
    foreign key (farm_id, project_id, successor_activity_id)
    references public.schedule_activities(farm_id, project_id, id)
    on delete cascade
);

create or replace function public.validate_schedule_relationship_cycle()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.predecessor_activity_id = new.successor_activity_id then
    raise exception 'An activity relationship cannot reference itself';
  end if;

  if exists (
    with recursive reachable as (
      select relationship.successor_activity_id as activity_id
      from public.schedule_activity_relationships as relationship
      where relationship.project_id = new.project_id
        and relationship.predecessor_activity_id = new.successor_activity_id
        and relationship.id <> new.id

      union

      select relationship.successor_activity_id
      from public.schedule_activity_relationships as relationship
      join reachable
        on relationship.predecessor_activity_id = reachable.activity_id
      where relationship.project_id = new.project_id
        and relationship.id <> new.id
    )
    select 1
    from reachable
    where activity_id = new.predecessor_activity_id
  ) then
    raise exception 'An activity relationship cycle is not allowed';
  end if;

  return new;
end;
$$;

create trigger validate_schedule_relationship_cycle
before insert or update of
  project_id,
  predecessor_activity_id,
  successor_activity_id
on public.schedule_activity_relationships
for each row execute function public.validate_schedule_relationship_cycle();

create table public.task_activity_links (
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  task_id uuid not null,
  activity_id uuid not null,
  link_type text not null default 'REFERENCE',
  is_primary boolean not null default false,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  primary key (task_id, activity_id),
  constraint task_activity_links_type_check
    check (link_type in ('MIGRATED', 'EXECUTION', 'FOLLOW_UP', 'REFERENCE')),
  constraint task_activity_links_task_same_farm_fkey
    foreign key (farm_id, task_id)
    references public.tasks(farm_id, id)
    on delete cascade,
  constraint task_activity_links_activity_same_project_fkey
    foreign key (farm_id, project_id, activity_id)
    references public.schedule_activities(farm_id, project_id, id)
    on delete cascade
);

create unique index task_activity_links_one_primary_task_idx
on public.task_activity_links(task_id)
where is_primary;

create or replace function public.validate_task_activity_cycle()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  task_cycle_id uuid;
  activity_cycle_id uuid;
begin
  select cultivation_cycle_id
  into task_cycle_id
  from public.tasks
  where farm_id = new.farm_id
    and id = new.task_id;

  select cultivation_cycle_id
  into activity_cycle_id
  from public.schedule_activities
  where farm_id = new.farm_id
    and project_id = new.project_id
    and id = new.activity_id;

  if task_cycle_id is not null
     and activity_cycle_id is not null
     and task_cycle_id <> activity_cycle_id then
    raise exception 'Task and activity cultivation cycles must match';
  end if;

  return new;
end;
$$;

create trigger validate_task_activity_cycle
before insert or update of farm_id, project_id, task_id, activity_id
on public.task_activity_links
for each row execute function public.validate_task_activity_cycle();

create index schedule_projects_farm_status_idx
on public.schedule_projects(farm_id, status, planned_start_at);

create index schedule_calendars_project_idx
on public.schedule_calendars(project_id);

create index schedule_calendar_exceptions_lookup_idx
on public.schedule_calendar_exceptions(calendar_id, exception_date);

create index schedule_wbs_nodes_parent_idx
on public.schedule_wbs_nodes(project_id, parent_id, sequence_no);

create index schedule_activities_wbs_idx
on public.schedule_activities(project_id, wbs_id, activity_code);

create index schedule_activities_cycle_operation_idx
on public.schedule_activities(farm_id, cultivation_cycle_id, operation_type_code);

create index schedule_activity_relationships_successor_idx
on public.schedule_activity_relationships(project_id, successor_activity_id);

create index task_activity_links_activity_idx
on public.task_activity_links(project_id, activity_id);

create trigger set_schedule_projects_updated_at
before update on public.schedule_projects
for each row execute function public.set_updated_at();

create trigger set_schedule_calendars_updated_at
before update on public.schedule_calendars
for each row execute function public.set_updated_at();

create trigger set_schedule_wbs_nodes_updated_at
before update on public.schedule_wbs_nodes
for each row execute function public.set_updated_at();

create trigger set_schedule_activities_updated_at
before update on public.schedule_activities
for each row execute function public.set_updated_at();

create trigger set_schedule_activity_relationships_updated_at
before update on public.schedule_activity_relationships
for each row execute function public.set_updated_at();

alter table public.schedule_projects enable row level security;
alter table public.schedule_calendars enable row level security;
alter table public.schedule_calendar_working_periods enable row level security;
alter table public.schedule_calendar_exceptions enable row level security;
alter table public.schedule_wbs_nodes enable row level security;
alter table public.schedule_activities enable row level security;
alter table public.schedule_activity_work_areas enable row level security;
alter table public.schedule_activity_relationships enable row level security;
alter table public.task_activity_links enable row level security;

create policy members_read_schedule_projects
on public.schedule_projects
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_manage_schedule_projects
on public.schedule_projects
for all to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_read_schedule_calendars
on public.schedule_calendars
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_manage_schedule_calendars
on public.schedule_calendars
for all to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_read_schedule_working_periods
on public.schedule_calendar_working_periods
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_manage_schedule_working_periods
on public.schedule_calendar_working_periods
for all to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_read_schedule_exceptions
on public.schedule_calendar_exceptions
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_manage_schedule_exceptions
on public.schedule_calendar_exceptions
for all to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_read_schedule_wbs
on public.schedule_wbs_nodes
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_manage_schedule_wbs
on public.schedule_wbs_nodes
for all to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_read_schedule_activities
on public.schedule_activities
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_manage_schedule_activities
on public.schedule_activities
for all to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_read_schedule_activity_areas
on public.schedule_activity_work_areas
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_manage_schedule_activity_areas
on public.schedule_activity_work_areas
for all to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_read_schedule_relationships
on public.schedule_activity_relationships
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_manage_schedule_relationships
on public.schedule_activity_relationships
for all to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_read_task_activity_links
on public.task_activity_links
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_manage_task_activity_links
on public.task_activity_links
for all to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

grant select, insert, update, delete on table
  public.schedule_projects,
  public.schedule_calendars,
  public.schedule_calendar_working_periods,
  public.schedule_calendar_exceptions,
  public.schedule_wbs_nodes,
  public.schedule_activities,
  public.schedule_activity_work_areas,
  public.schedule_activity_relationships,
  public.task_activity_links
to authenticated;

revoke all on table
  public.schedule_projects,
  public.schedule_calendars,
  public.schedule_calendar_working_periods,
  public.schedule_calendar_exceptions,
  public.schedule_wbs_nodes,
  public.schedule_activities,
  public.schedule_activity_work_areas,
  public.schedule_activity_relationships,
  public.task_activity_links
from anon;

revoke truncate, trigger, references on table
  public.schedule_projects,
  public.schedule_calendars,
  public.schedule_calendar_working_periods,
  public.schedule_calendar_exceptions,
  public.schedule_wbs_nodes,
  public.schedule_activities,
  public.schedule_activity_work_areas,
  public.schedule_activity_relationships,
  public.task_activity_links
from authenticated;

create or replace function public.create_schedule_project(
  target_farm_id uuid,
  target_cycle_id uuid,
  project_code text,
  project_name text,
  project_timezone text,
  root_wbs_code text,
  root_wbs_name text,
  calendar_code text,
  calendar_name text,
  calendar_working_periods jsonb,
  project_description text default null,
  project_status text default 'PLANNED',
  project_planned_start_at timestamptz default null,
  project_planned_finish_at timestamptz default null,
  project_data_date timestamptz default null,
  project_percent_complete_type text default 'DURATION',
  calendar_minutes_per_day integer default 480,
  calendar_minutes_per_week integer default 2400
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  created_project public.schedule_projects;
  created_calendar public.schedule_calendars;
  created_root public.schedule_wbs_nodes;
  created_working_periods jsonb;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to create a schedule project';
  end if;

  if target_cycle_id is not null and not exists (
    select 1
    from public.cultivation_cycles
    where farm_id = target_farm_id
      and id = target_cycle_id
  ) then
    raise exception 'Cultivation cycle was not found for this farm';
  end if;

  if nullif(trim(project_code), '') is null
     or nullif(trim(project_name), '') is null
     or nullif(trim(root_wbs_code), '') is null
     or nullif(trim(root_wbs_name), '') is null
     or nullif(trim(calendar_code), '') is null
     or nullif(trim(calendar_name), '') is null then
    raise exception 'Project, root WBS, and calendar codes and names are required';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_timezone_names
    where name = project_timezone
  ) then
    raise exception 'A valid IANA project timezone is required';
  end if;

  if jsonb_typeof(calendar_working_periods) <> 'array'
     or jsonb_array_length(calendar_working_periods) = 0 then
    raise exception 'At least one calendar working period is required';
  end if;

  insert into public.schedule_projects (
    farm_id,
    cultivation_cycle_id,
    project_code,
    name,
    description,
    status,
    planned_start_at,
    planned_finish_at,
    data_date,
    timezone,
    default_percent_complete_type,
    created_by,
    updated_by
  )
  values (
    target_farm_id,
    target_cycle_id,
    trim(project_code),
    trim(project_name),
    nullif(trim(project_description), ''),
    project_status,
    project_planned_start_at,
    project_planned_finish_at,
    project_data_date,
    project_timezone,
    project_percent_complete_type,
    auth.uid(),
    auth.uid()
  )
  returning * into created_project;

  insert into public.schedule_calendars (
    farm_id,
    project_id,
    calendar_code,
    name,
    timezone,
    minutes_per_day,
    minutes_per_week,
    created_by
  )
  values (
    target_farm_id,
    created_project.id,
    trim(calendar_code),
    trim(calendar_name),
    project_timezone,
    calendar_minutes_per_day,
    calendar_minutes_per_week,
    auth.uid()
  )
  returning * into created_calendar;

  insert into public.schedule_calendar_working_periods (
    farm_id,
    project_id,
    calendar_id,
    weekday,
    start_time,
    end_time
  )
  select
    target_farm_id,
    created_project.id,
    created_calendar.id,
    (period ->> 'weekday')::smallint,
    (period ->> 'start_time')::time,
    (period ->> 'end_time')::time
  from jsonb_array_elements(calendar_working_periods) as periods(period);

  update public.schedule_projects
  set default_calendar_id = created_calendar.id,
      updated_by = auth.uid(),
      updated_at = now()
  where id = created_project.id
  returning * into created_project;

  insert into public.schedule_wbs_nodes (
    farm_id,
    project_id,
    parent_id,
    wbs_code,
    name,
    sequence_no,
    created_by
  )
  values (
    target_farm_id,
    created_project.id,
    null,
    trim(root_wbs_code),
    trim(root_wbs_name),
    0,
    auth.uid()
  )
  returning * into created_root;

  select coalesce(
    jsonb_agg(to_jsonb(period) order by period.weekday, period.start_time),
    '[]'::jsonb
  )
  into created_working_periods
  from public.schedule_calendar_working_periods as period
  where period.calendar_id = created_calendar.id;

  return jsonb_build_object(
    'project', to_jsonb(created_project),
    'default_calendar',
      to_jsonb(created_calendar)
      || jsonb_build_object('working_periods', created_working_periods),
    'root_wbs', to_jsonb(created_root)
  );
end;
$$;

create or replace function public.create_schedule_wbs_node(
  target_farm_id uuid,
  target_project_id uuid,
  target_parent_id uuid,
  node_code text,
  node_name text,
  node_description text default null,
  node_sequence integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  created_node public.schedule_wbs_nodes;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to create a WBS node';
  end if;

  if not exists (
    select 1
    from public.schedule_projects
    where farm_id = target_farm_id
      and id = target_project_id
  ) then
    raise exception 'Schedule project was not found for this farm';
  end if;

  if target_parent_id is null or not exists (
    select 1
    from public.schedule_wbs_nodes
    where farm_id = target_farm_id
      and project_id = target_project_id
      and id = target_parent_id
  ) then
    raise exception 'Parent WBS was not found for this project';
  end if;

  insert into public.schedule_wbs_nodes (
    farm_id,
    project_id,
    parent_id,
    wbs_code,
    name,
    description,
    sequence_no,
    created_by
  )
  values (
    target_farm_id,
    target_project_id,
    target_parent_id,
    trim(node_code),
    trim(node_name),
    nullif(trim(node_description), ''),
    node_sequence,
    auth.uid()
  )
  returning * into created_node;

  return to_jsonb(created_node);
end;
$$;

create or replace function public.create_schedule_activity(
  target_farm_id uuid,
  target_project_id uuid,
  target_wbs_id uuid,
  activity_code text,
  activity_name text,
  activity_type text,
  target_calendar_id uuid default null,
  target_cycle_id uuid default null,
  target_operation_type_code text default 'other',
  activity_description text default null,
  activity_percent_complete_type text default 'DURATION',
  activity_planned_start_at timestamptz default null,
  activity_planned_finish_at timestamptz default null,
  activity_planned_duration_minutes integer default 0,
  activity_constraint_type text default null,
  activity_constraint_at timestamptz default null,
  target_work_area_ids uuid[] default array[]::uuid[],
  target_task_id uuid default null,
  task_link_type text default 'REFERENCE'
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_project public.schedule_projects;
  selected_calendar_id uuid;
  selected_cycle_id uuid;
  created_activity public.schedule_activities;
  linked_work_area_ids uuid[];
  created_task_link public.task_activity_links;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to create a schedule activity';
  end if;

  select *
  into current_project
  from public.schedule_projects
  where farm_id = target_farm_id
    and id = target_project_id;

  if not found then
    raise exception 'Schedule project was not found for this farm';
  end if;

  if not exists (
    select 1
    from public.schedule_wbs_nodes
    where farm_id = target_farm_id
      and project_id = target_project_id
      and id = target_wbs_id
  ) then
    raise exception 'WBS node was not found for this project';
  end if;

  selected_calendar_id := coalesce(
    target_calendar_id,
    current_project.default_calendar_id
  );
  if selected_calendar_id is null or not exists (
    select 1
    from public.schedule_calendars
    where farm_id = target_farm_id
      and project_id = target_project_id
      and id = selected_calendar_id
  ) then
    raise exception 'Calendar was not found for this project';
  end if;

  selected_cycle_id := coalesce(
    target_cycle_id,
    current_project.cultivation_cycle_id
  );
  if selected_cycle_id is not null and not exists (
    select 1
    from public.cultivation_cycles
    where farm_id = target_farm_id
      and id = selected_cycle_id
  ) then
    raise exception 'Cultivation cycle was not found for this farm';
  end if;

  if not exists (
    select 1
    from public.agri_operation_types
    where code = target_operation_type_code
      and is_active
  ) then
    raise exception 'Active agricultural operation type is required';
  end if;

  if exists (
    select 1
    from unnest(coalesce(target_work_area_ids, array[]::uuid[])) as requested(id)
    left join public.farm_work_areas as area
      on area.farm_id = target_farm_id
     and area.id = requested.id
    where area.id is null
  ) then
    raise exception 'A work area was not found for this farm';
  end if;

  if target_task_id is not null and not exists (
    select 1
    from public.tasks
    where farm_id = target_farm_id
      and id = target_task_id
  ) then
    raise exception 'Task was not found for this farm';
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
    primary_constraint_type,
    primary_constraint_at,
    created_by,
    updated_by
  )
  values (
    target_farm_id,
    target_project_id,
    target_wbs_id,
    selected_calendar_id,
    selected_cycle_id,
    target_operation_type_code,
    trim(activity_code),
    trim(activity_name),
    nullif(trim(activity_description), ''),
    activity_type,
    'NOT_STARTED',
    activity_percent_complete_type,
    activity_planned_start_at,
    activity_planned_finish_at,
    activity_planned_duration_minutes,
    activity_planned_duration_minutes,
    nullif(trim(activity_constraint_type), ''),
    activity_constraint_at,
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
    target_farm_id,
    target_project_id,
    created_activity.id,
    requested.id,
    row_number() over (order by requested.id) = 1
  from (
    select distinct id
    from unnest(coalesce(target_work_area_ids, array[]::uuid[])) as ids(id)
  ) as requested;

  if target_task_id is not null then
    insert into public.task_activity_links (
      farm_id,
      project_id,
      task_id,
      activity_id,
      link_type,
      is_primary,
      created_by
    )
    values (
      target_farm_id,
      target_project_id,
      target_task_id,
      created_activity.id,
      task_link_type,
      true,
      auth.uid()
    )
    returning * into created_task_link;
  end if;

  select coalesce(array_agg(work_area_id order by work_area_id), array[]::uuid[])
  into linked_work_area_ids
  from public.schedule_activity_work_areas
  where activity_id = created_activity.id;

  return to_jsonb(created_activity)
    || jsonb_build_object(
      'work_area_ids',
      linked_work_area_ids,
      'task_link',
      to_jsonb(created_task_link)
    );
end;
$$;

create or replace function public.create_schedule_relationship(
  target_farm_id uuid,
  target_project_id uuid,
  predecessor_id uuid,
  successor_id uuid,
  relationship_kind text default 'FS',
  relationship_lag_minutes integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  created_relationship public.schedule_activity_relationships;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to create a relationship';
  end if;

  if not exists (
    select 1
    from public.schedule_projects
    where farm_id = target_farm_id
      and id = target_project_id
  ) then
    raise exception 'Schedule project was not found for this farm';
  end if;

  if not exists (
    select 1
    from public.schedule_activities
    where farm_id = target_farm_id
      and project_id = target_project_id
      and id = predecessor_id
  ) or not exists (
    select 1
    from public.schedule_activities
    where farm_id = target_farm_id
      and project_id = target_project_id
      and id = successor_id
  ) then
    raise exception 'Both activities must belong to this project';
  end if;

  insert into public.schedule_activity_relationships (
    farm_id,
    project_id,
    predecessor_activity_id,
    successor_activity_id,
    relationship_type,
    lag_minutes,
    created_by
  )
  values (
    target_farm_id,
    target_project_id,
    predecessor_id,
    successor_id,
    relationship_kind,
    relationship_lag_minutes,
    auth.uid()
  )
  returning * into created_relationship;

  return to_jsonb(created_relationship);
end;
$$;

create or replace function public.link_task_to_activity(
  target_farm_id uuid,
  target_project_id uuid,
  target_task_id uuid,
  target_activity_id uuid,
  target_link_type text default 'REFERENCE',
  target_is_primary boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  created_link public.task_activity_links;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to link a task and activity';
  end if;

  insert into public.task_activity_links (
    farm_id,
    project_id,
    task_id,
    activity_id,
    link_type,
    is_primary,
    created_by
  )
  values (
    target_farm_id,
    target_project_id,
    target_task_id,
    target_activity_id,
    target_link_type,
    target_is_primary,
    auth.uid()
  )
  returning * into created_link;

  return to_jsonb(created_link);
end;
$$;

grant execute on function public.create_schedule_project(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  jsonb,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  text,
  integer,
  integer
) to authenticated;

grant execute on function public.create_schedule_wbs_node(
  uuid, uuid, uuid, text, text, text, integer
) to authenticated;

grant execute on function public.create_schedule_activity(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  uuid,
  uuid,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  integer,
  text,
  timestamptz,
  uuid[],
  uuid,
  text
) to authenticated;

grant execute on function public.create_schedule_relationship(
  uuid, uuid, uuid, uuid, text, integer
) to authenticated;

grant execute on function public.link_task_to_activity(
  uuid, uuid, uuid, uuid, text, boolean
) to authenticated;

revoke execute on function public.create_schedule_project(
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  text,
  text,
  text,
  jsonb,
  text,
  text,
  timestamptz,
  timestamptz,
  timestamptz,
  text,
  integer,
  integer
) from public;

revoke execute on function public.create_schedule_wbs_node(
  uuid, uuid, uuid, text, text, text, integer
) from public;

revoke execute on function public.create_schedule_activity(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  uuid,
  uuid,
  text,
  text,
  text,
  timestamptz,
  timestamptz,
  integer,
  text,
  timestamptz,
  uuid[],
  uuid,
  text
) from public;

revoke execute on function public.create_schedule_relationship(
  uuid, uuid, uuid, uuid, text, integer
) from public;

revoke execute on function public.link_task_to_activity(
  uuid, uuid, uuid, uuid, text, boolean
) from public;

revoke execute on function public.validate_calendar_working_period_overlap()
from public, anon, authenticated;

revoke execute on function public.validate_schedule_wbs_parent()
from public, anon, authenticated;

revoke execute on function public.validate_schedule_relationship_cycle()
from public, anon, authenticated;

revoke execute on function public.validate_task_activity_cycle()
from public, anon, authenticated;
