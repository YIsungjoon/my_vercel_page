-- Phase 2E: collection agent lifecycle, source grant history, and credential references.

alter table public.collection_agents
  add column version integer not null default 1,
  add column updated_by uuid references auth.users(id) on delete restrict,
  add column status_reason_code text not null default 'REGISTERED',
  add column status_note text,
  add column status_changed_at timestamptz not null default now();

update public.collection_agents
set updated_by = created_by,
    status_changed_at = created_at
where updated_by is null;

alter table public.collection_agents
  alter column updated_by set not null,
  add constraint collection_agents_version_check check (version >= 1),
  add constraint collection_agents_status_reason_check
    check (status_reason_code ~ '^[A-Z][A-Z0-9_]*$');

alter table public.collection_agent_sources
  add column status text not null default 'ACTIVE',
  add column version integer not null default 1,
  add column grant_reason_code text not null default 'INITIAL_GRANT',
  add column grant_note text,
  add column revoked_by uuid references auth.users(id) on delete restrict,
  add column revoked_at timestamptz,
  add column revocation_reason_code text,
  add column revocation_note text,
  add column updated_at timestamptz not null default now(),
  add constraint collection_agent_sources_status_check
    check (status in ('ACTIVE', 'REVOKED')),
  add constraint collection_agent_sources_version_check check (version >= 1),
  add constraint collection_agent_sources_grant_reason_check
    check (grant_reason_code ~ '^[A-Z][A-Z0-9_]*$'),
  add constraint collection_agent_sources_revocation_reason_check
    check (
      revocation_reason_code is null
      or revocation_reason_code ~ '^[A-Z][A-Z0-9_]*$'
    ),
  add constraint collection_agent_sources_lifecycle_check
    check (
      (
        status = 'ACTIVE'
        and revoked_by is null
        and revoked_at is null
        and revocation_reason_code is null
        and revocation_note is null
      )
      or (
        status = 'REVOKED'
        and revoked_by is not null
        and revoked_at is not null
        and revocation_reason_code is not null
      )
    );

create table public.collection_agent_status_transitions (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  agent_id uuid not null,
  agent_version integer not null,
  from_status text,
  to_status text not null,
  reason_code text not null,
  note text,
  changed_by uuid not null references auth.users(id) on delete restrict,
  changed_at timestamptz not null default now(),
  constraint collection_agent_status_transitions_agent_version_key
    unique (agent_id, agent_version),
  constraint collection_agent_status_transitions_agent_same_farm_fkey
    foreign key (farm_id, agent_id)
    references public.collection_agents(farm_id, id)
    on delete cascade,
  constraint collection_agent_status_transitions_version_check
    check (agent_version >= 1),
  constraint collection_agent_status_transitions_from_check
    check (from_status is null or from_status in ('ACTIVE', 'PAUSED', 'REVOKED')),
  constraint collection_agent_status_transitions_to_check
    check (to_status in ('ACTIVE', 'PAUSED', 'REVOKED')),
  constraint collection_agent_status_transitions_change_check
    check (from_status is null or from_status <> to_status),
  constraint collection_agent_status_transitions_reason_check
    check (reason_code ~ '^[A-Z][A-Z0-9_]*$')
);

create table public.collection_agent_source_grant_events (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  agent_id uuid not null,
  source_id uuid not null,
  grant_version integer not null,
  event_type text not null,
  reason_code text not null,
  note text,
  changed_by uuid not null references auth.users(id) on delete restrict,
  changed_at timestamptz not null default now(),
  constraint collection_agent_source_events_version_key
    unique (agent_id, source_id, grant_version),
  constraint collection_agent_source_events_grant_same_farm_fkey
    foreign key (farm_id, agent_id, source_id)
    references public.collection_agent_sources(farm_id, agent_id, source_id)
    on delete cascade,
  constraint collection_agent_source_events_version_check check (grant_version >= 1),
  constraint collection_agent_source_events_type_check
    check (event_type in ('GRANTED', 'REVOKED')),
  constraint collection_agent_source_events_reason_check
    check (reason_code ~ '^[A-Z][A-Z0-9_]*$')
);

