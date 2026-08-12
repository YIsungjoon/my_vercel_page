-- Phase 2C: relational collection principals, ingest batches, domain events, and outbox delivery.

create table public.collection_agents (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  agent_code text not null,
  name text not null,
  agent_kind text not null,
  status text not null default 'ACTIVE',
  authentication_mode text not null default 'PLATFORM_SERVICE_ROLE',
  last_seen_at timestamptz,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint collection_agents_farm_code_key unique (farm_id, agent_code),
  constraint collection_agents_farm_id_id_key unique (farm_id, id),
  constraint collection_agents_code_format_check
    check (agent_code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'),
  constraint collection_agents_name_check check (char_length(trim(name)) > 0),
  constraint collection_agents_kind_check
    check (agent_kind in ('WEATHER_COLLECTOR', 'SENSOR_GATEWAY', 'DATA_IMPORTER', 'SYSTEM_INTEGRATION')),
  constraint collection_agents_status_check check (status in ('ACTIVE', 'PAUSED', 'REVOKED')),
  constraint collection_agents_authentication_check
    check (authentication_mode = 'PLATFORM_SERVICE_ROLE')
);

create table public.collection_agent_sources (
  farm_id uuid not null references public.farms(id) on delete cascade,
  agent_id uuid not null,
  source_id uuid not null,
  granted_by uuid not null references auth.users(id) on delete restrict,
  granted_at timestamptz not null default now(),
  primary key (agent_id, source_id),
  constraint collection_agent_sources_farm_agent_source_key
    unique (farm_id, agent_id, source_id),
  constraint collection_agent_sources_agent_same_farm_fkey
    foreign key (farm_id, agent_id)
    references public.collection_agents(farm_id, id)
    on delete cascade,
  constraint collection_agent_sources_source_same_farm_fkey
    foreign key (farm_id, source_id)
    references public.observation_sources(farm_id, id)
    on delete cascade
);

create table public.observation_ingest_batches (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  agent_id uuid not null,
  source_id uuid not null,
  external_batch_key text not null,
  status text not null default 'OPEN',
  expected_count integer,
  accepted_count integer not null default 0,
  rejected_count integer not null default 0,
  failure_code text,
  failure_message text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint observation_ingest_batches_agent_key unique (agent_id, external_batch_key),
  constraint observation_ingest_batches_farm_id_id_key unique (farm_id, id),
  constraint observation_ingest_batches_farm_agent_source_id_key
    unique (farm_id, agent_id, source_id, id),
  constraint observation_ingest_batches_agent_source_same_farm_fkey
    foreign key (farm_id, agent_id, source_id)
    references public.collection_agent_sources(farm_id, agent_id, source_id)
    on delete restrict,
  constraint observation_ingest_batches_key_format_check
    check (external_batch_key ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$'),
  constraint observation_ingest_batches_status_check
    check (status in ('OPEN', 'COMPLETED', 'PARTIAL', 'FAILED')),
  constraint observation_ingest_batches_counts_check
    check (
      accepted_count >= 0
      and rejected_count >= 0
      and (expected_count is null or expected_count >= 0)
      and (
        expected_count is null
        or accepted_count + rejected_count <= expected_count
      )
    ),
  constraint observation_ingest_batches_terminal_check
    check (
      (status = 'OPEN' and finished_at is null)
      or (status <> 'OPEN' and finished_at is not null)
    ),
  constraint observation_ingest_batches_failure_check
    check (
      (status in ('PARTIAL', 'FAILED') and failure_code is not null)
      or (status in ('OPEN', 'COMPLETED') and failure_code is null and failure_message is null)
    ),
  constraint observation_ingest_batches_failure_code_check
    check (failure_code is null or failure_code ~ '^[A-Z][A-Z0-9_]*$')
);

alter table public.observation_streams
  add constraint observation_streams_farm_source_id_id_key
  unique (farm_id, source_id, id);

alter table public.stream_observations
  add column source_id uuid,
  add column collector_agent_id uuid,
  add column ingest_batch_id uuid;

update public.stream_observations as observation
set source_id = stream.source_id
from public.observation_streams as stream
where stream.farm_id = observation.farm_id
  and stream.id = observation.stream_id;

alter table public.stream_observations
  alter column source_id set not null,
  alter column recorded_by drop not null,
  add constraint stream_observations_farm_source_stream_id_id_key
    unique (farm_id, source_id, stream_id, id),
  add constraint stream_observations_source_same_stream_fkey
    foreign key (farm_id, source_id, stream_id)
    references public.observation_streams(farm_id, source_id, id)
    on delete restrict,
  add constraint stream_observations_collector_same_farm_fkey
    foreign key (farm_id, collector_agent_id)
    references public.collection_agents(farm_id, id)
    on delete restrict,
  add constraint stream_observations_batch_same_agent_source_fkey
    foreign key (farm_id, collector_agent_id, source_id, ingest_batch_id)
    references public.observation_ingest_batches(farm_id, agent_id, source_id, id)
    on delete restrict,
  add constraint stream_observations_actor_check
    check (num_nonnulls(recorded_by, collector_agent_id) = 1),
  add constraint stream_observations_ingest_context_check
    check (
      (collector_agent_id is null and ingest_batch_id is null)
      or (collector_agent_id is not null and ingest_batch_id is not null)
    );

create table public.domain_events (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  source_id uuid not null,
  stream_id uuid not null,
  observation_id uuid not null,
  collector_agent_id uuid,
  ingest_batch_id uuid,
  event_name text not null default 'OBSERVATION_RECORDED',
  observation_event_type text not null,
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  constraint domain_events_observation_key unique (observation_id),
  constraint domain_events_farm_id_id_key unique (farm_id, id),
  constraint domain_events_name_check check (event_name = 'OBSERVATION_RECORDED'),
  constraint domain_events_type_check
    check (observation_event_type in ('WEATHER_OBSERVATION', 'SENSOR_OBSERVATION')),
  constraint domain_events_observation_same_stream_fkey
    foreign key (farm_id, source_id, stream_id, observation_id)
    references public.stream_observations(farm_id, source_id, stream_id, id)
    on delete restrict,
  constraint domain_events_collector_same_farm_fkey
    foreign key (farm_id, collector_agent_id)
    references public.collection_agents(farm_id, id)
    on delete restrict,
  constraint domain_events_batch_same_farm_fkey
    foreign key (farm_id, ingest_batch_id)
    references public.observation_ingest_batches(farm_id, id)
    on delete restrict,
  constraint domain_events_ingest_context_check
    check (
      (collector_agent_id is null and ingest_batch_id is null)
      or (collector_agent_id is not null and ingest_batch_id is not null)
    )
);

create table public.outbox_messages (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  event_id uuid not null,
  topic text not null,
  status text not null default 'PENDING',
  attempt_count integer not null default 0,
  max_attempts integer not null default 5,
  available_at timestamptz not null default now(),
  locked_at timestamptz,
  locked_by text,
  published_at timestamptz,
  last_error_code text,
  last_error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint outbox_messages_event_topic_key unique (event_id, topic),
  constraint outbox_messages_farm_id_id_key unique (farm_id, id),
  constraint outbox_messages_event_same_farm_fkey
    foreign key (farm_id, event_id)
    references public.domain_events(farm_id, id)
    on delete restrict,
  constraint outbox_messages_topic_format_check
    check (topic ~ '^[a-z][a-z0-9_.-]*$'),
  constraint outbox_messages_status_check
    check (status in ('PENDING', 'CLAIMED', 'PUBLISHED', 'RETRY', 'DEAD_LETTER')),
  constraint outbox_messages_attempts_check
    check (attempt_count >= 0 and max_attempts between 1 and 100 and attempt_count <= max_attempts),
  constraint outbox_messages_lock_check
    check (
      (status = 'CLAIMED' and locked_at is not null and locked_by is not null)
      or (status <> 'CLAIMED' and locked_at is null and locked_by is null)
    ),
  constraint outbox_messages_publish_check
    check (
      (status = 'PUBLISHED' and published_at is not null)
      or (status <> 'PUBLISHED' and published_at is null)
    ),
  constraint outbox_messages_error_code_check
    check (last_error_code is null or last_error_code ~ '^[A-Z][A-Z0-9_]*$')
);

create table public.outbox_delivery_attempts (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  message_id uuid not null,
  attempt_no integer not null,
  worker_id text not null,
  status text not null default 'CLAIMED',
  claimed_at timestamptz not null default now(),
  finished_at timestamptz,
  error_code text,
  error_message text,
  constraint outbox_delivery_attempts_message_attempt_key unique (message_id, attempt_no),
  constraint outbox_delivery_attempts_message_same_farm_fkey
    foreign key (farm_id, message_id)
    references public.outbox_messages(farm_id, id)
    on delete restrict,
  constraint outbox_delivery_attempts_attempt_check check (attempt_no >= 1),
  constraint outbox_delivery_attempts_worker_check check (char_length(trim(worker_id)) between 1 and 100),
  constraint outbox_delivery_attempts_status_check check (status in ('CLAIMED', 'PUBLISHED', 'FAILED')),
  constraint outbox_delivery_attempts_terminal_check
    check (
      (status = 'CLAIMED' and finished_at is null and error_code is null and error_message is null)
      or (status = 'PUBLISHED' and finished_at is not null and error_code is null and error_message is null)
      or (status = 'FAILED' and finished_at is not null and error_code is not null)
    ),
  constraint outbox_delivery_attempts_error_code_check
    check (error_code is null or error_code ~ '^[A-Z][A-Z0-9_]*$')
);

create table public.outbox_dead_letters (
  message_id uuid primary key,
  farm_id uuid not null references public.farms(id) on delete cascade,
  final_attempt_no integer not null,
  reason_code text not null,
  reason_message text,
  dead_lettered_at timestamptz not null default now(),
  constraint outbox_dead_letters_message_same_farm_fkey
    foreign key (farm_id, message_id)
    references public.outbox_messages(farm_id, id)
    on delete restrict,
  constraint outbox_dead_letters_attempt_check check (final_attempt_no >= 1),
  constraint outbox_dead_letters_reason_code_check
    check (reason_code ~ '^[A-Z][A-Z0-9_]*$')
);

create index collection_agents_farm_status_idx
on public.collection_agents(farm_id, status, agent_code);

create index observation_ingest_batches_farm_started_idx
on public.observation_ingest_batches(farm_id, started_at desc);

create index domain_events_farm_occurred_idx
on public.domain_events(farm_id, occurred_at desc);

create index outbox_messages_claim_idx
on public.outbox_messages(status, available_at, created_at)
where status in ('PENDING', 'RETRY');

create index outbox_delivery_attempts_message_idx
on public.outbox_delivery_attempts(message_id, attempt_no desc);

create trigger set_collection_agents_updated_at
before update on public.collection_agents
for each row execute function public.set_updated_at();

create trigger set_observation_ingest_batches_updated_at
before update on public.observation_ingest_batches
for each row execute function public.set_updated_at();

create trigger set_outbox_messages_updated_at
before update on public.outbox_messages
for each row execute function public.set_updated_at();

create or replace function public.persist_stream_observation(
  target_farm_id uuid,
  target_stream_id uuid,
  observation_observed_at timestamptz,
  observation_idempotency_key text,
  observation_numeric_value numeric,
  observation_text_value text,
  observation_boolean_value boolean,
  observation_received_at timestamptz,
  source_quality_status text,
  source_sequence text,
  actor_user_id uuid,
  actor_agent_id uuid,
  target_ingest_batch_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  selected_stream record;
  selected_calibration public.observation_calibrations;
  existing_observation public.stream_observations;
  created_observation public.stream_observations;
  created_event public.domain_events;
  derived_quality_status text;
  latency_minutes numeric;
  effective_received_at timestamptz;
begin
  if num_nonnulls(actor_user_id, actor_agent_id) <> 1 then
    raise exception 'Exactly one observation actor is required';
  end if;

  if (actor_agent_id is null) <> (target_ingest_batch_id is null) then
    raise exception 'Collector observations require an ingest batch';
  end if;

  if nullif(trim(observation_idempotency_key), '') is null
     or trim(observation_idempotency_key)
       !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$' then
    raise exception 'A valid observation idempotency key is required';
  end if;

  select * into existing_observation
  from public.stream_observations
  where stream_id = target_stream_id
    and idempotency_key = trim(observation_idempotency_key);

  if found then
    if existing_observation.farm_id <> target_farm_id
       or existing_observation.observed_at <> observation_observed_at
       or (
         observation_received_at is not null
         and existing_observation.received_at <> observation_received_at
       )
       or existing_observation.numeric_value is distinct from observation_numeric_value
       or existing_observation.text_value is distinct from nullif(observation_text_value, '')
       or existing_observation.boolean_value is distinct from observation_boolean_value
       or existing_observation.source_quality_status <> source_quality_status
       or existing_observation.source_sequence
         is distinct from nullif(trim(source_sequence), '')
       or existing_observation.recorded_by is distinct from actor_user_id
       or existing_observation.collector_agent_id is distinct from actor_agent_id
       or existing_observation.ingest_batch_id is distinct from target_ingest_batch_id then
      raise exception 'Observation idempotency key is already used by another request';
    end if;

    return public.stream_observation_response(existing_observation.id);
  end if;

  select
    stream.*,
    source.is_active as source_is_active,
    field.value_type,
    field.event_type
  into selected_stream
  from public.observation_streams as stream
  join public.observation_sources as source
    on source.farm_id = stream.farm_id
   and source.id = stream.source_id
  join public.observation_fields as field
    on field.code = stream.field_code
  where stream.farm_id = target_farm_id
    and stream.id = target_stream_id;

  if not found then
    raise exception 'Observation stream was not found for this farm';
  end if;

  if not selected_stream.is_active or not selected_stream.source_is_active then
    raise exception 'An active source and stream are required';
  end if;

  if actor_agent_id is not null then
    perform 1
    from public.observation_ingest_batches as batch
    join public.collection_agents as agent
      on agent.farm_id = batch.farm_id
     and agent.id = batch.agent_id
    where batch.farm_id = target_farm_id
      and batch.id = target_ingest_batch_id
      and batch.agent_id = actor_agent_id
      and batch.source_id = selected_stream.source_id
      and batch.status = 'OPEN'
      and agent.status = 'ACTIVE'
    for update of batch;

    if not found then
      raise exception 'An active collector and open matching ingest batch are required';
    end if;
  end if;

  if observation_observed_at is null then
    raise exception 'Observation timestamp is required';
  end if;

  effective_received_at := coalesce(observation_received_at, now());

  if observation_observed_at > effective_received_at + interval '5 minutes' then
    raise exception 'Observation time is later than the allowed clock skew';
  end if;

  if num_nonnulls(
    observation_numeric_value,
    nullif(observation_text_value, ''),
    observation_boolean_value
  ) <> 1 then
    raise exception 'Exactly one typed observation value is required';
  end if;

  if (selected_stream.value_type = 'NUMERIC' and observation_numeric_value is null)
     or (selected_stream.value_type = 'TEXT' and nullif(observation_text_value, '') is null)
     or (selected_stream.value_type = 'BOOLEAN' and observation_boolean_value is null) then
    raise exception 'Observation value type does not match the stream field';
  end if;

  if source_quality_status not in ('VALID', 'SUSPECT', 'INVALID') then
    raise exception 'Source quality status is not supported';
  end if;

  select * into selected_calibration
  from public.observation_calibrations
  where farm_id = target_farm_id
    and stream_id = target_stream_id
    and status = 'VALID'
    and valid_from <= observation_observed_at
    and (valid_until is null or valid_until > observation_observed_at)
  order by valid_from desc
  limit 1;

  latency_minutes :=
    extract(epoch from effective_received_at - observation_observed_at) / 60;

  derived_quality_status := case
    when source_quality_status = 'INVALID' then 'INVALID'
    when source_quality_status = 'SUSPECT' then 'SUSPECT'
    when selected_stream.requires_calibration and selected_calibration.id is null
      then 'UNCALIBRATED'
    when latency_minutes > selected_stream.max_latency_minutes then 'LATE'
    else 'VALID'
  end;

  insert into public.stream_observations (
    farm_id, source_id, stream_id, calibration_id, observed_at, received_at,
    numeric_value, text_value, boolean_value, source_quality_status,
    quality_status, source_sequence, idempotency_key, recorded_by,
    collector_agent_id, ingest_batch_id
  )
  values (
    target_farm_id,
    selected_stream.source_id,
    target_stream_id,
    selected_calibration.id,
    observation_observed_at,
    effective_received_at,
    observation_numeric_value,
    nullif(observation_text_value, ''),
    observation_boolean_value,
    source_quality_status,
    derived_quality_status,
    nullif(trim(source_sequence), ''),
    trim(observation_idempotency_key),
    actor_user_id,
    actor_agent_id,
    target_ingest_batch_id
  )
  returning * into created_observation;

  if source_quality_status = 'SUSPECT' then
    insert into public.observation_quality_findings (
      farm_id, stream_id, observation_id, finding_code, severity, detail
    ) values (
      target_farm_id, target_stream_id, created_observation.id,
      'SOURCE_SUSPECT', 'WARNING',
      'The source reported this observation as suspect.'
    );
  elsif source_quality_status = 'INVALID' then
    insert into public.observation_quality_findings (
      farm_id, stream_id, observation_id, finding_code, severity, detail
    ) values (
      target_farm_id, target_stream_id, created_observation.id,
      'SOURCE_INVALID', 'ERROR',
      'The source reported this observation as invalid.'
    );
  end if;

  if selected_stream.requires_calibration and selected_calibration.id is null then
    insert into public.observation_quality_findings (
      farm_id, stream_id, observation_id, finding_code, severity, detail
    ) values (
      target_farm_id, target_stream_id, created_observation.id,
      'NO_VALID_CALIBRATION', 'ERROR',
      'No valid calibration covered the observation time.'
    );
  end if;

  if latency_minutes > selected_stream.max_latency_minutes then
    insert into public.observation_quality_findings (
      farm_id, stream_id, observation_id, finding_code, severity, detail
    ) values (
      target_farm_id, target_stream_id, created_observation.id,
      'RECEIVED_LATE', 'WARNING',
      'The observation exceeded the stream latency threshold.'
    );
  end if;

  insert into public.domain_events (
    farm_id, source_id, stream_id, observation_id,
    collector_agent_id, ingest_batch_id, observation_event_type, occurred_at
  ) values (
    target_farm_id, selected_stream.source_id, target_stream_id,
    created_observation.id, actor_agent_id, target_ingest_batch_id,
    selected_stream.event_type, observation_observed_at
  )
  returning * into created_event;

  insert into public.outbox_messages (farm_id, event_id, topic)
  values (target_farm_id, created_event.id, 'observation.recorded.v1');

  if target_ingest_batch_id is not null then
    update public.observation_ingest_batches
    set accepted_count = accepted_count + 1
    where id = target_ingest_batch_id;

    update public.collection_agents
    set last_seen_at = greatest(coalesce(last_seen_at, effective_received_at), effective_received_at)
    where id = actor_agent_id;
  end if;

  return public.stream_observation_response(created_observation.id);
end;
$$;

create or replace function public.record_stream_observation(
  target_farm_id uuid,
  target_stream_id uuid,
  observation_observed_at timestamptz,
  observation_idempotency_key text,
  observation_numeric_value numeric default null,
  observation_text_value text default null,
  observation_boolean_value boolean default null,
  observation_received_at timestamptz default null,
  source_quality_status text default 'VALID',
  source_sequence text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if not public.has_farm_role(
    target_farm_id,
    array['owner', 'manager', 'worker']
  ) then
    raise exception 'Farm action permission is required to record an observation';
  end if;

  return public.persist_stream_observation(
    target_farm_id,
    target_stream_id,
    observation_observed_at,
    observation_idempotency_key,
    observation_numeric_value,
    observation_text_value,
    observation_boolean_value,
    observation_received_at,
    source_quality_status,
    source_sequence,
    auth.uid(),
    null,
    null
  );
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
    farm_id, agent_code, name, agent_kind, created_by
  ) values (
    target_farm_id, trim(agent_code), trim(agent_name), agent_kind, auth.uid()
  )
  returning * into created_agent;

  insert into public.collection_agent_sources (
    farm_id, agent_id, source_id, granted_by
  )
  select target_farm_id, created_agent.id, requested.source_id, auth.uid()
  from unnest(authorized_source_ids) as requested(source_id);

  return jsonb_build_object(
    'agent', to_jsonb(created_agent),
    'authorized_source_ids', to_jsonb(authorized_source_ids)
  );
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
    and source.is_active;

  if not found then
    raise exception 'Authorized active observation source was not found';
  end if;

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
      'agent_kind', selected_agent.agent_kind
    ),
    'source', jsonb_build_object(
      'id', selected_source.id,
      'source_code', selected_source.source_code,
      'provider_code', selected_source.provider_code
    ),
    'streams', selected_streams
  );
end;
$$;

create or replace function public.open_observation_ingest_batch(
  target_farm_id uuid,
  target_agent_id uuid,
  target_source_id uuid,
  batch_external_key text,
  batch_expected_count integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  existing_batch public.observation_ingest_batches;
  created_batch public.observation_ingest_batches;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role is required';
  end if;

  if nullif(trim(batch_external_key), '') is null
     or trim(batch_external_key) !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$' then
    raise exception 'A valid external batch key is required';
  end if;

  if batch_expected_count is not null
     and (batch_expected_count < 1 or batch_expected_count > 10000) then
    raise exception 'Expected batch count must be between 1 and 10000';
  end if;

  select * into existing_batch
  from public.observation_ingest_batches
  where agent_id = target_agent_id
    and external_batch_key = trim(batch_external_key);

  if found then
    if existing_batch.farm_id <> target_farm_id
       or existing_batch.source_id <> target_source_id
       or existing_batch.expected_count is distinct from batch_expected_count then
      raise exception 'External batch key is already used by another request';
    end if;

    return to_jsonb(existing_batch);
  end if;

  if not exists (
    select 1
    from public.collection_agent_sources as grant_row
    join public.collection_agents as agent
      on agent.farm_id = grant_row.farm_id
     and agent.id = grant_row.agent_id
    join public.observation_sources as source
      on source.farm_id = grant_row.farm_id
     and source.id = grant_row.source_id
    where grant_row.farm_id = target_farm_id
      and grant_row.agent_id = target_agent_id
      and grant_row.source_id = target_source_id
      and agent.status = 'ACTIVE'
      and source.is_active
  ) then
    raise exception 'Active collector is not authorized for this source';
  end if;

  insert into public.observation_ingest_batches (
    farm_id, agent_id, source_id, external_batch_key, expected_count
  ) values (
    target_farm_id,
    target_agent_id,
    target_source_id,
    trim(batch_external_key),
    batch_expected_count
  )
  returning * into created_batch;

  update public.collection_agents
  set last_seen_at = greatest(coalesce(last_seen_at, now()), now())
  where id = target_agent_id;

  return to_jsonb(created_batch);
end;
$$;

create or replace function public.complete_observation_ingest_batch(
  target_farm_id uuid,
  target_batch_id uuid,
  completion_status text,
  batch_expected_count integer,
  batch_rejected_count integer default 0,
  batch_failure_code text default null,
  batch_failure_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  selected_batch public.observation_ingest_batches;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role is required';
  end if;

  select * into selected_batch
  from public.observation_ingest_batches
  where farm_id = target_farm_id
    and id = target_batch_id
  for update;

  if not found then
    raise exception 'Ingest batch was not found for this farm';
  end if;

  if completion_status not in ('COMPLETED', 'PARTIAL', 'FAILED') then
    raise exception 'Batch completion status is not supported';
  end if;

  if batch_expected_count < 1 or batch_expected_count > 10000
     or batch_rejected_count < 0
     or selected_batch.accepted_count + batch_rejected_count <> batch_expected_count then
    raise exception 'Batch counts must reconcile exactly';
  end if;

  if selected_batch.expected_count is not null
     and selected_batch.expected_count <> batch_expected_count then
    raise exception 'Batch expected count cannot change';
  end if;

  if completion_status = 'COMPLETED'
     and (batch_rejected_count <> 0 or selected_batch.accepted_count <> batch_expected_count) then
    raise exception 'Completed batch cannot contain rejected observations';
  elsif completion_status = 'PARTIAL'
     and (
       selected_batch.accepted_count < 1
       or batch_rejected_count < 1
       or nullif(trim(batch_failure_code), '') is null
     ) then
    raise exception 'Partial batch requires accepted and rejected observations with a failure code';
  elsif completion_status = 'FAILED'
     and (
       selected_batch.accepted_count <> 0
       or batch_rejected_count <> batch_expected_count
       or nullif(trim(batch_failure_code), '') is null
     ) then
    raise exception 'Failed batch requires every observation to be rejected with a failure code';
  end if;

  if completion_status in ('PARTIAL', 'FAILED')
     and trim(batch_failure_code) !~ '^[A-Z][A-Z0-9_]*$' then
    raise exception 'A valid batch failure code is required';
  end if;

  if selected_batch.status <> 'OPEN' then
    if selected_batch.status = completion_status
       and selected_batch.expected_count = batch_expected_count
       and selected_batch.rejected_count = batch_rejected_count
       and selected_batch.failure_code
         is not distinct from nullif(trim(batch_failure_code), '')
       and selected_batch.failure_message
         is not distinct from nullif(trim(batch_failure_message), '') then
      return to_jsonb(selected_batch);
    end if;

    raise exception 'Ingest batch is already terminal';
  end if;

  update public.observation_ingest_batches
  set status = completion_status,
      expected_count = batch_expected_count,
      rejected_count = batch_rejected_count,
      failure_code = case
        when completion_status = 'COMPLETED' then null
        else trim(batch_failure_code)
      end,
      failure_message = case
        when completion_status = 'COMPLETED' then null
        else nullif(trim(batch_failure_message), '')
      end,
      finished_at = now()
  where id = target_batch_id
  returning * into selected_batch;

  return to_jsonb(selected_batch);
end;
$$;

create or replace function public.record_agent_stream_observation(
  target_farm_id uuid,
  target_agent_id uuid,
  target_ingest_batch_id uuid,
  target_stream_id uuid,
  observation_observed_at timestamptz,
  observation_idempotency_key text,
  observation_numeric_value numeric default null,
  observation_text_value text default null,
  observation_boolean_value boolean default null,
  observation_received_at timestamptz default null,
  source_quality_status text default 'VALID',
  source_sequence text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role is required';
  end if;

  return public.persist_stream_observation(
    target_farm_id,
    target_stream_id,
    observation_observed_at,
    observation_idempotency_key,
    observation_numeric_value,
    observation_text_value,
    observation_boolean_value,
    observation_received_at,
    source_quality_status,
    source_sequence,
    null,
    target_agent_id,
    target_ingest_batch_id
  );
end;
$$;

create or replace function public.claim_outbox_messages(
  worker_id text,
  claim_limit integer default 20,
  lease_seconds integer default 300
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  expired_message public.outbox_messages;
  selected_message public.outbox_messages;
  claimed_message public.outbox_messages;
  claimed_messages jsonb := '[]'::jsonb;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role is required';
  end if;

  if nullif(trim(worker_id), '') is null or char_length(trim(worker_id)) > 100 then
    raise exception 'A valid outbox worker id is required';
  end if;

  if claim_limit < 1 or claim_limit > 100 then
    raise exception 'Claim limit must be between 1 and 100';
  end if;

  if lease_seconds < 30 or lease_seconds > 3600 then
    raise exception 'Lease seconds must be between 30 and 3600';
  end if;

  for expired_message in
    select message.*
    from public.outbox_messages as message
    where message.status = 'CLAIMED'
      and message.locked_at <= now() - make_interval(secs => lease_seconds)
    order by message.locked_at
    for update skip locked
  loop
    update public.outbox_delivery_attempts
    set status = 'FAILED',
        finished_at = now(),
        error_code = 'LEASE_EXPIRED',
        error_message = 'The outbox delivery lease expired before completion.'
    where message_id = expired_message.id
      and attempt_no = expired_message.attempt_count
      and status = 'CLAIMED';

    if expired_message.attempt_count >= expired_message.max_attempts then
      update public.outbox_messages
      set status = 'DEAD_LETTER',
          locked_at = null,
          locked_by = null,
          last_error_code = 'LEASE_EXPIRED',
          last_error_message = 'The outbox delivery lease expired before completion.'
      where id = expired_message.id;

      insert into public.outbox_dead_letters (
        message_id, farm_id, final_attempt_no, reason_code, reason_message
      ) values (
        expired_message.id,
        expired_message.farm_id,
        expired_message.attempt_count,
        'LEASE_EXPIRED',
        'The outbox delivery lease expired before completion.'
      ) on conflict (message_id) do nothing;
    else
      update public.outbox_messages
      set status = 'RETRY',
          available_at = now(),
          locked_at = null,
          locked_by = null,
          last_error_code = 'LEASE_EXPIRED',
          last_error_message = 'The outbox delivery lease expired before completion.'
      where id = expired_message.id;
    end if;
  end loop;

  for selected_message in
    select message.*
    from public.outbox_messages as message
    where message.status in ('PENDING', 'RETRY')
      and message.available_at <= now()
      and message.attempt_count < message.max_attempts
    order by message.available_at, message.created_at, message.id
    limit claim_limit
    for update skip locked
  loop
    update public.outbox_messages
    set status = 'CLAIMED',
        attempt_count = attempt_count + 1,
        locked_at = now(),
        locked_by = trim(worker_id)
    where id = selected_message.id
    returning * into claimed_message;

    insert into public.outbox_delivery_attempts (
      farm_id, message_id, attempt_no, worker_id
    ) values (
      claimed_message.farm_id,
      claimed_message.id,
      claimed_message.attempt_count,
      trim(worker_id)
    );

    claimed_messages := claimed_messages || jsonb_build_array(to_jsonb(claimed_message));
  end loop;

  return jsonb_build_object(
    'claimed_count', jsonb_array_length(claimed_messages),
    'messages', claimed_messages
  );
end;
$$;

create or replace function public.complete_outbox_delivery(
  target_farm_id uuid,
  target_message_id uuid,
  worker_id text,
  attempt_no integer,
  delivery_succeeded boolean,
  delivery_error_code text default null,
  delivery_error_message text default null,
  retry_delay_seconds integer default 60
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  selected_message public.outbox_messages;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role is required';
  end if;

  select * into selected_message
  from public.outbox_messages
  where farm_id = target_farm_id
    and id = target_message_id
  for update;

  if not found then
    raise exception 'Outbox message was not found for this farm';
  end if;

  if selected_message.status <> 'CLAIMED' then
    if delivery_succeeded
       and delivery_error_code is null
       and delivery_error_message is null
       and selected_message.status = 'PUBLISHED'
       and selected_message.attempt_count = attempt_no
       and exists (
         select 1
         from public.outbox_delivery_attempts as delivery_attempt
         where delivery_attempt.message_id = target_message_id
           and delivery_attempt.attempt_no = $4
           and delivery_attempt.worker_id = trim($3)
           and delivery_attempt.status = 'PUBLISHED'
       ) then
      return to_jsonb(selected_message);
    elsif not delivery_succeeded
       and selected_message.status in ('RETRY', 'DEAD_LETTER')
       and selected_message.attempt_count = attempt_no
       and selected_message.last_error_code
         is not distinct from nullif(trim(delivery_error_code), '')
       and selected_message.last_error_message
         is not distinct from nullif(trim(delivery_error_message), '')
       and exists (
         select 1
         from public.outbox_delivery_attempts as delivery_attempt
         where delivery_attempt.message_id = target_message_id
           and delivery_attempt.attempt_no = $4
           and delivery_attempt.worker_id = trim($3)
           and delivery_attempt.status = 'FAILED'
           and delivery_attempt.error_code
             is not distinct from nullif(trim(delivery_error_code), '')
           and delivery_attempt.error_message
             is not distinct from nullif(trim(delivery_error_message), '')
       ) then
      return to_jsonb(selected_message);
    end if;

    raise exception 'Outbox claim does not match this delivery receipt';
  end if;

  if selected_message.locked_by <> trim(worker_id)
     or selected_message.attempt_count <> attempt_no then
    raise exception 'Outbox claim does not match this delivery receipt';
  end if;

  if retry_delay_seconds < 0 or retry_delay_seconds > 86400 then
    raise exception 'Retry delay seconds must be between 0 and 86400';
  end if;

  if delivery_succeeded then
    if delivery_error_code is not null or delivery_error_message is not null then
      raise exception 'Successful delivery cannot include an error';
    end if;

    update public.outbox_delivery_attempts as delivery_attempt
    set status = 'PUBLISHED',
        finished_at = now()
    where delivery_attempt.message_id = target_message_id
      and delivery_attempt.attempt_no = $4
      and delivery_attempt.worker_id = trim($3)
      and delivery_attempt.status = 'CLAIMED';

    if not found then
      raise exception 'Claimed delivery attempt was not found';
    end if;

    update public.outbox_messages
    set status = 'PUBLISHED',
        published_at = now(),
        locked_at = null,
        locked_by = null,
        last_error_code = null,
        last_error_message = null
    where id = target_message_id
    returning * into selected_message;
  else
    if nullif(trim(delivery_error_code), '') is null
       or trim(delivery_error_code) !~ '^[A-Z][A-Z0-9_]*$' then
      raise exception 'A valid delivery error code is required';
    end if;

    update public.outbox_delivery_attempts as delivery_attempt
    set status = 'FAILED',
        finished_at = now(),
        error_code = trim(delivery_error_code),
        error_message = nullif(trim(delivery_error_message), '')
    where delivery_attempt.message_id = target_message_id
      and delivery_attempt.attempt_no = $4
      and delivery_attempt.worker_id = trim($3)
      and delivery_attempt.status = 'CLAIMED';

    if not found then
      raise exception 'Claimed delivery attempt was not found';
    end if;

    if selected_message.attempt_count >= selected_message.max_attempts then
      update public.outbox_messages
      set status = 'DEAD_LETTER',
          locked_at = null,
          locked_by = null,
          last_error_code = trim(delivery_error_code),
          last_error_message = nullif(trim(delivery_error_message), '')
      where id = target_message_id
      returning * into selected_message;

      insert into public.outbox_dead_letters (
        message_id, farm_id, final_attempt_no, reason_code, reason_message
      ) values (
        target_message_id,
        target_farm_id,
        attempt_no,
        trim(delivery_error_code),
        nullif(trim(delivery_error_message), '')
      );
    else
      update public.outbox_messages
      set status = 'RETRY',
          available_at = now() + make_interval(secs => retry_delay_seconds),
          locked_at = null,
          locked_by = null,
          last_error_code = trim(delivery_error_code),
          last_error_message = nullif(trim(delivery_error_message), '')
      where id = target_message_id
      returning * into selected_message;
    end if;
  end if;

  return to_jsonb(selected_message);
end;
$$;

insert into public.domain_events (
  farm_id, source_id, stream_id, observation_id,
  collector_agent_id, ingest_batch_id, observation_event_type,
  occurred_at, recorded_at
)
select
  observation.farm_id,
  observation.source_id,
  observation.stream_id,
  observation.id,
  observation.collector_agent_id,
  observation.ingest_batch_id,
  field.event_type,
  observation.observed_at,
  observation.created_at
from public.stream_observations as observation
join public.observation_streams as stream
  on stream.farm_id = observation.farm_id
 and stream.id = observation.stream_id
join public.observation_fields as field
  on field.code = stream.field_code
on conflict (observation_id) do nothing;

insert into public.outbox_messages (
  farm_id, event_id, topic, created_at, updated_at
)
select
  event.farm_id,
  event.id,
  'observation.recorded.v1',
  event.recorded_at,
  event.recorded_at
from public.domain_events as event
on conflict (event_id, topic) do nothing;

alter table public.collection_agents enable row level security;
alter table public.collection_agent_sources enable row level security;
alter table public.observation_ingest_batches enable row level security;
alter table public.domain_events enable row level security;
alter table public.outbox_messages enable row level security;
alter table public.outbox_delivery_attempts enable row level security;
alter table public.outbox_dead_letters enable row level security;

create policy managers_read_collection_agents
on public.collection_agents
for select to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy managers_read_collection_agent_sources
on public.collection_agent_sources
for select to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy managers_read_observation_ingest_batches
on public.observation_ingest_batches
for select to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy members_read_domain_events
on public.domain_events
for select to authenticated
using (public.is_farm_member(farm_id));

create policy managers_read_outbox_messages
on public.outbox_messages
for select to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy managers_read_outbox_delivery_attempts
on public.outbox_delivery_attempts
for select to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']));

create policy managers_read_outbox_dead_letters
on public.outbox_dead_letters
for select to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']));

grant select on table
  public.collection_agents,
  public.collection_agent_sources,
  public.observation_ingest_batches,
  public.domain_events,
  public.outbox_messages,
  public.outbox_delivery_attempts,
  public.outbox_dead_letters
to authenticated;

revoke all on table
  public.collection_agents,
  public.collection_agent_sources,
  public.observation_ingest_batches,
  public.domain_events,
  public.outbox_messages,
  public.outbox_delivery_attempts,
  public.outbox_dead_letters
from anon;

revoke insert, update, delete, truncate, trigger, references on table
  public.collection_agents,
  public.collection_agent_sources,
  public.observation_ingest_batches,
  public.domain_events,
  public.outbox_messages,
  public.outbox_delivery_attempts,
  public.outbox_dead_letters
from authenticated;

revoke execute on function public.persist_stream_observation(
  uuid, uuid, timestamptz, text, numeric, text, boolean, timestamptz,
  text, text, uuid, uuid, uuid
) from public, anon, authenticated, service_role;

revoke execute on function public.create_collection_agent(
  uuid, text, text, text, uuid[]
) from public, anon;

revoke execute on function public.get_collection_agent_configuration(
  text, text, text
) from public, anon, authenticated;

revoke execute on function public.open_observation_ingest_batch(
  uuid, uuid, uuid, text, integer
) from public, anon, authenticated;

revoke execute on function public.complete_observation_ingest_batch(
  uuid, uuid, text, integer, integer, text, text
) from public, anon, authenticated;

revoke execute on function public.record_agent_stream_observation(
  uuid, uuid, uuid, uuid, timestamptz, text, numeric, text, boolean,
  timestamptz, text, text
) from public, anon, authenticated;

revoke execute on function public.claim_outbox_messages(
  text, integer, integer
) from public, anon, authenticated;

revoke execute on function public.complete_outbox_delivery(
  uuid, uuid, text, integer, boolean, text, text, integer
) from public, anon, authenticated;

grant execute on function public.create_collection_agent(
  uuid, text, text, text, uuid[]
) to authenticated;

grant execute on function public.get_collection_agent_configuration(
  text, text, text
) to service_role;

grant execute on function public.open_observation_ingest_batch(
  uuid, uuid, uuid, text, integer
) to service_role;

grant execute on function public.complete_observation_ingest_batch(
  uuid, uuid, text, integer, integer, text, text
) to service_role;

grant execute on function public.record_agent_stream_observation(
  uuid, uuid, uuid, uuid, timestamptz, text, numeric, text, boolean,
  timestamptz, text, text
) to service_role;

grant execute on function public.claim_outbox_messages(
  text, integer, integer
) to service_role;

grant execute on function public.complete_outbox_delivery(
  uuid, uuid, text, integer, boolean, text, text, integer
) to service_role;

comment on table public.collection_agents is
  'Farm-scoped logical machine principals authenticated by the platform service role.';

comment on table public.observation_ingest_batches is
  'Relational lifecycle and count receipt for one collector delivery batch.';

comment on table public.domain_events is
  'Immutable typed domain events created transactionally with observations.';

comment on table public.outbox_messages is
  'Transactional outbox state; payload data remains normalized in domain event tables.';

comment on table public.outbox_delivery_attempts is
  'Immutable sequence of outbox claim and delivery outcomes.';

comment on table public.outbox_dead_letters is
  'Terminal relational receipt for messages that exhausted delivery attempts.';
