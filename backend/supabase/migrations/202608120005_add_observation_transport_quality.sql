-- Phase 2F: relational source sequence continuity and clock drift quality.

alter table public.observation_streams
  add column quality_policy_version integer not null default 1,
  add column sequence_policy text not null default 'NONE',
  add column clock_drift_tolerance_seconds integer not null default 300,
  add column quality_policy_updated_by uuid references auth.users(id) on delete restrict;

update public.observation_streams
set quality_policy_updated_by = created_by
where quality_policy_updated_by is null;

alter table public.observation_streams
  alter column quality_policy_updated_by set not null,
  alter column quality_policy_updated_by set default auth.uid(),
  add constraint observation_streams_quality_policy_version_check
    check (quality_policy_version >= 1),
  add constraint observation_streams_sequence_policy_check
    check (sequence_policy in ('NONE', 'MONOTONIC_INTEGER')),
  add constraint observation_streams_clock_drift_tolerance_check
    check (clock_drift_tolerance_seconds between 0 and 300);

drop index if exists public.stream_observations_source_sequence_idx;

create index stream_observations_source_sequence_idx
on public.stream_observations(stream_id, source_sequence)
where source_sequence is not null;

create table public.observation_stream_quality_policy_versions (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  stream_id uuid not null,
  policy_version integer not null,
  sequence_policy text not null,
  clock_drift_tolerance_seconds integer not null,
  reason_code text not null,
  note text,
  changed_by uuid not null references auth.users(id) on delete restrict,
  changed_at timestamptz not null default now(),
  constraint observation_stream_quality_policy_versions_key
    unique (stream_id, policy_version),
  constraint observation_stream_quality_policy_versions_stream_same_farm_fkey
    foreign key (farm_id, stream_id)
    references public.observation_streams(farm_id, id)
    on delete cascade,
  constraint observation_stream_quality_policy_versions_version_check
    check (policy_version >= 1),
  constraint observation_stream_quality_policy_versions_sequence_check
    check (sequence_policy in ('NONE', 'MONOTONIC_INTEGER')),
  constraint observation_stream_quality_policy_versions_drift_check
    check (clock_drift_tolerance_seconds between 0 and 300),
  constraint observation_stream_quality_policy_versions_reason_check
    check (reason_code ~ '^[A-Z][A-Z0-9_]*$')
);

create table public.observation_stream_sequence_states (
  stream_id uuid primary key,
  farm_id uuid not null references public.farms(id) on delete cascade,
  policy_version integer not null,
  last_sequence_value bigint,
  last_observation_id uuid,
  last_observed_at timestamptz,
  receipt_count bigint not null default 0,
  anomaly_count bigint not null default 0,
  version bigint not null default 1,
  updated_at timestamptz not null default now(),
  constraint observation_stream_sequence_states_farm_stream_key
    unique (farm_id, stream_id),
  constraint observation_stream_sequence_states_stream_same_farm_fkey
    foreign key (farm_id, stream_id)
    references public.observation_streams(farm_id, id)
    on delete cascade,
  constraint observation_stream_sequence_states_observation_same_stream_fkey
    foreign key (farm_id, stream_id, last_observation_id)
    references public.stream_observations(farm_id, stream_id, id)
    on delete restrict,
  constraint observation_stream_sequence_states_policy_version_check
    check (policy_version >= 1),
  constraint observation_stream_sequence_states_counts_check
    check (
      receipt_count >= 0
      and anomaly_count >= 0
      and anomaly_count <= receipt_count
      and version >= 1
    ),
  constraint observation_stream_sequence_states_high_watermark_check
    check (
      num_nonnulls(last_sequence_value, last_observation_id, last_observed_at) in (0, 3)
      and (last_sequence_value is null or last_sequence_value >= 0)
    )
);