create table public.collection_agent_credentials (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  agent_id uuid not null,
  credential_version integer not null,
  secret_reference text not null,
  secret_fingerprint_sha256 text not null,
  status text not null default 'ACTIVE',
  valid_from timestamptz not null default now(),
  expires_at timestamptz,
  rotated_from_credential_id uuid,
  change_reason_code text not null,
  change_note text,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  retired_by uuid references auth.users(id) on delete restrict,
  retired_at timestamptz,
  revoked_by uuid references auth.users(id) on delete restrict,
  revoked_at timestamptz,
  constraint collection_agent_credentials_agent_version_key
    unique (agent_id, credential_version),
  constraint collection_agent_credentials_secret_reference_key unique (secret_reference),
  constraint collection_agent_credentials_farm_agent_id_key
    unique (farm_id, agent_id, id),
  constraint collection_agent_credentials_agent_same_farm_fkey
    foreign key (farm_id, agent_id)
    references public.collection_agents(farm_id, id)
    on delete cascade,
  constraint collection_agent_credentials_rotated_from_same_agent_fkey
    foreign key (farm_id, agent_id, rotated_from_credential_id)
    references public.collection_agent_credentials(farm_id, agent_id, id)
    on delete restrict,
  constraint collection_agent_credentials_version_check check (credential_version >= 1),
  constraint collection_agent_credentials_reference_check
    check (
      char_length(secret_reference) between 11 and 255
      and secret_reference ~ '^vault://[A-Za-z0-9][A-Za-z0-9_./:-]*$'
    ),
  constraint collection_agent_credentials_fingerprint_check
    check (secret_fingerprint_sha256 ~ '^[0-9a-f]{64}$'),
  constraint collection_agent_credentials_status_check
    check (status in ('ACTIVE', 'RETIRED', 'REVOKED')),
  constraint collection_agent_credentials_validity_check
    check (expires_at is null or expires_at > valid_from),
  constraint collection_agent_credentials_reason_check
    check (change_reason_code ~ '^[A-Z][A-Z0-9_]*$'),
  constraint collection_agent_credentials_lifecycle_check
    check (
      (
        status = 'ACTIVE'
        and retired_by is null
        and retired_at is null
        and revoked_by is null
        and revoked_at is null
      )
      or (
        status = 'RETIRED'
        and retired_by is not null
        and retired_at is not null
        and revoked_by is null
        and revoked_at is null
      )
      or (
        status = 'REVOKED'
        and revoked_by is not null
        and revoked_at is not null
        and num_nonnulls(retired_by, retired_at) in (0, 2)
      )
    )
);

create unique index collection_agent_credentials_one_active_idx
on public.collection_agent_credentials(agent_id)
where status = 'ACTIVE';

create table public.collection_agent_credential_events (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  agent_id uuid not null,
  credential_id uuid not null,
  credential_version integer not null,
  event_type text not null,
  reason_code text not null,
  note text,
  changed_by uuid not null references auth.users(id) on delete restrict,
  changed_at timestamptz not null default now(),
  constraint collection_agent_credential_events_event_key
    unique (credential_id, event_type),
  constraint collection_agent_credential_events_credential_same_agent_fkey
    foreign key (farm_id, agent_id, credential_id)
    references public.collection_agent_credentials(farm_id, agent_id, id)
    on delete cascade,
  constraint collection_agent_credential_events_version_check
    check (credential_version >= 1),
  constraint collection_agent_credential_events_type_check
    check (event_type in ('REGISTERED', 'ROTATED', 'RETIRED', 'REVOKED')),
  constraint collection_agent_credential_events_reason_check
    check (reason_code ~ '^[A-Z][A-Z0-9_]*$')
);

insert into public.collection_agent_status_transitions (
  farm_id, agent_id, agent_version, from_status, to_status,
  reason_code, changed_by, changed_at
)
select
  farm_id, id, version, null, status,
  status_reason_code, created_by, created_at
from public.collection_agents;

insert into public.collection_agent_source_grant_events (
  farm_id, agent_id, source_id, grant_version, event_type,
  reason_code, note, changed_by, changed_at
)
select
  farm_id, agent_id, source_id, version, 'GRANTED',
  grant_reason_code, grant_note, granted_by, granted_at
from public.collection_agent_sources;

create index collection_agent_status_transitions_agent_idx
on public.collection_agent_status_transitions(agent_id, changed_at desc);

create index collection_agent_source_events_agent_idx
on public.collection_agent_source_grant_events(agent_id, changed_at desc);

create index collection_agent_credentials_agent_idx
on public.collection_agent_credentials(agent_id, credential_version desc);

create index collection_agent_credential_events_agent_idx
on public.collection_agent_credential_events(agent_id, changed_at desc);

create trigger set_collection_agent_sources_updated_at
before update on public.collection_agent_sources
for each row execute function public.set_updated_at();

create or replace function public.enforce_active_collection_batch_context()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1
    from public.collection_agent_sources as grant_row
    join public.collection_agents as agent
      on agent.farm_id = grant_row.farm_id
     and agent.id = grant_row.agent_id
    join public.observation_sources as source
      on source.farm_id = grant_row.farm_id
     and source.id = grant_row.source_id
    where grant_row.farm_id = new.farm_id
      and grant_row.agent_id = new.agent_id
      and grant_row.source_id = new.source_id
      and grant_row.status = 'ACTIVE'
      and agent.status = 'ACTIVE'
      and source.is_active
  ) then
    raise exception 'Active collector and source grant are required for an ingest batch';
  end if;

  return new;
