-- Phase 1B: relational activity templates, recurrence rules, and trigger rules.

create table public.activity_templates (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  template_code text not null,
  name text not null,
  description text,
  operation_type_code text not null references public.agri_operation_types(code),
  activity_type text not null default 'TASK_DEPENDENT',
  percent_complete_type text not null default 'DURATION',
  default_duration_minutes integer not null default 0,
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete set null,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint activity_templates_farm_code_key unique (farm_id, template_code),
  constraint activity_templates_farm_id_id_key unique (farm_id, id),
  constraint activity_templates_code_format_check
    check (template_code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'),
  constraint activity_templates_type_check
    check (activity_type in (
      'TASK_DEPENDENT',
      'RESOURCE_DEPENDENT',
      'LEVEL_OF_EFFORT',
      'START_MILESTONE',
      'FINISH_MILESTONE',
      'WBS_SUMMARY'
    )),
  constraint activity_templates_percent_complete_type_check
    check (percent_complete_type in ('DURATION', 'UNITS', 'PHYSICAL')),
  constraint activity_templates_duration_check
    check (default_duration_minutes >= 0),
  constraint activity_templates_milestone_duration_check
    check (
      activity_type not in ('START_MILESTONE', 'FINISH_MILESTONE')
      or default_duration_minutes = 0
    ),
  constraint activity_templates_version_check check (version >= 1)
);

create table public.activity_recurrence_rules (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  template_id uuid not null,
  wbs_id uuid not null,
  calendar_id uuid not null,
  cultivation_cycle_id uuid,
  rule_code text not null,
  name text not null,
  status text not null default 'DRAFT',
  frequency text not null,
  interval_count integer not null default 1,
  day_of_month smallint,
  starts_on date not null,
  ends_on date,
  occurrence_time time not null,
  timezone text not null,
  generation_horizon_days integer not null default 30,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete set null,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint activity_recurrence_rules_project_code_key
    unique (project_id, rule_code),
  constraint activity_recurrence_rules_farm_project_id_id_key
    unique (farm_id, project_id, id),
  constraint activity_recurrence_rules_code_format_check
    check (rule_code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'),
  constraint activity_recurrence_rules_status_check
    check (status in ('DRAFT', 'ACTIVE', 'PAUSED', 'ARCHIVED')),
  constraint activity_recurrence_rules_frequency_check
    check (frequency in ('DAILY', 'WEEKLY', 'MONTHLY')),
  constraint activity_recurrence_rules_interval_check
    check (interval_count >= 1),
  constraint activity_recurrence_rules_month_day_check
    check (
      (frequency = 'MONTHLY' and day_of_month between 1 and 31)
      or (frequency <> 'MONTHLY' and day_of_month is null)
    ),
  constraint activity_recurrence_rules_date_range_check
    check (ends_on is null or ends_on >= starts_on),
  constraint activity_recurrence_rules_horizon_check
    check (generation_horizon_days between 1 and 366),
  constraint activity_recurrence_rules_version_check check (version >= 1),
  constraint activity_recurrence_rules_project_same_farm_fkey
    foreign key (farm_id, project_id)
    references public.schedule_projects(farm_id, id)
    on delete cascade,
  constraint activity_recurrence_rules_template_same_farm_fkey
    foreign key (farm_id, template_id)
    references public.activity_templates(farm_id, id)
    on delete restrict,
  constraint activity_recurrence_rules_wbs_same_project_fkey
    foreign key (farm_id, project_id, wbs_id)
    references public.schedule_wbs_nodes(farm_id, project_id, id)
    on delete restrict,
  constraint activity_recurrence_rules_calendar_same_project_fkey
    foreign key (farm_id, project_id, calendar_id)
    references public.schedule_calendars(farm_id, project_id, id)
    on delete restrict,
  constraint activity_recurrence_rules_cycle_same_farm_fkey
    foreign key (farm_id, cultivation_cycle_id)
    references public.cultivation_cycles(farm_id, id)
    on delete set null (cultivation_cycle_id)
);

create table public.activity_recurrence_weekdays (
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  recurrence_rule_id uuid not null,
  weekday smallint not null,
  created_at timestamptz not null default now(),
  primary key (recurrence_rule_id, weekday),
  constraint activity_recurrence_weekdays_weekday_check
    check (weekday between 0 and 6),
  constraint activity_recurrence_weekdays_rule_same_project_fkey
    foreign key (farm_id, project_id, recurrence_rule_id)
    references public.activity_recurrence_rules(farm_id, project_id, id)
    on delete cascade
);

create table public.activity_trigger_rules (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  template_id uuid not null,
  wbs_id uuid not null,
  calendar_id uuid not null,
  cultivation_cycle_id uuid,
  rule_code text not null,
  name text not null,
  status text not null default 'DRAFT',
  event_type text not null,
  predicate_match_mode text not null default 'ALL',
  cooldown_minutes integer not null default 0,
  valid_from timestamptz,
  valid_until timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  updated_by uuid references auth.users(id) on delete set null,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint activity_trigger_rules_project_code_key unique (project_id, rule_code),
  constraint activity_trigger_rules_farm_project_id_id_key
    unique (farm_id, project_id, id),
  constraint activity_trigger_rules_code_format_check
    check (rule_code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'),
  constraint activity_trigger_rules_status_check
    check (status in ('DRAFT', 'ACTIVE', 'PAUSED', 'ARCHIVED')),
  constraint activity_trigger_rules_event_type_check
    check (event_type in (
      'WEATHER_OBSERVATION',
      'SENSOR_OBSERVATION',
      'TASK_ACTION',
      'GROWTH_STAGE_CHANGE',
      'MANUAL'
    )),
  constraint activity_trigger_rules_match_mode_check
    check (predicate_match_mode in ('ALL', 'ANY')),
  constraint activity_trigger_rules_cooldown_check
    check (cooldown_minutes >= 0),
  constraint activity_trigger_rules_valid_range_check
    check (valid_until is null or valid_from is null or valid_until >= valid_from),
  constraint activity_trigger_rules_version_check check (version >= 1),
  constraint activity_trigger_rules_project_same_farm_fkey
    foreign key (farm_id, project_id)
    references public.schedule_projects(farm_id, id)
    on delete cascade,
  constraint activity_trigger_rules_template_same_farm_fkey
    foreign key (farm_id, template_id)
    references public.activity_templates(farm_id, id)
    on delete restrict,
  constraint activity_trigger_rules_wbs_same_project_fkey
    foreign key (farm_id, project_id, wbs_id)
    references public.schedule_wbs_nodes(farm_id, project_id, id)
    on delete restrict,
  constraint activity_trigger_rules_calendar_same_project_fkey
    foreign key (farm_id, project_id, calendar_id)
    references public.schedule_calendars(farm_id, project_id, id)
    on delete restrict,
  constraint activity_trigger_rules_cycle_same_farm_fkey
    foreign key (farm_id, cultivation_cycle_id)
    references public.cultivation_cycles(farm_id, id)
    on delete set null (cultivation_cycle_id)
);

create table public.activity_trigger_predicates (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  trigger_rule_id uuid not null,
  sequence_no integer not null,
  source_field_code text not null,
  comparison_operator text not null,
  numeric_value numeric,
  text_value text,
  boolean_value boolean,
  unit_code text,
  observation_window_minutes integer,
  created_at timestamptz not null default now(),
  constraint activity_trigger_predicates_rule_sequence_key
    unique (trigger_rule_id, sequence_no),
  constraint activity_trigger_predicates_sequence_check check (sequence_no >= 1),
  constraint activity_trigger_predicates_source_field_check
    check (source_field_code ~ '^[a-z][a-z0-9_.]*$'),
  constraint activity_trigger_predicates_operator_check
    check (comparison_operator in ('GT', 'GTE', 'LT', 'LTE', 'EQ', 'NEQ')),
  constraint activity_trigger_predicates_exactly_one_value_check
    check (num_nonnulls(numeric_value, text_value, boolean_value) = 1),
  constraint activity_trigger_predicates_unit_check
    check (
      unit_code is null
      or (
        numeric_value is not null
        and unit_code ~ '^[A-Za-z][A-Za-z0-9_./%-]*$'
      )
    ),
  constraint activity_trigger_predicates_window_check
    check (
      observation_window_minutes is null
      or observation_window_minutes >= 0
    ),
  constraint activity_trigger_predicates_rule_same_project_fkey
    foreign key (farm_id, project_id, trigger_rule_id)
    references public.activity_trigger_rules(farm_id, project_id, id)
    on delete cascade
);

create table public.activity_trigger_rule_work_areas (
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  trigger_rule_id uuid not null,
  work_area_id uuid not null,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (trigger_rule_id, work_area_id),
  constraint activity_trigger_rule_areas_rule_same_project_fkey
    foreign key (farm_id, project_id, trigger_rule_id)
    references public.activity_trigger_rules(farm_id, project_id, id)
    on delete cascade,
  constraint activity_trigger_rule_areas_area_same_farm_fkey
    foreign key (farm_id, work_area_id)
    references public.farm_work_areas(farm_id, id)
    on delete cascade
);

create unique index activity_trigger_rule_areas_one_primary_idx
on public.activity_trigger_rule_work_areas(trigger_rule_id)
where is_primary;

create or replace function public.validate_recurrence_weekday_frequency()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.activity_recurrence_rules
    where id = new.recurrence_rule_id
      and farm_id = new.farm_id
      and project_id = new.project_id
      and frequency = 'WEEKLY'
  ) then
    raise exception 'Weekday rows are only allowed for weekly recurrence rules';
  end if;

  return new;
end;
$$;

create trigger validate_recurrence_weekday_frequency
before insert or update on public.activity_recurrence_weekdays
for each row execute function public.validate_recurrence_weekday_frequency();

create or replace function public.validate_recurrence_frequency_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.frequency = 'WEEKLY'
     and new.frequency <> 'WEEKLY'
     and exists (
       select 1
       from public.activity_recurrence_weekdays
       where recurrence_rule_id = new.id
     ) then
    raise exception 'Remove recurrence weekdays before changing frequency';
  end if;

  return new;
end;
$$;

create trigger validate_recurrence_frequency_change
before update of frequency on public.activity_recurrence_rules
for each row execute function public.validate_recurrence_frequency_change();

create or replace function public.validate_active_recurrence_rule()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_rule_id uuid;
begin
  if tg_table_name = 'activity_recurrence_weekdays' then
    if tg_op = 'DELETE' then
      target_rule_id := old.recurrence_rule_id;
    else
      target_rule_id := new.recurrence_rule_id;
    end if;
  else
    target_rule_id := new.id;
  end if;

  if exists (
    select 1
    from public.activity_recurrence_rules as rule
    where rule.id = target_rule_id
      and rule.status = 'ACTIVE'
      and rule.frequency = 'WEEKLY'
  ) and not exists (
    select 1
    from public.activity_recurrence_weekdays
    where recurrence_rule_id = target_rule_id
  ) then
    raise exception 'An active weekly recurrence rule requires at least one weekday';
  end if;

  return null;
end;
$$;

create constraint trigger validate_active_recurrence_rule_row
after insert or update of status, frequency
on public.activity_recurrence_rules
deferrable initially deferred
for each row execute function public.validate_active_recurrence_rule();

create constraint trigger validate_active_recurrence_weekday_rows
after insert or update or delete
on public.activity_recurrence_weekdays
deferrable initially deferred
for each row execute function public.validate_active_recurrence_rule();

create or replace function public.validate_active_trigger_rule()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_rule_id uuid;
begin
  if tg_table_name = 'activity_trigger_predicates' then
    if tg_op = 'DELETE' then
      target_rule_id := old.trigger_rule_id;
    else
      target_rule_id := new.trigger_rule_id;
    end if;
  else
    target_rule_id := new.id;
  end if;

  if exists (
    select 1
    from public.activity_trigger_rules as rule
    where rule.id = target_rule_id
      and rule.status = 'ACTIVE'
      and rule.event_type <> 'MANUAL'
  ) and not exists (
    select 1
    from public.activity_trigger_predicates
    where trigger_rule_id = target_rule_id
  ) then
    raise exception 'An active non-manual trigger rule requires a predicate';
  end if;

  return null;
end;
$$;

create constraint trigger validate_active_trigger_rule_row
after insert or update of status, event_type
on public.activity_trigger_rules
deferrable initially deferred
for each row execute function public.validate_active_trigger_rule();

create constraint trigger validate_active_trigger_predicate_rows
after insert or update or delete
on public.activity_trigger_predicates
deferrable initially deferred
for each row execute function public.validate_active_trigger_rule();

create index activity_templates_farm_active_idx
on public.activity_templates(farm_id, is_active, template_code);

create index activity_recurrence_rules_project_status_idx
on public.activity_recurrence_rules(project_id, status, starts_on);

create index activity_trigger_rules_project_status_idx
on public.activity_trigger_rules(project_id, status, event_type);

create index activity_trigger_predicates_rule_idx
on public.activity_trigger_predicates(trigger_rule_id, sequence_no);

create trigger set_activity_templates_updated_at
before update on public.activity_templates
for each row execute function public.set_updated_at();

create trigger set_activity_recurrence_rules_updated_at
before update on public.activity_recurrence_rules
for each row execute function public.set_updated_at();

create trigger set_activity_trigger_rules_updated_at
before update on public.activity_trigger_rules
for each row execute function public.set_updated_at();

alter table public.activity_templates enable row level security;
alter table public.activity_recurrence_rules enable row level security;
alter table public.activity_recurrence_weekdays enable row level security;
alter table public.activity_trigger_rules enable row level security;
alter table public.activity_trigger_predicates enable row level security;
alter table public.activity_trigger_rule_work_areas enable row level security;

create policy members_read_activity_templates
on public.activity_templates
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_manage_activity_templates
on public.activity_templates
for all to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_read_recurrence_rules
on public.activity_recurrence_rules
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_manage_recurrence_rules
on public.activity_recurrence_rules
for all to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_read_recurrence_weekdays
on public.activity_recurrence_weekdays
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_manage_recurrence_weekdays
on public.activity_recurrence_weekdays
for all to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_read_trigger_rules
on public.activity_trigger_rules
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_manage_trigger_rules
on public.activity_trigger_rules
for all to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_read_trigger_predicates
on public.activity_trigger_predicates
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_manage_trigger_predicates
on public.activity_trigger_predicates
for all to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_read_trigger_rule_areas
on public.activity_trigger_rule_work_areas
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_manage_trigger_rule_areas
on public.activity_trigger_rule_work_areas
for all to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

grant select, insert, update, delete on table
  public.activity_templates,
  public.activity_recurrence_rules,
  public.activity_recurrence_weekdays,
  public.activity_trigger_rules,
  public.activity_trigger_predicates,
  public.activity_trigger_rule_work_areas
to authenticated;

revoke all on table
  public.activity_templates,
  public.activity_recurrence_rules,
  public.activity_recurrence_weekdays,
  public.activity_trigger_rules,
  public.activity_trigger_predicates,
  public.activity_trigger_rule_work_areas
from anon;

revoke truncate, trigger, references on table
  public.activity_templates,
  public.activity_recurrence_rules,
  public.activity_recurrence_weekdays,
  public.activity_trigger_rules,
  public.activity_trigger_predicates,
  public.activity_trigger_rule_work_areas
from authenticated;

create or replace function public.create_activity_template(
  target_farm_id uuid,
  template_code text,
  template_name text,
  target_operation_type_code text,
  template_activity_type text default 'TASK_DEPENDENT',
  template_percent_complete_type text default 'DURATION',
  template_default_duration_minutes integer default 0,
  template_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  created_template public.activity_templates;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to create an activity template';
  end if;

  if nullif(trim(template_code), '') is null
     or nullif(trim(template_name), '') is null then
    raise exception 'Template code and name are required';
  end if;

  if not exists (
    select 1
    from public.agri_operation_types
    where code = target_operation_type_code
      and is_active
  ) then
    raise exception 'Active agricultural operation type is required';
  end if;

  insert into public.activity_templates (
    farm_id,
    template_code,
    name,
    description,
    operation_type_code,
    activity_type,
    percent_complete_type,
    default_duration_minutes,
    created_by,
    updated_by
  )
  values (
    target_farm_id,
    trim(template_code),
    trim(template_name),
    nullif(trim(template_description), ''),
    target_operation_type_code,
    template_activity_type,
    template_percent_complete_type,
    template_default_duration_minutes,
    auth.uid(),
    auth.uid()
  )
  returning * into created_template;

  return to_jsonb(created_template);
end;
$$;

create or replace function public.create_activity_recurrence_rule(
  target_farm_id uuid,
  target_project_id uuid,
  target_template_id uuid,
  target_wbs_id uuid,
  rule_code text,
  rule_name text,
  recurrence_frequency text,
  recurrence_starts_on date,
  recurrence_occurrence_time time,
  target_calendar_id uuid default null,
  target_cycle_id uuid default null,
  rule_status text default 'DRAFT',
  recurrence_interval_count integer default 1,
  recurrence_day_of_month smallint default null,
  recurrence_ends_on date default null,
  recurrence_timezone text default null,
  recurrence_weekdays smallint[] default array[]::smallint[],
  generation_horizon_days integer default 30
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  current_project public.schedule_projects;
  selected_calendar_id uuid;
  selected_cycle_id uuid;
  selected_timezone text;
  created_rule public.activity_recurrence_rules;
  created_weekdays jsonb;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to create a recurrence rule';
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
    from public.activity_templates
    where farm_id = target_farm_id
      and id = target_template_id
      and is_active
  ) then
    raise exception 'Active activity template was not found for this farm';
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

  selected_calendar_id := coalesce(target_calendar_id, current_project.default_calendar_id);
  if selected_calendar_id is null or not exists (
    select 1
    from public.schedule_calendars
    where farm_id = target_farm_id
      and project_id = target_project_id
      and id = selected_calendar_id
  ) then
    raise exception 'Calendar was not found for this project';
  end if;

  selected_cycle_id := coalesce(target_cycle_id, current_project.cultivation_cycle_id);
  if selected_cycle_id is not null and not exists (
    select 1
    from public.cultivation_cycles
    where farm_id = target_farm_id
      and id = selected_cycle_id
  ) then
    raise exception 'Cultivation cycle was not found for this farm';
  end if;

  if nullif(trim(rule_code), '') is null or nullif(trim(rule_name), '') is null then
    raise exception 'Recurrence rule code and name are required';
  end if;

  if recurrence_frequency = 'WEEKLY'
     and cardinality(coalesce(recurrence_weekdays, array[]::smallint[])) = 0 then
    raise exception 'A weekly recurrence rule requires at least one weekday';
  end if;

  if recurrence_frequency <> 'WEEKLY'
     and cardinality(coalesce(recurrence_weekdays, array[]::smallint[])) > 0 then
    raise exception 'Weekdays are only accepted for weekly recurrence rules';
  end if;

  if recurrence_frequency = 'MONTHLY' and recurrence_day_of_month is null then
    raise exception 'A monthly recurrence rule requires a day of month';
  end if;

  if recurrence_frequency <> 'MONTHLY' and recurrence_day_of_month is not null then
    raise exception 'Day of month is only accepted for monthly recurrence rules';
  end if;

  selected_timezone := coalesce(nullif(trim(recurrence_timezone), ''), current_project.timezone);
  if not exists (
    select 1
    from pg_catalog.pg_timezone_names
    where name = selected_timezone
  ) then
    raise exception 'A valid IANA recurrence timezone is required';
  end if;

  insert into public.activity_recurrence_rules (
    farm_id,
    project_id,
    template_id,
    wbs_id,
    calendar_id,
    cultivation_cycle_id,
    rule_code,
    name,
    status,
    frequency,
    interval_count,
    day_of_month,
    starts_on,
    ends_on,
    occurrence_time,
    timezone,
    generation_horizon_days,
    created_by,
    updated_by
  )
  values (
    target_farm_id,
    target_project_id,
    target_template_id,
    target_wbs_id,
    selected_calendar_id,
    selected_cycle_id,
    trim(rule_code),
    trim(rule_name),
    rule_status,
    recurrence_frequency,
    recurrence_interval_count,
    recurrence_day_of_month,
    recurrence_starts_on,
    recurrence_ends_on,
    recurrence_occurrence_time,
    selected_timezone,
    generation_horizon_days,
    auth.uid(),
    auth.uid()
  )
  returning * into created_rule;

  insert into public.activity_recurrence_weekdays (
    farm_id,
    project_id,
    recurrence_rule_id,
    weekday
  )
  select
    target_farm_id,
    target_project_id,
    created_rule.id,
    requested.weekday
  from (
    select distinct unnest(coalesce(recurrence_weekdays, array[]::smallint[])) as weekday
  ) as requested;

  select coalesce(
    jsonb_agg(weekday order by weekday),
    '[]'::jsonb
  )
  into created_weekdays
  from public.activity_recurrence_weekdays
  where recurrence_rule_id = created_rule.id;

  return to_jsonb(created_rule) || jsonb_build_object('weekdays', created_weekdays);
end;
$$;

create or replace function public.create_activity_trigger_rule(
  target_farm_id uuid,
  target_project_id uuid,
  target_template_id uuid,
  target_wbs_id uuid,
  rule_code text,
  rule_name text,
  trigger_event_type text,
  target_calendar_id uuid default null,
  target_cycle_id uuid default null,
  rule_status text default 'DRAFT',
  predicate_match_mode text default 'ALL',
  cooldown_minutes integer default 0,
  valid_from timestamptz default null,
  valid_until timestamptz default null,
  predicate_field_codes text[] default array[]::text[],
  predicate_operators text[] default array[]::text[],
  predicate_numeric_values numeric[] default array[]::numeric[],
  predicate_text_values text[] default array[]::text[],
  predicate_boolean_values boolean[] default array[]::boolean[],
  predicate_unit_codes text[] default array[]::text[],
  predicate_window_minutes integer[] default array[]::integer[],
  target_work_area_ids uuid[] default array[]::uuid[]
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
  predicate_count integer;
  predicate_index integer;
  created_rule public.activity_trigger_rules;
  created_predicates jsonb;
  linked_work_areas jsonb;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to create a trigger rule';
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
    from public.activity_templates
    where farm_id = target_farm_id
      and id = target_template_id
      and is_active
  ) then
    raise exception 'Active activity template was not found for this farm';
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

  selected_calendar_id := coalesce(target_calendar_id, current_project.default_calendar_id);
  if selected_calendar_id is null or not exists (
    select 1
    from public.schedule_calendars
    where farm_id = target_farm_id
      and project_id = target_project_id
      and id = selected_calendar_id
  ) then
    raise exception 'Calendar was not found for this project';
  end if;

  selected_cycle_id := coalesce(target_cycle_id, current_project.cultivation_cycle_id);
  if selected_cycle_id is not null and not exists (
    select 1
    from public.cultivation_cycles
    where farm_id = target_farm_id
      and id = selected_cycle_id
  ) then
    raise exception 'Cultivation cycle was not found for this farm';
  end if;

  if nullif(trim(rule_code), '') is null or nullif(trim(rule_name), '') is null then
    raise exception 'Trigger rule code and name are required';
  end if;

  predicate_count := cardinality(coalesce(predicate_field_codes, array[]::text[]));
  if cardinality(coalesce(predicate_operators, array[]::text[])) <> predicate_count
     or cardinality(coalesce(predicate_numeric_values, array[]::numeric[])) <> predicate_count
     or cardinality(coalesce(predicate_text_values, array[]::text[])) <> predicate_count
     or cardinality(coalesce(predicate_boolean_values, array[]::boolean[])) <> predicate_count
     or cardinality(coalesce(predicate_unit_codes, array[]::text[])) <> predicate_count
     or cardinality(coalesce(predicate_window_minutes, array[]::integer[])) <> predicate_count then
    raise exception 'All trigger predicate arrays must have the same length';
  end if;

  if rule_status = 'ACTIVE' and trigger_event_type <> 'MANUAL' and predicate_count = 0 then
    raise exception 'An active non-manual trigger rule requires a predicate';
  end if;

  if predicate_count > 0 then
    for predicate_index in
      select generate_subscripts(predicate_field_codes, 1)
    loop
      if num_nonnulls(
        predicate_numeric_values[predicate_index],
        predicate_text_values[predicate_index],
        predicate_boolean_values[predicate_index]
      ) <> 1 then
        raise exception 'Each trigger predicate requires exactly one typed comparison value';
      end if;
    end loop;
  end if;

  if exists (
    select 1
    from unnest(coalesce(target_work_area_ids, array[]::uuid[])) as requested(id)
    left join public.farm_work_areas as area
      on area.farm_id = target_farm_id
     and area.id = requested.id
     and area.is_active
    where area.id is null
  ) then
    raise exception 'An active work area was not found for this farm';
  end if;

  insert into public.activity_trigger_rules (
    farm_id,
    project_id,
    template_id,
    wbs_id,
    calendar_id,
    cultivation_cycle_id,
    rule_code,
    name,
    status,
    event_type,
    predicate_match_mode,
    cooldown_minutes,
    valid_from,
    valid_until,
    created_by,
    updated_by
  )
  values (
    target_farm_id,
    target_project_id,
    target_template_id,
    target_wbs_id,
    selected_calendar_id,
    selected_cycle_id,
    trim(rule_code),
    trim(rule_name),
    rule_status,
    trigger_event_type,
    predicate_match_mode,
    cooldown_minutes,
    valid_from,
    valid_until,
    auth.uid(),
    auth.uid()
  )
  returning * into created_rule;

  insert into public.activity_trigger_predicates (
    farm_id,
    project_id,
    trigger_rule_id,
    sequence_no,
    source_field_code,
    comparison_operator,
    numeric_value,
    text_value,
    boolean_value,
    unit_code,
    observation_window_minutes
  )
  select
    target_farm_id,
    target_project_id,
    created_rule.id,
    subscripts.predicate_index,
    trim(predicate_field_codes[subscripts.predicate_index]),
    predicate_operators[subscripts.predicate_index],
    predicate_numeric_values[subscripts.predicate_index],
    nullif(trim(predicate_text_values[subscripts.predicate_index]), ''),
    predicate_boolean_values[subscripts.predicate_index],
    nullif(trim(predicate_unit_codes[subscripts.predicate_index]), ''),
    predicate_window_minutes[subscripts.predicate_index]
  from generate_subscripts(predicate_field_codes, 1) as subscripts(predicate_index);

  with requested as (
    select area_id, min(ordinality) as ordinality
    from unnest(coalesce(target_work_area_ids, array[]::uuid[]))
      with ordinality as areas(area_id, ordinality)
    group by area_id
  )
  insert into public.activity_trigger_rule_work_areas (
    farm_id,
    project_id,
    trigger_rule_id,
    work_area_id,
    is_primary
  )
  select
    target_farm_id,
    target_project_id,
    created_rule.id,
    area_id,
    row_number() over (order by ordinality) = 1
  from requested;

  select coalesce(
    jsonb_agg(to_jsonb(predicate_row) order by predicate_row.sequence_no),
    '[]'::jsonb
  )
  into created_predicates
  from public.activity_trigger_predicates as predicate_row
  where predicate_row.trigger_rule_id = created_rule.id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'work_area_id', link.work_area_id,
        'is_primary', link.is_primary
      )
      order by link.is_primary desc, link.created_at
    ),
    '[]'::jsonb
  )
  into linked_work_areas
  from public.activity_trigger_rule_work_areas as link
  where link.trigger_rule_id = created_rule.id;

  return to_jsonb(created_rule) || jsonb_build_object(
    'predicates', created_predicates,
    'work_areas', linked_work_areas
  );
