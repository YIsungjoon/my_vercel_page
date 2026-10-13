-- Forward migration for farm membership, cultivation cycles, and RLS.
-- This migration assumes the location-based farms table already exists.

alter table public.countries
  add column if not exists code char(2);

update public.countries
set code = case name
  when 'Canada' then 'CA'
  when 'United States' then 'US'
  when 'Mexico' then 'MX'
  else code
end
where code is null;

insert into public.countries (code, name)
select 'KR', 'South Korea'
where not exists (
  select 1 from public.countries where code = 'KR'
);

alter table public.countries
  alter column code set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'countries_code_key'
      and conrelid = 'public.countries'::regclass
  ) then
    alter table public.countries
      add constraint countries_code_key unique (code);
  end if;
end
$$;

alter table public.farms
  add column if not exists created_by uuid references auth.users(id) on delete set null;

alter table public.farms
  add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'farms_country_code_fkey'
      and conrelid = 'public.farms'::regclass
  ) then
    alter table public.farms
      add constraint farms_country_code_fkey
      foreign key (country_code) references public.countries(code);
  end if;
end
$$;

create table if not exists public.farm_memberships (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('owner', 'manager', 'worker', 'viewer')),
  created_at timestamptz not null default now(),
  unique (farm_id, user_id)
);

create index if not exists farm_memberships_user_idx
  on public.farm_memberships (user_id, farm_id);

create table if not exists public.cultivation_cycles (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  crop text not null,
  variety text not null,
  planted_at date not null,
  expected_harvest_at date,
  growth_stage text not null,
  status text not null default 'active'
    check (status in ('planned', 'active', 'completed', 'archived')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (farm_id, crop, variety, planted_at)
);

create index if not exists cultivation_cycles_farm_status_idx
  on public.cultivation_cycles (farm_id, status);

create or replace function public.is_farm_member(target_farm_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.farm_memberships
    where farm_id = target_farm_id
      and user_id = auth.uid()
  );
$$;

create or replace function public.has_farm_role(
  target_farm_id uuid,
  allowed_roles text[]
)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1
    from public.farm_memberships
    where farm_id = target_farm_id
      and user_id = auth.uid()
      and role = any(allowed_roles)
  );
$$;

create or replace function public.create_farm_with_owner(
  farm_slug text,
  farm_name text,
  farm_region text,
  farm_country_code text,
  farm_latitude numeric,
  farm_longitude numeric,
  farm_timezone text default 'Asia/Seoul'
)
returns public.farms
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  created_farm public.farms;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required';
  end if;

  insert into public.farms (
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
    farm_slug,
    farm_name,
    farm_region,
    farm_country_code,
    farm_latitude,
    farm_longitude,
    farm_timezone,
    auth.uid()
  )
  returning * into created_farm;

  insert into public.farm_memberships (farm_id, user_id, role)
  values (created_farm.id, auth.uid(), 'owner');

  return created_farm;
end;
$$;

