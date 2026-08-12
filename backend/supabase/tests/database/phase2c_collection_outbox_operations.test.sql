begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(59);

select extensions.has_table('public', 'collection_agents', 'collection agent principals exist');
select extensions.has_table('public', 'collection_agent_sources', 'agent source grants exist');
select extensions.has_table('public', 'observation_ingest_batches', 'ingest batch ledger exists');
select extensions.has_table('public', 'domain_events', 'domain event ledger exists');
select extensions.has_table('public', 'outbox_messages', 'transactional outbox exists');
select extensions.has_table('public', 'outbox_delivery_attempts', 'delivery attempt ledger exists');
select extensions.has_table('public', 'outbox_dead_letters', 'dead-letter receipts exist');

select extensions.is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'collection_agents',
        'collection_agent_sources',
        'observation_ingest_batches',
        'domain_events',
        'outbox_messages',
        'outbox_delivery_attempts',
        'outbox_dead_letters'
      )
      and data_type in ('json', 'jsonb')
  ),
  0,
  'phase 2C persists no JSON or JSONB columns'
);

select extensions.has_column('public', 'stream_observations', 'source_id', 'observation snapshots source');
select extensions.has_column(
  'public', 'stream_observations', 'collector_agent_id', 'observation can name a machine actor'
);
select extensions.has_column(
  'public', 'stream_observations', 'ingest_batch_id', 'machine observation belongs to a batch'
);
select extensions.has_fk('public', 'stream_observations', 'observation ingest context has foreign keys');

select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.create_collection_agent(uuid,text,text,text,uuid[])',
    'EXECUTE'
  ),
  'authenticated managers can invoke collection agent creation'
);
select extensions.ok(
  has_function_privilege(
    'service_role',
    'public.get_collection_agent_configuration(text,text,text)',
    'EXECUTE'
  ),
  'service role can resolve collector configuration'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.get_collection_agent_configuration(text,text,text)',
    'EXECUTE'
  ),
  'authenticated clients cannot invoke service collector configuration'
);

insert into auth.users (id, email)
values
  ('16000000-0000-4000-8000-000000000001', 'phase2c-owner@example.test'),
  ('16000000-0000-4000-8000-000000000002', 'phase2c-worker@example.test');

insert into public.farms (
  id, slug, name, region, country_code, latitude, longitude, timezone, created_by
)
values (
  '26000000-0000-4000-8000-000000000001',
  'phase2c-farm',
  'Phase 2C Farm',
  'Test Region',
  'KR',
  35.8,
  126.8,
  'Asia/Seoul',
  '16000000-0000-4000-8000-000000000001'
);

insert into public.farm_memberships (farm_id, user_id, role)
values
  (
    '26000000-0000-4000-8000-000000000001',
    '16000000-0000-4000-8000-000000000001',
    'owner'
  ),
  (
    '26000000-0000-4000-8000-000000000001',
    '16000000-0000-4000-8000-000000000002',
    'worker'
  );

create temporary table phase2c_refs (
  source_id uuid,
  stream_id uuid,
  agent_id uuid,
  batch_id uuid,
  machine_message_id uuid,
  user_message_id uuid
);
grant select, insert, update on phase2c_refs to authenticated, service_role;

set local role authenticated;
set local request.jwt.claim.sub = '16000000-0000-4000-8000-000000000001';
set local request.jwt.claim.role = 'authenticated';

select extensions.lives_ok(
  $$
    select public.create_observation_source(
      '26000000-0000-4000-8000-000000000001',
      'OPEN-METEO',
      'Open-Meteo weather source',
      'WEATHER_API',
      'open-meteo'
    )
  $$,
  'owner creates the weather source'
);

select extensions.lives_ok(
  $$
    select public.create_observation_stream(
      '26000000-0000-4000-8000-000000000001',
      (select id from public.observation_sources where source_code = 'OPEN-METEO'),
      'weather.temperature_c',
      'OPEN-METEO-TEMP',
      'Open-Meteo temperature',
      null,
      15,
      false
    )
  $$,
  'owner creates a weather observation stream'
);