create table public.observation_transport_quality_receipts (
  observation_id uuid primary key,
  farm_id uuid not null references public.farms(id) on delete cascade,
  stream_id uuid not null,
  policy_version integer not null,
  sequence_policy text not null,
  source_sequence_value bigint,
  previous_high_watermark bigint,
  sequence_status text not null,
  missing_sequence_count bigint not null default 0,
  sequence_state_advanced boolean not null default false,
  clock_drift_seconds numeric(12, 3) not null,
  clock_drift_tolerance_seconds integer not null,
  clock_status text not null,
  evaluated_at timestamptz not null default now(),
  constraint observation_transport_quality_receipts_farm_stream_observation_key
    unique (farm_id, stream_id, observation_id),
  constraint observation_transport_quality_receipts_observation_same_stream_fkey
    foreign key (farm_id, stream_id, observation_id)
    references public.stream_observations(farm_id, stream_id, id)
    on delete cascade,
  constraint observation_transport_quality_receipts_policy_version_check
    check (policy_version >= 1),
  constraint observation_transport_quality_receipts_sequence_policy_check
    check (sequence_policy in ('NONE', 'MONOTONIC_INTEGER')),
  constraint observation_transport_quality_receipts_sequence_status_check
    check (
      sequence_status in (
        'NOT_TRACKED', 'FIRST', 'CONTIGUOUS', 'GAP', 'OUT_OF_ORDER', 'DUPLICATE'
      )
    ),
  constraint observation_transport_quality_receipts_sequence_shape_check
    check (
      (
        sequence_policy = 'NONE'
        and source_sequence_value is null
        and previous_high_watermark is null
        and sequence_status = 'NOT_TRACKED'
        and missing_sequence_count = 0
        and not sequence_state_advanced
      )
      or (
        sequence_policy = 'MONOTONIC_INTEGER'
        and source_sequence_value is not null
        and source_sequence_value >= 0
        and sequence_status <> 'NOT_TRACKED'
        and missing_sequence_count >= 0
        and (sequence_status = 'FIRST') = (previous_high_watermark is null)
        and (sequence_status = 'GAP') = (missing_sequence_count > 0)
        and (
          sequence_state_advanced
          = (sequence_status in ('FIRST', 'CONTIGUOUS', 'GAP'))
        )
      )
    ),
  constraint observation_transport_quality_receipts_clock_drift_check
    check (clock_drift_seconds >= 0),
  constraint observation_transport_quality_receipts_clock_tolerance_check
    check (clock_drift_tolerance_seconds between 0 and 300),
  constraint observation_transport_quality_receipts_clock_status_check
    check (clock_status in ('WITHIN_TOLERANCE', 'CLOCK_AHEAD')),
  constraint observation_transport_quality_receipts_clock_shape_check
    check (
      (clock_status = 'WITHIN_TOLERANCE'
        and clock_drift_seconds <= clock_drift_tolerance_seconds)
      or (clock_status = 'CLOCK_AHEAD'
        and clock_drift_seconds > clock_drift_tolerance_seconds)
    )
);

insert into public.observation_stream_quality_policy_versions (
  farm_id, stream_id, policy_version, sequence_policy,
  clock_drift_tolerance_seconds, reason_code, changed_by, changed_at
)
select
  farm_id,
  id,
  quality_policy_version,
  sequence_policy,
  clock_drift_tolerance_seconds,
  'INITIAL_POLICY',
  created_by,
  created_at
from public.observation_streams;

create index observation_stream_quality_policy_versions_stream_idx
on public.observation_stream_quality_policy_versions(stream_id, policy_version desc);

create index observation_transport_quality_receipts_stream_idx
on public.observation_transport_quality_receipts(stream_id, evaluated_at desc);