create or replace function public.create_farm_with_cycle(
  farm_slug text,
  farm_name text,
  farm_region text,
  farm_country_code text,
  farm_latitude numeric,
  farm_longitude numeric,
  farm_timezone text,
  cycle_crop text,
  cycle_variety text,
  cycle_planted_at date,
  cycle_growth_stage text,
  cycle_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  created_farm public.farms;
  created_cycle public.cultivation_cycles;
begin
  created_farm := public.create_farm_with_owner(
    farm_slug,
    farm_name,
    farm_region,
    farm_country_code,
    farm_latitude,
    farm_longitude,
    farm_timezone
  );

  insert into public.cultivation_cycles (
    farm_id,
    crop,
    variety,
    planted_at,
    growth_stage,
    notes
  )
  values (
    created_farm.id,
    cycle_crop,
    cycle_variety,
    cycle_planted_at,
    cycle_growth_stage,
    cycle_notes
  )
  returning * into created_cycle;

  return jsonb_build_object(
    'farm', to_jsonb(created_farm),
    'cycle', to_jsonb(created_cycle)
  );
end;
$$;
create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists farms_set_updated_at on public.farms;
create trigger farms_set_updated_at
before update on public.farms
for each row execute function public.set_updated_at();

drop trigger if exists cultivation_cycles_set_updated_at on public.cultivation_cycles;
create trigger cultivation_cycles_set_updated_at
before update on public.cultivation_cycles
for each row execute function public.set_updated_at();

alter table public.farms enable row level security;
alter table public.farm_memberships enable row level security;
alter table public.cultivation_cycles enable row level security;

drop policy if exists "public can read virtual farms" on public.farms;
drop policy if exists "Allow public read for farms" on public.farms;
drop policy if exists "Allow public insert/update for farms" on public.farms;

create policy "anonymous can read virtual farms"
on public.farms
for select to anon, authenticated using (is_virtual = true);

create policy "members can read farms"
on public.farms
for select
to authenticated
using (public.is_farm_member(id));

create policy "farm managers can update farms"
on public.farms
for update
to authenticated
using (public.has_farm_role(id, array['owner', 'manager']))
with check (public.has_farm_role(id, array['owner', 'manager']));

create policy "farm owners can delete farms"
on public.farms
for delete
to authenticated
using (public.has_farm_role(id, array['owner']));

drop policy if exists "public can read virtual farm weather" on public.weather_observations;
drop policy if exists "Allow public select for weather_observations" on public.weather_observations;
drop policy if exists "Allow public insert for weather_observations" on public.weather_observations;

create policy "anonymous can read virtual farm weather"
on public.weather_observations
for select to anon, authenticated using ( exists (
    select 1
    from public.farms
    where farms.id = weather_observations.farm_id
      and farms.is_virtual = true
  )
);

create policy "members can read farm weather"
on public.weather_observations
for select
to authenticated
using (public.is_farm_member(farm_id));

drop policy if exists "Allow public read for farm_memberships" on public.farm_memberships;
drop policy if exists "Allow public all for farm_memberships" on public.farm_memberships;

create policy "users can read their memberships"
on public.farm_memberships
for select
to authenticated
using (
  user_id = auth.uid()
  or public.has_farm_role(farm_id, array['owner', 'manager'])
);

create policy "owners manage memberships"
on public.farm_memberships
for all
to authenticated
using (public.has_farm_role(farm_id, array['owner']))
with check (public.has_farm_role(farm_id, array['owner']));

drop policy if exists "Allow public read for cultivation_cycles" on public.cultivation_cycles;
drop policy if exists "Allow public all for cultivation_cycles" on public.cultivation_cycles;

create policy "members can read cultivation cycles"
on public.cultivation_cycles
for select
to authenticated
using (public.is_farm_member(farm_id));

create policy "farm managers manage cultivation cycles"
on public.cultivation_cycles
for all
to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

alter table public.tasks enable row level security;
alter table public.task_logs enable row level security;
alter table public.ai_consultations enable row level security;
alter table public.chat_logs enable row level security;

drop policy if exists "Allow public read for tasks" on public.tasks;
drop policy if exists "Allow public all for tasks" on public.tasks;
create policy "members can read tasks"
on public.tasks
for select
to authenticated
using (public.is_farm_member(farm_id));
create policy "farm managers manage tasks"
on public.tasks
for all
to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']))
with check (public.has_farm_role(farm_id, array['owner', 'manager']));

drop policy if exists "Allow public read for task_logs" on public.task_logs;
drop policy if exists "Allow public all for task_logs" on public.task_logs;
create policy "members can read task logs"
on public.task_logs
for select
to authenticated
using (public.is_farm_member(farm_id));
create policy "members can write task logs"
on public.task_logs
for insert
to authenticated
with check (public.has_farm_role(farm_id, array['owner', 'manager', 'worker']));

drop policy if exists "Allow public read for ai_consultations" on public.ai_consultations;
drop policy if exists "Allow public all for ai_consultations" on public.ai_consultations;
create policy "members can read ai consultations"
on public.ai_consultations
for select
to authenticated
using (public.is_farm_member(farm_id));
create policy "members can write ai consultations"
on public.ai_consultations
for insert
to authenticated
with check (public.is_farm_member(farm_id));

drop policy if exists "Allow public select for chat_logs" on public.chat_logs;
drop policy if exists "Allow public insert for chat_logs" on public.chat_logs;
drop policy if exists "Allow public update for chat_logs" on public.chat_logs;
create policy "members can read chat logs"
on public.chat_logs
for select
to authenticated
using (farm_id is not null and public.is_farm_member(farm_id));
create policy "members can write chat logs"
on public.chat_logs
for insert
to authenticated
with check (farm_id is not null and public.is_farm_member(farm_id));

grant select on public.farms to anon, authenticated;
grant update, delete on public.farms to authenticated;
grant select on public.weather_observations to anon, authenticated;
grant select, insert, update, delete on public.farm_memberships to authenticated;
grant select, insert, update, delete on public.cultivation_cycles to authenticated;
grant select, insert, update, delete on public.tasks to authenticated;
grant select, insert on public.task_logs to authenticated;
grant select, insert on public.ai_consultations to authenticated;
grant select, insert on public.chat_logs to authenticated;
grant execute on function public.is_farm_member(uuid) to anon, authenticated;
grant execute on function public.has_farm_role(uuid, text[]) to anon, authenticated;
grant execute on function public.create_farm_with_owner(text, text, text, text, numeric, numeric, text) to authenticated;
grant execute on function public.create_farm_with_cycle(text, text, text, text, numeric, numeric, text, text, text, date, text, text) to authenticated;
grant execute on function public.set_updated_at() to authenticated;
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

  if create_followup and not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to create a follow-up task';
  end if;

  if action_issue_category is not null and char_length(trim(action_issue_category)) > 0 then
    log_note := concat_ws(E'\n', log_note, 'Issue category: ' || trim(action_issue_category));
  end if;

  update public.tasks
  set status = action_name,
      updated_at = now()
  where id = target_task_id
  returning * into updated_task;

  insert into public.task_logs (
    task_id,
    farm_id,
    action,
    note,
    photo_url,
    issue_category
  )
  values (
    target_task_id,
    target_farm_id,
    action_name,
    nullif(log_note, ''),
    nullif(trim(action_photo_url), ''),
    case when action_name = 'issue' then nullif(trim(action_issue_category), '') else null end
  )
  returning * into created_log;

  if create_followup then
    if nullif(trim(followup_title), '') is null or followup_date is null then
      raise exception 'Follow-up title and date are required';
    end if;

    insert into public.tasks (
      farm_id,
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
      trim(followup_title),
      nullif(log_note, ''),
      followup_date,
      current_task.category,
      'high',
      true,
      target_task_id
    )
    returning * into created_followup;
  end if;

  return jsonb_build_object(
    'task', to_jsonb(updated_task),
    'log', to_jsonb(created_log),
    'followup', to_jsonb(created_followup)
  );
end;
$$;

grant execute on function public.record_task_action(uuid, uuid, text, text, text, text, boolean, text, date)
to authenticated;
revoke execute on function public.create_farm_with_owner(text, text, text, text, numeric, numeric, text) from public;
revoke execute on function public.create_farm_with_cycle(text, text, text, text, numeric, numeric, text, text, text, date, text, text) from public;
revoke execute on function public.record_task_action(uuid, uuid, text, text, text, text, boolean, text, date) from public;
revoke execute on function public.set_updated_at() from public;
create policy "anonymous can read virtual cultivation cycles"
on public.cultivation_cycles
for select
to anon
using (
  exists (
    select 1
    from public.farms
    where farms.id = cultivation_cycles.farm_id
      and farms.is_virtual = true
  )
);

grant select on public.cultivation_cycles to anon;