select extensions.lives_ok(
  $$
    select public.create_collection_agent(
      '26000000-0000-4000-8000-000000000001',
      'OPEN-METEO-COLLECTOR',
      'Open-Meteo collector',
      'WEATHER_COLLECTOR',
      array[(select id from public.observation_sources where source_code = 'OPEN-METEO')]
    )
  $$,
  'owner creates a source-authorized machine principal'
);

select extensions.is(
  (
    select count(*)::integer
    from public.collection_agent_sources
    where farm_id = '26000000-0000-4000-8000-000000000001'
  ),
  1,
  'agent has exactly one normalized source grant'
);

insert into phase2c_refs (source_id, stream_id, agent_id)
select
  source.id,
  stream.id,
  agent.id
from public.observation_sources as source
join public.observation_streams as stream on stream.source_id = source.id
join public.collection_agents as agent on agent.farm_id = source.farm_id
where source.source_code = 'OPEN-METEO'
  and stream.stream_code = 'OPEN-METEO-TEMP'
  and agent.agent_code = 'OPEN-METEO-COLLECTOR';

set local request.jwt.claim.sub = '16000000-0000-4000-8000-000000000002';

select extensions.throws_ok(
  $$
    select public.create_collection_agent(
      '26000000-0000-4000-8000-000000000001',
      'WORKER-COLLECTOR',
      'Worker collector',
      'WEATHER_COLLECTOR',
      array[(select id from public.observation_sources where source_code = 'OPEN-METEO')]
    )
  $$,
  'P0001',
  null,
  'worker cannot create a machine principal'
);

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.lives_ok(
  $$
    select public.get_collection_agent_configuration(
      'phase2c-farm', 'OPEN-METEO-COLLECTOR', 'OPEN-METEO'
    )
  $$,
  'service role resolves farm-scoped collector configuration'
);

select extensions.ok(
  (
    public.get_collection_agent_configuration(
      'phase2c-farm', 'OPEN-METEO-COLLECTOR', 'OPEN-METEO'
    ) -> 'agent' ->> 'agent_code'
  ) = 'OPEN-METEO-COLLECTOR'
  and jsonb_array_length(
    public.get_collection_agent_configuration(
      'phase2c-farm', 'OPEN-METEO-COLLECTOR', 'OPEN-METEO'
    ) -> 'streams'
  ) = 1,
  'collector configuration contains the logical principal and active stream'
);

select extensions.lives_ok(
  $$
    update phase2c_refs
    set batch_id = (
      public.open_observation_ingest_batch(
        '26000000-0000-4000-8000-000000000001',
        agent_id,
        source_id,
        'open-meteo:phase2c-001',
        1
      ) ->> 'id'
    )::uuid
  $$,
  'service role opens an authorized ingest batch'
);

select extensions.lives_ok(
  $$
    select public.open_observation_ingest_batch(
      '26000000-0000-4000-8000-000000000001',
      (select agent_id from phase2c_refs),
      (select source_id from phase2c_refs),
      'open-meteo:phase2c-001',
      1
    )
  $$,
  'same external batch key returns the existing batch'
);

reset role;

select extensions.is(
  (
    select count(*)::integer
    from public.observation_ingest_batches
    where external_batch_key = 'open-meteo:phase2c-001'
  ),
  1,
  'batch idempotency key creates one ledger row'
);

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.lives_ok(
  $$
    select public.record_agent_stream_observation(
      target_farm_id := '26000000-0000-4000-8000-000000000001',
      target_agent_id := (select agent_id from phase2c_refs),
      target_ingest_batch_id := (select batch_id from phase2c_refs),
      target_stream_id := (select stream_id from phase2c_refs),
      observation_observed_at := date_trunc('second', now()),
      observation_idempotency_key := 'open-meteo:temperature:phase2c-001',
      observation_numeric_value := 27.5,
      observation_received_at := date_trunc('second', now()),
      source_sequence := 'phase2c-temperature-001'
    )
  $$,
  'service collector records a typed stream observation'
);

reset role;