create or replace function public.record_initial_observation_stream_quality_policy()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.observation_stream_quality_policy_versions (
    farm_id, stream_id, policy_version, sequence_policy,
    clock_drift_tolerance_seconds, reason_code, changed_by, changed_at
  ) values (
    new.farm_id,
    new.id,
    new.quality_policy_version,
    new.sequence_policy,
    new.clock_drift_tolerance_seconds,
    'INITIAL_POLICY',
    new.created_by,
    new.created_at
  );

  return new;
end;
$$;

create trigger record_initial_observation_stream_quality_policy
after insert on public.observation_streams
for each row execute function public.record_initial_observation_stream_quality_policy();

create or replace function public.update_observation_stream_quality_policy(
  target_farm_id uuid,
  target_stream_id uuid,
  expected_policy_version integer,
  target_sequence_policy text,
  target_clock_drift_tolerance_seconds integer,
  reason_code text,
  policy_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  current_stream public.observation_streams;
  updated_stream public.observation_streams;
  normalized_reason text := nullif(trim(reason_code), '');
  normalized_note text := nullif(trim(policy_note), '');
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to update an observation quality policy';
  end if;

  if expected_policy_version < 1 then
    raise exception 'Expected quality policy version must be at least 1';
  end if;

  if target_sequence_policy not in ('NONE', 'MONOTONIC_INTEGER') then
    raise exception 'Observation sequence policy is not supported';
  end if;

  if target_clock_drift_tolerance_seconds < 0
     or target_clock_drift_tolerance_seconds > 300 then
    raise exception 'Clock drift tolerance must be between 0 and 300 seconds';
  end if;

  if normalized_reason is null or normalized_reason !~ '^[A-Z][A-Z0-9_]*$' then
    raise exception 'A valid observation quality policy reason is required';
  end if;

  select * into current_stream
  from public.observation_streams
  where farm_id = target_farm_id
    and id = target_stream_id
  for update;

  if not found then
    raise exception 'Observation stream was not found for this farm';
  end if;

  if current_stream.quality_policy_version <> expected_policy_version then
    raise exception using
      errcode = '40001',
      message = 'Observation quality policy version conflict';
  end if;

  if current_stream.sequence_policy = target_sequence_policy
     and current_stream.clock_drift_tolerance_seconds
       = target_clock_drift_tolerance_seconds then
    return to_jsonb(current_stream);
  end if;

  update public.observation_streams
  set sequence_policy = target_sequence_policy,
      clock_drift_tolerance_seconds = target_clock_drift_tolerance_seconds,
      quality_policy_version = current_stream.quality_policy_version + 1,
      quality_policy_updated_by = auth.uid()
  where id = current_stream.id
  returning * into updated_stream;

  if current_stream.sequence_policy <> target_sequence_policy then
    delete from public.observation_stream_sequence_states
    where stream_id = current_stream.id;
  end if;

  insert into public.observation_stream_quality_policy_versions (
    farm_id, stream_id, policy_version, sequence_policy,
    clock_drift_tolerance_seconds, reason_code, note, changed_by
  ) values (
    updated_stream.farm_id,
    updated_stream.id,
    updated_stream.quality_policy_version,
    updated_stream.sequence_policy,
    updated_stream.clock_drift_tolerance_seconds,
    normalized_reason,
    normalized_note,
    auth.uid()
  );

  return to_jsonb(updated_stream);
end;
$$;

create or replace function public.stream_observation_response(
  target_observation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_observation public.stream_observations;
  selected_findings jsonb;
  selected_transport_receipt public.observation_transport_quality_receipts;
begin
  select * into selected_observation
  from public.stream_observations
  where id = target_observation_id;

  if not found then
    raise exception 'Stream observation was not found';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(finding) order by finding.detected_at, finding.finding_code),
    '[]'::jsonb
  ) into selected_findings
  from public.observation_quality_findings as finding
  where finding.observation_id = selected_observation.id;

  select * into selected_transport_receipt
  from public.observation_transport_quality_receipts
  where observation_id = selected_observation.id;

  return jsonb_build_object(
    'observation', to_jsonb(selected_observation),
    'quality_findings', selected_findings,
    'transport_quality_receipt', case
      when selected_transport_receipt.observation_id is null then null
      else to_jsonb(selected_transport_receipt)
    end
  );