end;
$$;

revoke execute on function public.validate_recurrence_weekday_frequency() from public, anon, authenticated;
revoke execute on function public.validate_recurrence_frequency_change() from public, anon, authenticated;
revoke execute on function public.validate_active_recurrence_rule() from public, anon, authenticated;
revoke execute on function public.validate_active_trigger_rule() from public, anon, authenticated;

revoke execute on function public.create_activity_template(
  uuid, text, text, text, text, text, integer, text
) from public, anon;
revoke execute on function public.create_activity_recurrence_rule(
  uuid, uuid, uuid, uuid, text, text, text, date, time,
  uuid, uuid, text, integer, smallint, date, text, smallint[], integer
) from public, anon;
revoke execute on function public.create_activity_trigger_rule(
  uuid, uuid, uuid, uuid, text, text, text, uuid, uuid, text, text,
  integer, timestamptz, timestamptz, text[], text[], numeric[], text[],
  boolean[], text[], integer[], uuid[]
) from public, anon;

grant execute on function public.create_activity_template(
  uuid, text, text, text, text, text, integer, text
) to authenticated;
grant execute on function public.create_activity_recurrence_rule(
  uuid, uuid, uuid, uuid, text, text, text, date, time,
  uuid, uuid, text, integer, smallint, date, text, smallint[], integer
) to authenticated;
grant execute on function public.create_activity_trigger_rule(
  uuid, uuid, uuid, uuid, text, text, text, uuid, uuid, text, text,
  integer, timestamptz, timestamptz, text[], text[], numeric[], text[],
  boolean[], text[], integer[], uuid[]
) to authenticated;