select extensions.ok(
  (
    select recorded_by is null
      and collector_agent_id is not null
      and ingest_batch_id is not null
      and source_id is not null
    from public.stream_observations
    where idempotency_key = 'open-meteo:temperature:phase2c-001'
  ),
  'machine observation preserves exactly one collector actor and ingest context'
);

select extensions.is(
  (
    select accepted_count
    from public.observation_ingest_batches
    where external_batch_key = 'open-meteo:phase2c-001'
  ),
  1,
  'new machine observation increments the batch receipt'
);

select extensions.is(
  (
    select count(*)::integer
    from public.domain_events as event
    join public.stream_observations as observation on observation.id = event.observation_id
    where observation.idempotency_key = 'open-meteo:temperature:phase2c-001'
      and event.event_name = 'OBSERVATION_RECORDED'
      and event.observation_event_type = 'WEATHER_OBSERVATION'
  ),
  1,
  'observation transaction emits one typed domain event'
);

select extensions.is(
  (
    select count(*)::integer
    from public.outbox_messages as message
    join public.domain_events as event on event.id = message.event_id
    join public.stream_observations as observation on observation.id = event.observation_id
    where observation.idempotency_key = 'open-meteo:temperature:phase2c-001'
      and message.topic = 'observation.recorded.v1'
      and message.status = 'PENDING'
  ),
  1,
  'observation transaction emits one pending outbox message'
);

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.lives_ok(
  $$
    select public.record_agent_stream_observation(
      '26000000-0000-4000-8000-000000000001',
      (select agent_id from phase2c_refs),
      (select batch_id from phase2c_refs),
      (select stream_id from phase2c_refs),
      date_trunc('second', now()),
      'open-meteo:temperature:phase2c-001',
      27.5,
      null,
      null,
      date_trunc('second', now()),
      'VALID',
      'phase2c-temperature-001'
    )
  $$,
  'same machine observation request is idempotent'
);

reset role;

select extensions.is(
  (
    select count(*)::integer
    from public.stream_observations
    where idempotency_key = 'open-meteo:temperature:phase2c-001'
  ),
  1,
  'machine observation retry creates no duplicate observation'
);

select extensions.is(
  (
    select accepted_count
    from public.observation_ingest_batches
    where external_batch_key = 'open-meteo:phase2c-001'
  ),
  1,
  'machine observation retry does not increment accepted count'
);

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.lives_ok(
  $$
    select public.complete_observation_ingest_batch(
      '26000000-0000-4000-8000-000000000001',
      (select batch_id from phase2c_refs),
      'COMPLETED',
      1,
      0
    )
  $$,
  'collector completes a reconciled ingest batch'
);

reset role;

select extensions.ok(
  (
    select status = 'COMPLETED'
      and expected_count = 1
      and accepted_count = 1
      and rejected_count = 0
      and finished_at is not null
    from public.observation_ingest_batches
    where external_batch_key = 'open-meteo:phase2c-001'
  ),
  'completed batch preserves terminal count receipt'
);

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.throws_ok(
  $$
    select public.record_agent_stream_observation(
      '26000000-0000-4000-8000-000000000001',
      (select agent_id from phase2c_refs),
      (select batch_id from phase2c_refs),
      (select stream_id from phase2c_refs),
      now(),
      'open-meteo:temperature:phase2c-002',
      28
    )
  $$,
  'P0001',
  null,
  'terminal ingest batch rejects new observations'
);

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '16000000-0000-4000-8000-000000000001';

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      target_farm_id := '26000000-0000-4000-8000-000000000001',
      target_stream_id := (
        select id from public.observation_streams where stream_code = 'OPEN-METEO-TEMP'
      ),
      observation_observed_at := date_trunc('second', now()) - interval '1 minute',
      observation_idempotency_key := 'manual-weather:phase2c-001',
      observation_numeric_value := 26,
      observation_received_at := date_trunc('second', now()) - interval '1 minute'
    )
  $$,
  'existing user observation RPC remains compatible'
);

select extensions.ok(
  (
    select observation.recorded_by = '16000000-0000-4000-8000-000000000001'::uuid
      and observation.collector_agent_id is null
      and observation.ingest_batch_id is null
      and event.id is not null
    from public.stream_observations as observation
    join public.domain_events as event on event.observation_id = observation.id
    where observation.idempotency_key = 'manual-weather:phase2c-001'
  ),
  'user observation keeps the user actor and emits an event'
);