end;
$$;

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
  sequence_state public.observation_stream_sequence_states;
  derived_quality_status text;
  sequence_status text := 'NOT_TRACKED';
  sequence_value bigint;
  previous_high_watermark bigint;
  missing_sequence_count bigint := 0;
  sequence_state_advanced boolean := false;
  sequence_anomaly boolean := false;
  clock_status text;
  clock_drift_seconds numeric;
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
    and stream.id = target_stream_id
  for share of stream;

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

  if selected_stream.sequence_policy = 'MONOTONIC_INTEGER' then
    if nullif(trim(source_sequence), '') is null
       or trim(source_sequence) !~ '^[0-9]{1,18}$' then
      raise exception 'A monotonic integer source sequence is required for this stream';
    end if;

    sequence_value := trim(source_sequence)::bigint;

    insert into public.observation_stream_sequence_states (
      farm_id, stream_id, policy_version
    ) values (
      target_farm_id,
      target_stream_id,
      selected_stream.quality_policy_version
    )
    on conflict (stream_id) do nothing;

    select * into sequence_state
    from public.observation_stream_sequence_states
    where stream_id = target_stream_id
    for update;

    previous_high_watermark := sequence_state.last_sequence_value;

    if exists (
      select 1
      from public.observation_transport_quality_receipts as prior_receipt
      where prior_receipt.stream_id = target_stream_id
        and prior_receipt.sequence_policy = 'MONOTONIC_INTEGER'
        and prior_receipt.source_sequence_value = sequence_value
    ) then
      sequence_status := 'DUPLICATE';
      sequence_anomaly := true;
    elsif previous_high_watermark is null then
      sequence_status := 'FIRST';
      sequence_state_advanced := true;
    elsif sequence_value < previous_high_watermark then
      sequence_status := 'OUT_OF_ORDER';
      sequence_anomaly := true;
    elsif sequence_value - previous_high_watermark = 1 then
      sequence_status := 'CONTIGUOUS';
      sequence_state_advanced := true;
    else
      sequence_status := 'GAP';
      missing_sequence_count := sequence_value - previous_high_watermark - 1;
      sequence_state_advanced := true;
      sequence_anomaly := true;
    end if;
  end if;

  clock_drift_seconds := greatest(
    extract(epoch from observation_observed_at - effective_received_at),
    0
  );
  clock_status := case
    when clock_drift_seconds > selected_stream.clock_drift_tolerance_seconds
      then 'CLOCK_AHEAD'
    else 'WITHIN_TOLERANCE'
  end;

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
    when sequence_anomaly or clock_status = 'CLOCK_AHEAD' then 'SUSPECT'
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

  insert into public.observation_transport_quality_receipts (
    observation_id, farm_id, stream_id, policy_version, sequence_policy,
    source_sequence_value, previous_high_watermark, sequence_status,
    missing_sequence_count, sequence_state_advanced, clock_drift_seconds,
    clock_drift_tolerance_seconds, clock_status
  ) values (
    created_observation.id,
    target_farm_id,
    target_stream_id,
    selected_stream.quality_policy_version,
    selected_stream.sequence_policy,
    sequence_value,
    previous_high_watermark,
    sequence_status,
    missing_sequence_count,
    sequence_state_advanced,
    clock_drift_seconds,
    selected_stream.clock_drift_tolerance_seconds,
    clock_status
  );

  if selected_stream.sequence_policy = 'MONOTONIC_INTEGER' then
    update public.observation_stream_sequence_states
    set policy_version = selected_stream.quality_policy_version,
        last_sequence_value = case
          when sequence_state_advanced then sequence_value
          else last_sequence_value
        end,
        last_observation_id = case
          when sequence_state_advanced then created_observation.id
          else last_observation_id
        end,
        last_observed_at = case
          when sequence_state_advanced then created_observation.observed_at
          else last_observed_at
        end,
        receipt_count = receipt_count + 1,
        anomaly_count = anomaly_count + case when sequence_anomaly then 1 else 0 end,
        version = version + 1,
        updated_at = now()
    where stream_id = target_stream_id;
  end if;

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

  if sequence_status = 'GAP' then
    insert into public.observation_quality_findings (
      farm_id, stream_id, observation_id, finding_code, severity, detail
    ) values (
      target_farm_id, target_stream_id, created_observation.id,
      'SOURCE_SEQUENCE_GAP', 'WARNING',
      'The source sequence skipped ' || missing_sequence_count::text || ' value(s).'
    );
  elsif sequence_status = 'OUT_OF_ORDER' then
    insert into public.observation_quality_findings (
      farm_id, stream_id, observation_id, finding_code, severity, detail
    ) values (
      target_farm_id, target_stream_id, created_observation.id,
      'SOURCE_SEQUENCE_OUT_OF_ORDER', 'WARNING',
      'The source sequence is lower than the current high watermark.'
    );
  elsif sequence_status = 'DUPLICATE' then
    insert into public.observation_quality_findings (
      farm_id, stream_id, observation_id, finding_code, severity, detail
    ) values (
      target_farm_id, target_stream_id, created_observation.id,
      'SOURCE_SEQUENCE_DUPLICATE', 'WARNING',
      'The source sequence equals the current high watermark.'
    );
  end if;

  if clock_status = 'CLOCK_AHEAD' then
    insert into public.observation_quality_findings (
      farm_id, stream_id, observation_id, finding_code, severity, detail
    ) values (
      target_farm_id, target_stream_id, created_observation.id,
      'SOURCE_CLOCK_AHEAD', 'WARNING',
      'The source timestamp is ahead of receipt time beyond the configured tolerance.'
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

alter table public.observation_stream_quality_policy_versions enable row level security;
alter table public.observation_stream_sequence_states enable row level security;
alter table public.observation_transport_quality_receipts enable row level security;

create policy members_read_observation_stream_quality_policy_versions
on public.observation_stream_quality_policy_versions
for select to authenticated
using (public.is_farm_member(farm_id));

create policy members_read_observation_stream_sequence_states
on public.observation_stream_sequence_states
for select to authenticated
using (public.is_farm_member(farm_id));

create policy members_read_observation_transport_quality_receipts
on public.observation_transport_quality_receipts
for select to authenticated
using (public.is_farm_member(farm_id));

grant select on table
  public.observation_stream_quality_policy_versions,
  public.observation_stream_sequence_states,
  public.observation_transport_quality_receipts
to authenticated;

revoke all on table
  public.observation_stream_quality_policy_versions,
  public.observation_stream_sequence_states,
  public.observation_transport_quality_receipts
from anon;

revoke insert, update, delete, truncate, trigger, references on table
  public.observation_stream_quality_policy_versions,
  public.observation_stream_sequence_states,
  public.observation_transport_quality_receipts
from authenticated;

revoke execute on function public.record_initial_observation_stream_quality_policy()
from public, anon, authenticated, service_role;

revoke execute on function public.update_observation_stream_quality_policy(
  uuid, uuid, integer, text, integer, text, text
) from public, anon;

grant execute on function public.update_observation_stream_quality_policy(
  uuid, uuid, integer, text, integer, text, text
) to authenticated;

comment on table public.observation_stream_quality_policy_versions is
  'Immutable manager-attributed versions of stream sequence and clock drift policy.';

comment on table public.observation_stream_sequence_states is
  'Current monotonic source sequence high watermark serialized per observation stream.';

comment on table public.observation_transport_quality_receipts is
  'Typed sequence continuity and future clock drift evidence for each observation.';
