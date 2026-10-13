-- Phase 0: establish farm context and integrity before introducing P6 activities.

create table public.agri_operation_types (
  code text primary key,
  name_ko text not null,
  description text,
  sort_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint agri_operation_types_code_format_check
    check (code ~ '^[a-z][a-z0-9_]*$')
);

insert into public.agri_operation_types (code, name_ko, description, sort_order)
values
  ('irrigation_fertigation', '관수/시비', '관수, 양액 공급, 시비 및 배액 관리', 10),
  ('environment_control', '환경관리', '온도, 습도, 광, 이산화탄소 및 환기 관리', 20),
  ('pest_disease_control', '병해충방제', '예찰, 진단, 방제 및 위생 관리', 30),
  ('harvest_postharvest', '수확/정리', '수확, 선별, 포장 및 수확 후 정리', 40),
  ('follow_up', '후속작업', '이슈 또는 선행 작업에서 파생된 후속 조치', 50),
  ('other', '기타', '표준 분류에 포함되지 않은 농작업', 90);

create table public.farm_work_areas (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  parent_area_id uuid,
  code text not null,
  name text not null,
  area_type text not null,
  area_m2 numeric(14, 2),
  properties jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint farm_work_areas_farm_code_key unique (farm_id, code),
  constraint farm_work_areas_farm_id_id_key unique (farm_id, id),
  constraint farm_work_areas_code_format_check
    check (code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'),
  constraint farm_work_areas_area_type_check
    check (area_type in (
      'farm', 'field', 'block', 'greenhouse', 'house', 'bay', 'bed', 'zone', 'facility'
    )),
  constraint farm_work_areas_area_m2_check check (area_m2 is null or area_m2 >= 0),
  constraint farm_work_areas_properties_object_check
    check (jsonb_typeof(properties) = 'object'),
  constraint farm_work_areas_parent_same_farm_fkey
    foreign key (farm_id, parent_area_id)
    references public.farm_work_areas(farm_id, id)
    on delete set null (parent_area_id)
);

alter table public.cultivation_cycles
  add constraint cultivation_cycles_farm_id_id_key unique (farm_id, id);

alter table public.tasks
  add constraint tasks_farm_id_id_key unique (farm_id, id);

create table public.cultivation_cycle_areas (
  farm_id uuid not null references public.farms(id) on delete cascade,
  cultivation_cycle_id uuid not null,
  work_area_id uuid not null,
  valid_from date,
  valid_to date,
  created_at timestamptz not null default now(),
  primary key (cultivation_cycle_id, work_area_id),
  constraint cultivation_cycle_areas_cycle_same_farm_fkey
    foreign key (farm_id, cultivation_cycle_id)
    references public.cultivation_cycles(farm_id, id)
    on delete cascade,
  constraint cultivation_cycle_areas_area_same_farm_fkey
    foreign key (farm_id, work_area_id)
    references public.farm_work_areas(farm_id, id)
    on delete cascade,
  constraint cultivation_cycle_areas_valid_range_check
    check (valid_to is null or valid_from is null or valid_to >= valid_from)
);

alter table public.tasks
  add column cultivation_cycle_id uuid,
  add column operation_type_code text;

update public.tasks
set operation_type_code = case category
  when '관수/시비' then 'irrigation_fertigation'
  when '환경관리' then 'environment_control'
  when '병해충방제' then 'pest_disease_control'
  when '수확/정리' then 'harvest_postharvest'
  when '후속작업' then 'follow_up'
  else 'other'
end;

with single_cycle_farms as (
  select farm_id, min(id::text)::uuid as cultivation_cycle_id
  from public.cultivation_cycles
  group by farm_id
  having count(*) = 1
)
update public.tasks as task
set cultivation_cycle_id = single_cycle_farms.cultivation_cycle_id
from single_cycle_farms
where task.farm_id = single_cycle_farms.farm_id
  and task.cultivation_cycle_id is null;

alter table public.tasks
  alter column operation_type_code set not null,
  add constraint tasks_operation_type_code_fkey
    foreign key (operation_type_code)
    references public.agri_operation_types(code),
  add constraint tasks_cultivation_cycle_same_farm_fkey
    foreign key (farm_id, cultivation_cycle_id)
    references public.cultivation_cycles(farm_id, id)
    on delete set null (cultivation_cycle_id);

alter table public.tasks
  drop constraint tasks_parent_task_id_fkey,
  add constraint tasks_parent_task_same_farm_fkey
    foreign key (farm_id, parent_task_id)
    references public.tasks(farm_id, id)
    on delete set null (parent_task_id);

create or replace function public.set_task_operation_type()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.operation_type_code is null then
    new.operation_type_code := case new.category
      when '관수/시비' then 'irrigation_fertigation'
      when '환경관리' then 'environment_control'
      when '병해충방제' then 'pest_disease_control'
      when '수확/정리' then 'harvest_postharvest'
      when '후속작업' then 'follow_up'
      else 'other'
    end;
  end if;

  return new;
end;
$$;

create trigger set_tasks_operation_type
before insert or update of category, operation_type_code on public.tasks
for each row execute function public.set_task_operation_type();

create table public.task_work_areas (
  farm_id uuid not null references public.farms(id) on delete cascade,
  task_id uuid not null,
  work_area_id uuid not null,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (task_id, work_area_id),
  constraint task_work_areas_task_same_farm_fkey
    foreign key (farm_id, task_id)
    references public.tasks(farm_id, id)
    on delete cascade,
  constraint task_work_areas_area_same_farm_fkey
    foreign key (farm_id, work_area_id)
    references public.farm_work_areas(farm_id, id)
    on delete cascade
);

create unique index task_work_areas_one_primary_idx
on public.task_work_areas(task_id)
where is_primary;

alter table public.task_logs
  add column actor_id uuid references auth.users(id) on delete set null;

alter table public.task_logs
  drop constraint task_logs_task_id_fkey,
  add constraint task_logs_task_same_farm_fkey
    foreign key (farm_id, task_id)
    references public.tasks(farm_id, id)
    on delete cascade;

create index farm_work_areas_farm_parent_idx
on public.farm_work_areas(farm_id, parent_area_id);

create index cultivation_cycle_areas_farm_area_idx
on public.cultivation_cycle_areas(farm_id, work_area_id);

create index tasks_farm_cycle_date_idx
on public.tasks(farm_id, cultivation_cycle_id, scheduled_date);

create index tasks_operation_type_code_idx
on public.tasks(operation_type_code);

create index task_logs_actor_created_idx
on public.task_logs(actor_id, created_at desc);

create trigger set_agri_operation_types_updated_at
before update on public.agri_operation_types
for each row execute function public.set_updated_at();

create trigger set_farm_work_areas_updated_at
before update on public.farm_work_areas
for each row execute function public.set_updated_at();

alter table public.agri_operation_types enable row level security;
alter table public.farm_work_areas enable row level security;
alter table public.cultivation_cycle_areas enable row level security;
alter table public.task_work_areas enable row level security;

create policy operation_types_are_readable
on public.agri_operation_types
for select
to anon, authenticated
using (true);

create policy members_can_read_farm_work_areas
on public.farm_work_areas
for select
to authenticated
using (public.is_farm_member(farm_id));

create policy farm_managers_manage_work_areas
on public.farm_work_areas
for all
to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_can_read_cultivation_cycle_areas
on public.cultivation_cycle_areas
for select
to authenticated
using (public.is_farm_member(farm_id));

create policy farm_managers_manage_cultivation_cycle_areas
on public.cultivation_cycle_areas
for all
to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_can_read_task_work_areas
on public.task_work_areas
for select
to authenticated
using (public.is_farm_member(farm_id));

create policy farm_managers_manage_task_work_areas
on public.task_work_areas
for all
to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

do $$
begin
  execute 'drop policy if exists '
    || quote_ident('members can write task logs')
    || ' on public.task_logs';
end;
$$;

grant select on public.agri_operation_types to anon, authenticated;
grant select, insert, update, delete on public.farm_work_areas to authenticated;
grant select, insert, update, delete on public.cultivation_cycle_areas to authenticated;
grant select, insert, update, delete on public.task_work_areas to authenticated;
revoke insert, update, delete on public.agri_operation_types from anon, authenticated;
revoke insert, update, delete on public.task_logs from anon;
revoke insert on public.task_logs from authenticated;
revoke truncate, trigger, references on table
  public.countries,
  public.farms,
  public.weather_observations,
  public.farm_memberships,
  public.cultivation_cycles,
  public.tasks,
  public.task_logs,
  public.ai_consultations,
  public.chat_logs,
  public.agri_operation_types,
  public.farm_work_areas,
  public.cultivation_cycle_areas,
  public.task_work_areas
from anon, authenticated;

create or replace function public.create_farm_task(
  target_farm_id uuid,
  task_title text,
  task_scheduled_date date,
  task_category text,
  task_description text default null,
  task_priority text default 'medium',
  task_parent_task_id uuid default null,
  target_cycle_id uuid default null,
  target_operation_type_code text default null,
  target_work_area_ids uuid[] default array[]::uuid[],
  task_is_followup boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  created_task public.tasks;
  selected_cycle_id uuid;
  selected_operation_type_code text;
  linked_work_area_ids uuid[];
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to create a task';
  end if;

  if nullif(trim(task_title), '') is null or task_scheduled_date is null then
    raise exception 'Task title and scheduled date are required';
  end if;

  if task_parent_task_id is not null and not exists (
    select 1
    from public.tasks
    where farm_id = target_farm_id
      and id = task_parent_task_id
  ) then
    raise exception 'Parent task was not found for this farm';
  end if;

  selected_cycle_id := target_cycle_id;

  if selected_cycle_id is null then
    select min(id::text)::uuid
    into selected_cycle_id
    from public.cultivation_cycles
    where farm_id = target_farm_id
      and status = 'active'
    having count(*) = 1;
  end if;

  if selected_cycle_id is not null and not exists (
    select 1
    from public.cultivation_cycles
    where farm_id = target_farm_id
      and id = selected_cycle_id
  ) then
    raise exception 'Cultivation cycle was not found for this farm';
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

  selected_operation_type_code := coalesce(
    nullif(trim(target_operation_type_code), ''),
    case task_category
      when '관수/시비' then 'irrigation_fertigation'
      when '환경관리' then 'environment_control'
      when '병해충방제' then 'pest_disease_control'
      when '수확/정리' then 'harvest_postharvest'
      when '후속작업' then 'follow_up'
      else 'other'
    end
  );

  if not exists (
    select 1
    from public.agri_operation_types
    where code = selected_operation_type_code
      and is_active
  ) then
    raise exception 'Active agricultural operation type is required';
  end if;

  insert into public.tasks (
    farm_id,
    cultivation_cycle_id,
    operation_type_code,
    title,
    description,
    scheduled_date,
    category,
    priority,
    is_followup,
    parent_task_id
  )
  values (
    target_farm_id,
    selected_cycle_id,
    selected_operation_type_code,
    trim(task_title),
    nullif(trim(task_description), ''),
    task_scheduled_date,
    task_category,
    task_priority,
    task_is_followup,
    task_parent_task_id
  )
  returning * into created_task;

  insert into public.task_work_areas (farm_id, task_id, work_area_id, is_primary)
  select
    target_farm_id,
    created_task.id,
    requested.id,
    row_number() over (order by requested.id) = 1
  from (
    select distinct id
    from unnest(coalesce(target_work_area_ids, array[]::uuid[])) as ids(id)
  ) as requested;

  select coalesce(array_agg(work_area_id order by work_area_id), array[]::uuid[])
  into linked_work_area_ids
  from public.task_work_areas
  where task_id = created_task.id;

  return to_jsonb(created_task)
    || jsonb_build_object('work_area_ids', linked_work_area_ids);
end;
$$;

grant execute on function public.create_farm_task(
  uuid, text, date, text, text, text, uuid, uuid, text, uuid[], boolean
) to authenticated;

revoke execute on function public.create_farm_task(
  uuid, text, date, text, text, text, uuid, uuid, text, uuid[], boolean
) from public;

create or replace function public.record_task_action(
  target_farm_id uuid,
  target_task_id uuid,
  action_name text,
  action_note text,
  action_photo_url text default null,
  action_issue_category text default null,
  create_followup boolean default false,
  followup_title text default null,
  followup_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_task public.tasks;
  updated_task public.tasks;
  created_log public.task_logs;
  created_followup public.tasks;
  log_note text := coalesce(action_note, '');
  task_work_area_ids uuid[] := array[]::uuid[];
  followup_work_area_ids uuid[] := array[]::uuid[];
begin
  if action_name not in ('completed', 'skipped', 'issue') then
    raise exception 'Invalid task action';
  end if;

  select *
  into current_task
  from public.tasks
  where id = target_task_id
    and farm_id = target_farm_id
  for update;

  if not found then
    raise exception 'Task was not found for this farm';
  end if;

  if not public.has_farm_role(target_farm_id, array['owner', 'manager', 'worker']) then
    raise exception 'Farm action permission is required';
  end if;

  if create_followup and not public.has_farm_role(
    target_farm_id,
    array['owner', 'manager']
  ) then
    raise exception 'Manager permission is required to create a follow-up task';
  end if;

  if action_issue_category is not null
     and char_length(trim(action_issue_category)) > 0 then
    log_note := concat_ws(
      E'\n',
      log_note,
      'Issue category: ' || trim(action_issue_category)
    );
  end if;

  update public.tasks
  set status = action_name,
      updated_at = now()
  where id = target_task_id
    and farm_id = target_farm_id
  returning * into updated_task;

  insert into public.task_logs (
    task_id,
    farm_id,
    actor_id,
    action,
    note,
    photo_url,
    issue_category
  )
  values (
    target_task_id,
    target_farm_id,
    auth.uid(),
    action_name,
    nullif(log_note, ''),
    nullif(trim(action_photo_url), ''),
    case
      when action_name = 'issue'
        then nullif(trim(action_issue_category), '')
      else null
    end
  )
  returning * into created_log;

  select coalesce(array_agg(work_area_id order by work_area_id), array[]::uuid[])
  into task_work_area_ids
  from public.task_work_areas
  where farm_id = target_farm_id
    and task_id = target_task_id;

  if create_followup then
    if nullif(trim(followup_title), '') is null or followup_date is null then
      raise exception 'Follow-up title and date are required';
    end if;

    insert into public.tasks (
      farm_id,
      cultivation_cycle_id,
      operation_type_code,
      title,
      description,
      scheduled_date,
      category,
      priority,
      is_followup,
      parent_task_id
    )
    values (
      target_farm_id,
      current_task.cultivation_cycle_id,
      'follow_up',
      trim(followup_title),
      nullif(log_note, ''),
      followup_date,
      '후속작업',
      'high',
      true,
      target_task_id
    )
    returning * into created_followup;

    insert into public.task_work_areas (
      farm_id,
      task_id,
      work_area_id,
      is_primary
    )
    select
      target_farm_id,
      created_followup.id,
      work_area_id,
      is_primary
    from public.task_work_areas
    where farm_id = target_farm_id
      and task_id = target_task_id;

    select coalesce(array_agg(work_area_id order by work_area_id), array[]::uuid[])
    into followup_work_area_ids
    from public.task_work_areas
    where farm_id = target_farm_id
      and task_id = created_followup.id;
  end if;

  return jsonb_build_object(
    'task',
    to_jsonb(updated_task)
      || jsonb_build_object('work_area_ids', task_work_area_ids),
    'log', to_jsonb(created_log),
    'followup',
    case
      when created_followup.id is null then null
      else to_jsonb(created_followup)
        || jsonb_build_object('work_area_ids', followup_work_area_ids)
    end
  );
end;
$$;

grant execute on function public.record_task_action(
  uuid, uuid, text, text, text, text, boolean, text, date
) to authenticated;

revoke execute on function public.record_task_action(
  uuid, uuid, text, text, text, text, boolean, text, date
) from public;