select extensions.is(
  (select count(*)::integer from public.collection_agents),
  1,
  'farm owner can read collection agents through RLS'
);

set local request.jwt.claim.sub = '16000000-0000-4000-8000-000000000002';

select extensions.is(
  (select count(*)::integer from public.collection_agents),
  0,
  'farm worker cannot read manager-only collection agents'
);

select extensions.throws_ok(
  $$
    insert into public.collection_agents (
      farm_id, agent_code, name, agent_kind, created_by
    ) values (
      '26000000-0000-4000-8000-000000000001',
      'DIRECT-INSERT',
      'Direct insert',
      'WEATHER_COLLECTOR',
      '16000000-0000-4000-8000-000000000002'
    )
  $$,
  '42501',
  null,
  'authenticated clients cannot directly write collection principals'
);

reset role;

update public.outbox_messages as message
set max_attempts = 1
from public.domain_events as event
join public.stream_observations as observation
  on observation.id = event.observation_id
where message.event_id = event.id
  and observation.idempotency_key = 'manual-weather:phase2c-001';

update public.outbox_messages as message
set available_at = now() - interval '1 minute'
from public.domain_events as event
join public.stream_observations as observation
  on observation.id = event.observation_id
where message.event_id = event.id
  and observation.idempotency_key = 'open-meteo:temperature:phase2c-001';

update phase2c_refs
set machine_message_id = (
      select message.id
      from public.outbox_messages as message
      join public.domain_events as event on event.id = message.event_id
      join public.stream_observations as observation on observation.id = event.observation_id
      where observation.idempotency_key = 'open-meteo:temperature:phase2c-001'
    ),
    user_message_id = (
      select message.id
      from public.outbox_messages as message
      join public.domain_events as event on event.id = message.event_id
      join public.stream_observations as observation on observation.id = event.observation_id
      where observation.idempotency_key = 'manual-weather:phase2c-001'
    );

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.lives_ok(
  $$select public.claim_outbox_messages('phase2c-dispatcher', 1, 300)$$,
  'dispatcher claims the oldest pending outbox message'
);

reset role;

select extensions.ok(
  (
    select message.status = 'CLAIMED'
      and message.attempt_count = 1
      and attempt.status = 'CLAIMED'
      and attempt.worker_id = 'phase2c-dispatcher'
    from public.outbox_messages as message
    join public.outbox_delivery_attempts as attempt on attempt.message_id = message.id
    join public.domain_events as event on event.id = message.event_id
    join public.stream_observations as observation on observation.id = event.observation_id
    where observation.idempotency_key = 'open-meteo:temperature:phase2c-001'
  ),
  'claim creates a matching relational delivery attempt'
);

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.lives_ok(
  $$
    select public.complete_outbox_delivery(
      '26000000-0000-4000-8000-000000000001',
      (select machine_message_id from phase2c_refs),
      'phase2c-dispatcher',
      1,
      true
    )
  $$,
  'dispatcher records successful publication'
);

reset role;

select extensions.ok(
  (
    select message.status = 'PUBLISHED'
      and message.published_at is not null
      and message.locked_by is null
      and attempt.status = 'PUBLISHED'
      and attempt.finished_at is not null
    from public.outbox_messages as message
    join public.outbox_delivery_attempts as attempt on attempt.message_id = message.id
    join public.domain_events as event on event.id = message.event_id
    join public.stream_observations as observation on observation.id = event.observation_id
    where observation.idempotency_key = 'open-meteo:temperature:phase2c-001'
  ),
  'successful receipt publishes the message and attempt'
);

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.lives_ok(
  $$
    select public.complete_outbox_delivery(
      '26000000-0000-4000-8000-000000000001',
      (select machine_message_id from phase2c_refs),
      'phase2c-dispatcher',
      1,
      true
    )
  $$,
  'same successful delivery receipt is idempotent'
);