end;
$$;

create trigger enforce_active_collection_batch_context
before insert on public.observation_ingest_batches
for each row execute function public.enforce_active_collection_batch_context();

create or replace function public.enforce_active_collection_observation_context()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.collector_agent_id is not null and not exists (
    select 1
    from public.collection_agent_sources as grant_row
    join public.collection_agents as agent
      on agent.farm_id = grant_row.farm_id
     and agent.id = grant_row.agent_id
    where grant_row.farm_id = new.farm_id
      and grant_row.agent_id = new.collector_agent_id
      and grant_row.source_id = new.source_id
      and grant_row.status = 'ACTIVE'
      and agent.status = 'ACTIVE'
  ) then
    raise exception 'Active collector and source grant are required to record an observation';
  end if;

  return new;
end;
$$;

create trigger enforce_active_collection_observation_context
before insert on public.stream_observations
for each row execute function public.enforce_active_collection_observation_context();

create or replace function public.collection_agent_management_response(target_agent_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_agent public.collection_agents;
  selected_sources jsonb;
  selected_credentials jsonb;
begin
  select * into selected_agent
  from public.collection_agents
  where id = target_agent_id;

  if not found then
    raise exception 'Collection agent was not found';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(grant_row) order by grant_row.status, grant_row.source_id),
    '[]'::jsonb
  ) into selected_sources
  from public.collection_agent_sources as grant_row
  where grant_row.agent_id = target_agent_id;

  select coalesce(
    jsonb_agg(to_jsonb(credential) order by credential.credential_version desc),
    '[]'::jsonb
  ) into selected_credentials
  from public.collection_agent_credentials as credential
  where credential.agent_id = target_agent_id;

  return jsonb_build_object(
    'agent', to_jsonb(selected_agent),
    'source_grants', selected_sources,
    'credentials', selected_credentials
  );
end;
$$;