select extensions.lives_ok(
  $$select public.claim_outbox_messages('phase2c-dispatcher', 1, 300)$$,
  'dispatcher claims the remaining user observation event'
);

select extensions.lives_ok(
  $$
    select public.complete_outbox_delivery(
      '26000000-0000-4000-8000-000000000001',
      (select user_message_id from phase2c_refs),
      'phase2c-dispatcher',
      1,
      false,
      'DOWNSTREAM_UNAVAILABLE',
      'Test downstream failure',
      0
    )
  $$,
  'final failed delivery creates a dead-letter receipt'
);

select extensions.lives_ok(
  $$
    select public.complete_outbox_delivery(
      '26000000-0000-4000-8000-000000000001',
      (select user_message_id from phase2c_refs),
      'phase2c-dispatcher',
      1,
      false,
      'DOWNSTREAM_UNAVAILABLE',
      'Test downstream failure',
      0
    )
  $$,
  'same failed delivery receipt is idempotent'
);

reset role;

select extensions.ok(
  (
    select status = 'DEAD_LETTER'
      and last_error_code = 'DOWNSTREAM_UNAVAILABLE'
      and locked_by is null
    from public.outbox_messages as message
    join public.domain_events as event on event.id = message.event_id
    join public.stream_observations as observation on observation.id = event.observation_id
    where observation.idempotency_key = 'manual-weather:phase2c-001'
  ),
  'exhausted message moves to dead-letter status'
);

select extensions.is(
  (
    select count(*)::integer
    from public.outbox_dead_letters as dead_letter
    join public.outbox_messages as message on message.id = dead_letter.message_id
    join public.domain_events as event on event.id = message.event_id
    join public.stream_observations as observation on observation.id = event.observation_id
    where observation.idempotency_key = 'manual-weather:phase2c-001'
      and dead_letter.final_attempt_no = 1
      and dead_letter.reason_code = 'DOWNSTREAM_UNAVAILABLE'
  ),
  1,
  'dead-letter table preserves the terminal failure reason'
);

select extensions.ok(
  (
    select attempt.status = 'FAILED'
      and attempt.error_code = 'DOWNSTREAM_UNAVAILABLE'
      and attempt.finished_at is not null
    from public.outbox_delivery_attempts as attempt
    join public.outbox_messages as message on message.id = attempt.message_id
    join public.domain_events as event on event.id = message.event_id
    join public.stream_observations as observation on observation.id = event.observation_id
    where observation.idempotency_key = 'manual-weather:phase2c-001'
  ),
  'failed delivery attempt remains auditable'
);

select extensions.ok(
  not has_function_privilege(
    'anon',
    'public.claim_outbox_messages(text,integer,integer)',
    'EXECUTE'
  ),
  'anonymous clients cannot claim outbox messages'
);

select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.record_stream_observation(uuid,uuid,timestamptz,text,numeric,text,boolean,timestamptz,text,text)',
    'EXECUTE'
  ),
  'authenticated user observation RPC remains executable'
);

select extensions.is(
  (
    select count(*)::integer
    from public.domain_events
    where farm_id = '26000000-0000-4000-8000-000000000001'
  ),
  2,
  'two observations create exactly two immutable domain events'
);

select extensions.is(
  (
    select count(*)::integer
    from public.outbox_messages
    where farm_id = '26000000-0000-4000-8000-000000000001'
  ),
  2,
  'two events create exactly two outbox messages'
);

select extensions.ok(
  (
    select last_seen_at is not null
    from public.collection_agents
    where agent_code = 'OPEN-METEO-COLLECTOR'
  ),
  'machine activity updates collector last-seen time'
);

select extensions.is(
  (
    select count(*)::integer
    from public.outbox_delivery_attempts
    where farm_id = '26000000-0000-4000-8000-000000000001'
  ),
  2,
  'each claimed message has one delivery attempt'
);

select extensions.is(
  (
    select count(*)::integer
    from public.outbox_dead_letters
    where farm_id = '26000000-0000-4000-8000-000000000001'
  ),
  1,
  'only the exhausted message has a dead-letter receipt'
);

select * from extensions.finish();

rollback;