create or replace function public.transition_collection_agent_status(
  target_farm_id uuid,
  target_agent_id uuid,
  expected_version integer,
  target_status text,
  reason_code text,
  status_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  current_agent public.collection_agents;
  updated_agent public.collection_agents;
  current_grant public.collection_agent_sources;
  current_credential public.collection_agent_credentials;
  normalized_reason text := nullif(trim(reason_code), '');
  normalized_note text := nullif(trim(status_note), '');
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to change a collection agent status';
  end if;

  if expected_version < 1 then
    raise exception 'Expected collection agent version must be at least 1';
  end if;

  if target_status not in ('ACTIVE', 'PAUSED', 'REVOKED') then
    raise exception 'Collection agent status is not supported';
  end if;

  if normalized_reason is null or normalized_reason !~ '^[A-Z][A-Z0-9_]*$' then
    raise exception 'A valid collection agent status reason is required';
  end if;

  select * into current_agent
  from public.collection_agents
  where farm_id = target_farm_id
    and id = target_agent_id
  for update;

  if not found then
    raise exception 'Collection agent was not found for this farm';
  end if;

  if current_agent.version <> expected_version then
    raise exception using
      errcode = '40001',
      message = 'Collection agent version conflict';
  end if;

  if current_agent.status = target_status then
    return public.collection_agent_management_response(current_agent.id);
  end if;

  if current_agent.status = 'REVOKED'
     or (current_agent.status = 'ACTIVE' and target_status not in ('PAUSED', 'REVOKED'))
     or (current_agent.status = 'PAUSED' and target_status not in ('ACTIVE', 'REVOKED')) then
    raise exception 'Collection agent status transition is not allowed';
  end if;

  if target_status = 'ACTIVE' and not exists (
    select 1
    from public.collection_agent_sources
    where farm_id = target_farm_id
      and agent_id = target_agent_id
      and status = 'ACTIVE'
  ) then
    raise exception 'An active collection agent requires at least one active source grant';
  end if;

  update public.collection_agents
  set status = target_status,
      version = current_agent.version + 1,
      updated_by = auth.uid(),
      status_reason_code = normalized_reason,
      status_note = normalized_note,
      status_changed_at = now()
  where id = current_agent.id
  returning * into updated_agent;

  insert into public.collection_agent_status_transitions (
    farm_id, agent_id, agent_version, from_status, to_status,
    reason_code, note, changed_by, changed_at
  ) values (
    target_farm_id,
    updated_agent.id,
    updated_agent.version,
    current_agent.status,
    updated_agent.status,
    normalized_reason,
    normalized_note,
    auth.uid(),
    updated_agent.status_changed_at
  );

  if target_status = 'REVOKED' then
    for current_grant in
      select *
      from public.collection_agent_sources
      where farm_id = target_farm_id
        and agent_id = target_agent_id
        and status = 'ACTIVE'
      order by source_id
      for update
    loop
      update public.collection_agent_sources
      set status = 'REVOKED',
          version = current_grant.version + 1,
          revoked_by = auth.uid(),
          revoked_at = now(),
          revocation_reason_code = 'AGENT_REVOKED',
          revocation_note = normalized_note
      where agent_id = current_grant.agent_id
        and source_id = current_grant.source_id
      returning * into current_grant;

      insert into public.collection_agent_source_grant_events (
        farm_id, agent_id, source_id, grant_version, event_type,
        reason_code, note, changed_by, changed_at
      ) values (
        current_grant.farm_id,
        current_grant.agent_id,
        current_grant.source_id,
        current_grant.version,
        'REVOKED',
        'AGENT_REVOKED',
        normalized_note,
        auth.uid(),
        current_grant.revoked_at
      );
    end loop;

    for current_credential in
      select *
      from public.collection_agent_credentials
      where farm_id = target_farm_id
        and agent_id = target_agent_id
        and status <> 'REVOKED'
      order by credential_version
      for update
    loop
      update public.collection_agent_credentials
      set status = 'REVOKED',
          change_reason_code = 'AGENT_REVOKED',
          change_note = normalized_note,
          revoked_by = auth.uid(),
          revoked_at = now()
      where id = current_credential.id
      returning * into current_credential;

      insert into public.collection_agent_credential_events (
        farm_id, agent_id, credential_id, credential_version,
        event_type, reason_code, note, changed_by, changed_at
      ) values (
        current_credential.farm_id,
        current_credential.agent_id,
        current_credential.id,
        current_credential.credential_version,
        'REVOKED',
        'AGENT_REVOKED',
        normalized_note,
        auth.uid(),
        current_credential.revoked_at
      );
    end loop;
  end if;

  return public.collection_agent_management_response(updated_agent.id);
end;
$$;

create or replace function public.set_collection_agent_sources(
  target_farm_id uuid,
  target_agent_id uuid,
  expected_version integer,
  authorized_source_ids uuid[],
  reason_code text,
  change_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  current_agent public.collection_agents;
  current_grant public.collection_agent_sources;
  requested_source_id uuid;
  requested_count integer;
  valid_count integer;
  changed_count integer := 0;
  normalized_reason text := nullif(trim(reason_code), '');
  normalized_note text := nullif(trim(change_note), '');
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to change collection agent sources';
  end if;

  if expected_version < 1 then
    raise exception 'Expected collection agent version must be at least 1';
  end if;

  if normalized_reason is null or normalized_reason !~ '^[A-Z][A-Z0-9_]*$' then
    raise exception 'A valid source grant change reason is required';
  end if;

  requested_count := cardinality(coalesce(authorized_source_ids, array[]::uuid[]));
  if (
    select count(distinct source_id)
    from unnest(coalesce(authorized_source_ids, array[]::uuid[])) as requested(source_id)
  ) <> requested_count then
    raise exception 'Authorized source ids must be unique';
  end if;

  select * into current_agent
  from public.collection_agents
  where farm_id = target_farm_id
    and id = target_agent_id
  for update;

  if not found then
    raise exception 'Collection agent was not found for this farm';
  end if;

  if current_agent.version <> expected_version then
    raise exception using
      errcode = '40001',
      message = 'Collection agent version conflict';
  end if;

  if current_agent.status = 'REVOKED' then
    raise exception 'A revoked collection agent cannot receive source grants';
  end if;

  if current_agent.status = 'ACTIVE' and requested_count < 1 then
    raise exception 'An active collection agent requires at least one source grant';
  end if;

  select count(*) into valid_count
  from public.observation_sources
  where farm_id = target_farm_id
    and id = any(coalesce(authorized_source_ids, array[]::uuid[]))
    and is_active;

  if valid_count <> requested_count then
    raise exception 'Every authorized source must be active and belong to the farm';
  end if;

  for current_grant in
    select *
    from public.collection_agent_sources
    where farm_id = target_farm_id
      and agent_id = target_agent_id
      and status = 'ACTIVE'
      and not (source_id = any(coalesce(authorized_source_ids, array[]::uuid[])))
    order by source_id
    for update
  loop
    update public.collection_agent_sources
    set status = 'REVOKED',
        version = current_grant.version + 1,
        revoked_by = auth.uid(),
        revoked_at = now(),
        revocation_reason_code = normalized_reason,
        revocation_note = normalized_note
    where agent_id = current_grant.agent_id
      and source_id = current_grant.source_id
    returning * into current_grant;

    insert into public.collection_agent_source_grant_events (
      farm_id, agent_id, source_id, grant_version, event_type,
      reason_code, note, changed_by, changed_at
    ) values (
      current_grant.farm_id,
      current_grant.agent_id,
      current_grant.source_id,
      current_grant.version,
      'REVOKED',
      normalized_reason,
      normalized_note,
      auth.uid(),
      current_grant.revoked_at
    );

    changed_count := changed_count + 1;
  end loop;

  foreach requested_source_id in array coalesce(authorized_source_ids, array[]::uuid[])
  loop
    select * into current_grant
    from public.collection_agent_sources
    where agent_id = target_agent_id
      and source_id = requested_source_id
    for update;

    if not found then
      insert into public.collection_agent_sources (
        farm_id, agent_id, source_id, granted_by,
        grant_reason_code, grant_note
      ) values (
        target_farm_id,
        target_agent_id,
        requested_source_id,
        auth.uid(),
        normalized_reason,
        normalized_note
      )
      returning * into current_grant;

      insert into public.collection_agent_source_grant_events (
        farm_id, agent_id, source_id, grant_version, event_type,
        reason_code, note, changed_by, changed_at
      ) values (
        current_grant.farm_id,
        current_grant.agent_id,
        current_grant.source_id,
        current_grant.version,
        'GRANTED',
        normalized_reason,
        normalized_note,
        auth.uid(),
        current_grant.granted_at
      );

      changed_count := changed_count + 1;
    elsif current_grant.status = 'REVOKED' then
      update public.collection_agent_sources
      set status = 'ACTIVE',
          version = current_grant.version + 1,
          granted_by = auth.uid(),
          granted_at = now(),
          grant_reason_code = normalized_reason,
          grant_note = normalized_note,
          revoked_by = null,
          revoked_at = null,
          revocation_reason_code = null,
          revocation_note = null
      where agent_id = current_grant.agent_id
        and source_id = current_grant.source_id
      returning * into current_grant;

      insert into public.collection_agent_source_grant_events (
        farm_id, agent_id, source_id, grant_version, event_type,
        reason_code, note, changed_by, changed_at
      ) values (
        current_grant.farm_id,
        current_grant.agent_id,
        current_grant.source_id,
        current_grant.version,
        'GRANTED',
        normalized_reason,
        normalized_note,
        auth.uid(),
        current_grant.granted_at
      );

      changed_count := changed_count + 1;
    end if;
  end loop;

  if changed_count > 0 then
    update public.collection_agents
    set version = version + 1,
        updated_by = auth.uid()
    where id = current_agent.id;
  end if;

  return public.collection_agent_management_response(current_agent.id);
end;
$$;

create or replace function public.rotate_collection_agent_credential(
  target_farm_id uuid,
  target_agent_id uuid,
  expected_agent_version integer,
  expected_current_credential_id uuid,
  credential_secret_reference text,
  credential_fingerprint_sha256 text,
  credential_expires_at timestamptz,
  reason_code text,
  change_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  current_agent public.collection_agents;
  active_credential public.collection_agent_credentials;
  previous_credential public.collection_agent_credentials;
  created_credential public.collection_agent_credentials;
  current_active_id uuid;
  previous_credential_id uuid;
  next_credential_version integer;
  normalized_reference text := nullif(trim(credential_secret_reference), '');
  normalized_fingerprint text := lower(nullif(trim(credential_fingerprint_sha256), ''));
  normalized_reason text := nullif(trim(reason_code), '');
  normalized_note text := nullif(trim(change_note), '');
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to rotate a collection agent credential';
  end if;

  if expected_agent_version < 1 then
    raise exception 'Expected collection agent version must be at least 1';
  end if;

  if normalized_reference is null
     or char_length(normalized_reference) > 255
     or normalized_reference !~ '^vault://[A-Za-z0-9][A-Za-z0-9_./:-]*$' then
    raise exception 'A valid Vault secret reference is required';
  end if;

  if normalized_fingerprint is null
     or normalized_fingerprint !~ '^[0-9a-f]{64}$' then
    raise exception 'A SHA-256 credential fingerprint is required';
  end if;

  if normalized_reason is null or normalized_reason !~ '^[A-Z][A-Z0-9_]*$' then
    raise exception 'A valid credential rotation reason is required';
  end if;

  if credential_expires_at is not null and credential_expires_at <= now() then
    raise exception 'Credential expiry must be in the future';
  end if;

  select * into current_agent
  from public.collection_agents
  where farm_id = target_farm_id
    and id = target_agent_id
  for update;

  if not found then
    raise exception 'Collection agent was not found for this farm';
  end if;

  if current_agent.version <> expected_agent_version then
    raise exception using
      errcode = '40001',
      message = 'Collection agent version conflict';
  end if;

  if current_agent.status = 'REVOKED' then
    raise exception 'A revoked collection agent cannot receive credentials';
  end if;

  select * into active_credential
  from public.collection_agent_credentials
  where farm_id = target_farm_id
    and agent_id = target_agent_id
    and status = 'ACTIVE'
  for update;

  current_active_id := active_credential.id;
  if current_active_id is distinct from expected_current_credential_id then
    raise exception using
      errcode = '40001',
      message = 'Collection agent credential version conflict';
  end if;

  if exists (
    select 1
    from public.collection_agent_credentials
    where agent_id = target_agent_id
      and secret_fingerprint_sha256 = normalized_fingerprint
  ) then
    raise exception 'Credential fingerprint has already been used for this agent';
  end if;

  select * into previous_credential
  from public.collection_agent_credentials
  where agent_id = target_agent_id
  order by credential_version desc
  limit 1;

  previous_credential_id := previous_credential.id;
  next_credential_version := coalesce(previous_credential.credential_version, 0) + 1;

  if current_active_id is not null then
    update public.collection_agent_credentials
    set status = 'RETIRED',
        change_reason_code = normalized_reason,
        change_note = normalized_note,
        retired_by = auth.uid(),
        retired_at = now()
    where id = current_active_id
    returning * into active_credential;

    insert into public.collection_agent_credential_events (
      farm_id, agent_id, credential_id, credential_version,
      event_type, reason_code, note, changed_by, changed_at
    ) values (
      active_credential.farm_id,
      active_credential.agent_id,
      active_credential.id,
      active_credential.credential_version,
      'RETIRED',
      normalized_reason,
      normalized_note,
      auth.uid(),
      active_credential.retired_at
    );
  end if;

  insert into public.collection_agent_credentials (
    farm_id, agent_id, credential_version, secret_reference,
    secret_fingerprint_sha256, expires_at, rotated_from_credential_id,
    change_reason_code, change_note, created_by
  ) values (
    target_farm_id,
    target_agent_id,
    next_credential_version,
    normalized_reference,
    normalized_fingerprint,
    credential_expires_at,
    previous_credential_id,
    normalized_reason,
    normalized_note,
    auth.uid()
  )
  returning * into created_credential;

  insert into public.collection_agent_credential_events (
    farm_id, agent_id, credential_id, credential_version,
    event_type, reason_code, note, changed_by, changed_at
  ) values (
    created_credential.farm_id,
    created_credential.agent_id,
    created_credential.id,
    created_credential.credential_version,
    case when previous_credential_id is null then 'REGISTERED' else 'ROTATED' end,
    normalized_reason,
    normalized_note,
    auth.uid(),
    created_credential.created_at
  );

  update public.collection_agents
  set version = version + 1,
      updated_by = auth.uid()
  where id = current_agent.id;

  return public.collection_agent_management_response(current_agent.id);
end;
$$;

create or replace function public.revoke_collection_agent_credential(
  target_farm_id uuid,
  target_agent_id uuid,
  target_credential_id uuid,
  expected_agent_version integer,
  reason_code text,
  change_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  current_agent public.collection_agents;
  current_credential public.collection_agent_credentials;
  normalized_reason text := nullif(trim(reason_code), '');
  normalized_note text := nullif(trim(change_note), '');
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to revoke a collection agent credential';
  end if;

  if expected_agent_version < 1 then
    raise exception 'Expected collection agent version must be at least 1';
  end if;

  if normalized_reason is null or normalized_reason !~ '^[A-Z][A-Z0-9_]*$' then
    raise exception 'A valid credential revocation reason is required';
  end if;

  select * into current_agent
  from public.collection_agents
  where farm_id = target_farm_id
    and id = target_agent_id
  for update;

  if not found then
    raise exception 'Collection agent was not found for this farm';
  end if;

  if current_agent.version <> expected_agent_version then
    raise exception using
      errcode = '40001',
      message = 'Collection agent version conflict';
  end if;

  select * into current_credential
  from public.collection_agent_credentials
  where farm_id = target_farm_id
    and agent_id = target_agent_id
    and id = target_credential_id
  for update;

  if not found then
    raise exception 'Collection agent credential was not found';
  end if;

  if current_credential.status = 'REVOKED' then
    return public.collection_agent_management_response(current_agent.id);
  end if;

  update public.collection_agent_credentials
  set status = 'REVOKED',
      change_reason_code = normalized_reason,
      change_note = normalized_note,
      revoked_by = auth.uid(),
      revoked_at = now()
  where id = current_credential.id
  returning * into current_credential;

  insert into public.collection_agent_credential_events (
    farm_id, agent_id, credential_id, credential_version,
    event_type, reason_code, note, changed_by, changed_at
  ) values (
    current_credential.farm_id,
    current_credential.agent_id,
    current_credential.id,
    current_credential.credential_version,
    'REVOKED',
    normalized_reason,
    normalized_note,
    auth.uid(),
    current_credential.revoked_at
  );

  update public.collection_agents
  set version = version + 1,
      updated_by = auth.uid()
  where id = current_agent.id;

  return public.collection_agent_management_response(current_agent.id);
end;
$$;

create or replace function public.create_collection_agent(
  target_farm_id uuid,
  agent_code text,
  agent_name text,
  agent_kind text,
  authorized_source_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  created_agent public.collection_agents;
  created_grant public.collection_agent_sources;
  requested_source_id uuid;
  requested_source_count integer;
  valid_source_count integer;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to create a collection agent';
  end if;

  if nullif(trim(agent_code), '') is null
     or trim(agent_code) !~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$' then
    raise exception 'A valid agent code is required';
  end if;

  if nullif(trim(agent_name), '') is null then
    raise exception 'A collection agent name is required';
  end if;

  if agent_kind not in (
    'WEATHER_COLLECTOR', 'SENSOR_GATEWAY', 'DATA_IMPORTER', 'SYSTEM_INTEGRATION'
  ) then
    raise exception 'Collection agent kind is not supported';
  end if;

  requested_source_count := coalesce(cardinality(authorized_source_ids), 0);
  if requested_source_count < 1 then
    raise exception 'At least one authorized source is required';
  end if;

  if (
    select count(distinct source_id)
    from unnest(authorized_source_ids) as requested(source_id)
  ) <> requested_source_count then
    raise exception 'Authorized source ids must be unique';
  end if;

  select count(*) into valid_source_count
  from public.observation_sources
  where farm_id = target_farm_id
    and id = any(authorized_source_ids)
    and is_active;

  if valid_source_count <> requested_source_count then
    raise exception 'Every authorized source must be active and belong to the farm';
  end if;

  insert into public.collection_agents (
    farm_id, agent_code, name, agent_kind, created_by, updated_by
  ) values (
    target_farm_id,
    trim(agent_code),
    trim(agent_name),
    agent_kind,
    auth.uid(),
    auth.uid()
  )
  returning * into created_agent;

  insert into public.collection_agent_status_transitions (
    farm_id, agent_id, agent_version, from_status, to_status,
    reason_code, changed_by, changed_at
  ) values (
    created_agent.farm_id,
    created_agent.id,
    created_agent.version,
    null,
    created_agent.status,
    'REGISTERED',
    auth.uid(),
    created_agent.created_at
  );

  foreach requested_source_id in array authorized_source_ids
  loop
    insert into public.collection_agent_sources (
      farm_id, agent_id, source_id, granted_by
    ) values (
      target_farm_id,
      created_agent.id,
      requested_source_id,
      auth.uid()
    )
    returning * into created_grant;

    insert into public.collection_agent_source_grant_events (
      farm_id, agent_id, source_id, grant_version, event_type,
      reason_code, changed_by, changed_at
    ) values (
      created_grant.farm_id,
      created_grant.agent_id,
      created_grant.source_id,
      created_grant.version,
      'GRANTED',
      created_grant.grant_reason_code,
      auth.uid(),
      created_grant.granted_at
    );
  end loop;

  return public.collection_agent_management_response(created_agent.id);
end;
$$;

create or replace function public.get_collection_agent_configuration(
  target_farm_slug text,
  target_agent_code text,
  target_source_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  selected_farm public.farms;
  selected_agent public.collection_agents;
  selected_source public.observation_sources;
  selected_grant public.collection_agent_sources;
  selected_credential public.collection_agent_credentials;
  selected_streams jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role is required';
  end if;

  select * into selected_farm
  from public.farms
  where slug = trim(target_farm_slug);

  if not found then
    raise exception 'Farm was not found';
  end if;

  select agent.* into selected_agent
  from public.collection_agents as agent
  where agent.farm_id = selected_farm.id
    and agent.agent_code = trim(target_agent_code)
    and agent.status = 'ACTIVE';

  if not found then
    raise exception 'Active collection agent was not found';
  end if;

  select source.* into selected_source
  from public.observation_sources as source
  join public.collection_agent_sources as grant_row
    on grant_row.farm_id = source.farm_id
   and grant_row.source_id = source.id
   and grant_row.agent_id = selected_agent.id
  where source.farm_id = selected_farm.id
    and source.source_code = trim(target_source_code)
    and source.is_active
    and grant_row.status = 'ACTIVE';

  if not found then
    raise exception 'Authorized active observation source was not found';
  end if;

  select * into selected_grant
  from public.collection_agent_sources
  where farm_id = selected_farm.id
    and agent_id = selected_agent.id
    and source_id = selected_source.id
    and status = 'ACTIVE';

  select * into selected_credential
  from public.collection_agent_credentials
  where farm_id = selected_farm.id
    and agent_id = selected_agent.id
    and status = 'ACTIVE'
    and valid_from <= now()
    and (expires_at is null or expires_at > now())
  order by credential_version desc
  limit 1;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'id', stream.id,
        'field_code', stream.field_code,
        'stream_code', stream.stream_code,
        'unit_code', stream.unit_code
      ) order by stream.field_code
    ),
    '[]'::jsonb
  ) into selected_streams
  from public.observation_streams as stream
  where stream.farm_id = selected_farm.id
    and stream.source_id = selected_source.id
    and stream.is_active;

  return jsonb_build_object(
    'farm', jsonb_build_object(
      'id', selected_farm.id,
      'name', selected_farm.name,
      'slug', selected_farm.slug,
      'latitude', selected_farm.latitude,
      'longitude', selected_farm.longitude,
      'timezone', selected_farm.timezone
    ),
    'agent', jsonb_build_object(
      'id', selected_agent.id,
      'agent_code', selected_agent.agent_code,
      'agent_kind', selected_agent.agent_kind,
      'version', selected_agent.version
    ),
    'source', jsonb_build_object(
      'id', selected_source.id,
      'source_code', selected_source.source_code,
      'provider_code', selected_source.provider_code,
      'grant_version', selected_grant.version
    ),
    'credential', case
      when selected_credential.id is null then null
      else jsonb_build_object(
        'id', selected_credential.id,
        'credential_version', selected_credential.credential_version,
        'secret_reference', selected_credential.secret_reference,
        'secret_fingerprint_sha256', selected_credential.secret_fingerprint_sha256,
        'expires_at', selected_credential.expires_at
      )
    end,
    'streams', selected_streams
  );
end;
$$;

alter table public.collection_agent_status_transitions enable row level security;
alter table public.collection_agent_source_grant_events enable row level security;
alter table public.collection_agent_credentials enable row level security;
alter table public.collection_agent_credential_events enable row level security;

create policy managers_read_collection_agent_status_transitions
on public.collection_agent_status_transitions
for select to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy managers_read_collection_agent_source_grant_events
on public.collection_agent_source_grant_events
for select to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy managers_read_collection_agent_credentials
on public.collection_agent_credentials
for select to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy managers_read_collection_agent_credential_events
on public.collection_agent_credential_events
for select to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']));

grant select on table
  public.collection_agent_status_transitions,
  public.collection_agent_source_grant_events,
  public.collection_agent_credentials,
  public.collection_agent_credential_events
to authenticated;

revoke all on table
  public.collection_agent_status_transitions,
  public.collection_agent_source_grant_events,
  public.collection_agent_credentials,
  public.collection_agent_credential_events
from anon;

revoke insert, update, delete, truncate, trigger, references on table
  public.collection_agent_status_transitions,
  public.collection_agent_source_grant_events,
  public.collection_agent_credentials,
  public.collection_agent_credential_events
from authenticated;

revoke execute on function public.enforce_active_collection_batch_context()
from public, anon, authenticated, service_role;

revoke execute on function public.enforce_active_collection_observation_context()
from public, anon, authenticated, service_role;

revoke execute on function public.collection_agent_management_response(uuid)
from public, anon, authenticated, service_role;

revoke execute on function public.transition_collection_agent_status(
  uuid, uuid, integer, text, text, text
) from public, anon;

revoke execute on function public.set_collection_agent_sources(
  uuid, uuid, integer, uuid[], text, text
) from public, anon;

revoke execute on function public.rotate_collection_agent_credential(
  uuid, uuid, integer, uuid, text, text, timestamptz, text, text
) from public, anon;

revoke execute on function public.revoke_collection_agent_credential(
  uuid, uuid, uuid, integer, text, text
) from public, anon;

grant execute on function public.transition_collection_agent_status(
  uuid, uuid, integer, text, text, text
) to authenticated;

grant execute on function public.set_collection_agent_sources(
  uuid, uuid, integer, uuid[], text, text
) to authenticated;

grant execute on function public.rotate_collection_agent_credential(
  uuid, uuid, integer, uuid, text, text, timestamptz, text, text
) to authenticated;

grant execute on function public.revoke_collection_agent_credential(
  uuid, uuid, uuid, integer, text, text
) to authenticated;

comment on table public.collection_agent_status_transitions is
  'Immutable manager-attributed collection agent status history.';

comment on table public.collection_agent_source_grant_events is
  'Immutable grant and revocation history for collection agent source scope.';

comment on table public.collection_agent_credentials is
  'Credential generations containing Vault references and fingerprints, never secret values.';

comment on table public.collection_agent_credential_events is
  'Immutable registration, rotation, retirement, and revocation receipts for credential generations.';
