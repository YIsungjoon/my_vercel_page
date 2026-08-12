begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(74);

select extensions.has_table(
  'public', 'collection_agent_status_transitions', 'agent status history exists'
);
select extensions.has_table(
  'public', 'collection_agent_source_grant_events', 'source grant history exists'
);
select extensions.has_table(
  'public', 'collection_agent_credentials', 'credential generations exist'
);
select extensions.has_table(
  'public', 'collection_agent_credential_events', 'credential event history exists'
);
select extensions.has_column(
  'public', 'collection_agents', 'version', 'collection agents use optimistic versions'
);
select extensions.has_column(
  'public', 'collection_agent_sources', 'status', 'source grants have lifecycle status'
);
select extensions.has_fk(
  'public', 'collection_agent_credentials', 'credential generations stay in one farm and agent'
);

select extensions.is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'collection_agent_status_transitions',
        'collection_agent_source_grant_events',
        'collection_agent_credentials',
        'collection_agent_credential_events'
      )
      and data_type in ('json', 'jsonb')
  ),
  0,
  'phase 2E persists no JSON or JSONB columns'
);

select extensions.is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'collection_agent_credentials'
      and column_name in ('secret', 'secret_value', 'credential_value')
  ),
  0,
  'credential generations never persist secret values'
);

select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.transition_collection_agent_status(uuid,uuid,integer,text,text,text)',
    'EXECUTE'
  ),
  'authenticated managers can invoke agent status transitions'
);
select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.set_collection_agent_sources(uuid,uuid,integer,uuid[],text,text)',
    'EXECUTE'
  ),
  'authenticated managers can replace source grants'
);
select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.rotate_collection_agent_credential(uuid,uuid,integer,uuid,text,text,timestamptz,text,text)',
    'EXECUTE'
  ),
  'authenticated managers can rotate credential references'
);
select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.revoke_collection_agent_credential(uuid,uuid,uuid,integer,text,text)',
    'EXECUTE'
  ),
  'authenticated managers can revoke credential generations'
);
select extensions.ok(
  not has_function_privilege(
    'anon',
    'public.transition_collection_agent_status(uuid,uuid,integer,text,text,text)',
    'EXECUTE'
  ),
  'anonymous clients cannot transition collection agents'
);
select extensions.ok(
  not has_function_privilege(
    'authenticated',
    'public.collection_agent_management_response(uuid)',
    'EXECUTE'
  ),
  'authenticated clients cannot bypass management RPC authorization'
);

insert into auth.users (id, email)
values
  ('1a000000-0000-4000-8000-000000000001', 'phase2e-owner@example.test'),
  ('1a000000-0000-4000-8000-000000000002', 'phase2e-worker@example.test');

insert into public.farms (
  id, slug, name, region, country_code, latitude, longitude, timezone, created_by
)
values (
  '2a000000-0000-4000-8000-000000000001',
  'phase2e-farm',
  'Phase 2E Farm',
  'Test Region',
  'KR',
  35.8,
  126.8,
  'Asia/Seoul',
  '1a000000-0000-4000-8000-000000000001'
);

insert into public.farm_memberships (farm_id, user_id, role)
values
  (
    '2a000000-0000-4000-8000-000000000001',
    '1a000000-0000-4000-8000-000000000001',
    'owner'
  ),
  (
    '2a000000-0000-4000-8000-000000000001',
    '1a000000-0000-4000-8000-000000000002',
    'worker'
  );

create temporary table phase2e_refs (
  source_a_id uuid,
  source_b_id uuid,
  stream_b_id uuid,
  agent_id uuid,
  batch_id uuid,
  creation_response jsonb
);
insert into phase2e_refs default values;
grant select, update on phase2e_refs to authenticated, service_role;

set local role authenticated;
set local request.jwt.claim.sub = '1a000000-0000-4000-8000-000000000001';
set local request.jwt.claim.role = 'authenticated';

select extensions.lives_ok(
  $$
    select public.create_observation_source(
      '2a000000-0000-4000-8000-000000000001',
      'PHASE2E-SOURCE-A',
      'Phase 2E source A',
      'WEATHER_API',
      'phase2e-provider-a'
    )
  $$,
  'owner creates source A'
);

select extensions.lives_ok(
  $$
    select public.create_observation_source(
      '2a000000-0000-4000-8000-000000000001',
      'PHASE2E-SOURCE-B',
      'Phase 2E source B',
      'WEATHER_API',
      'phase2e-provider-b'
    )
  $$,
  'owner creates source B'
);

update phase2e_refs
set source_a_id = (
      select id from public.observation_sources where source_code = 'PHASE2E-SOURCE-A'
    ),
    source_b_id = (
      select id from public.observation_sources where source_code = 'PHASE2E-SOURCE-B'
    );

select extensions.lives_ok(
  $$
    select public.create_observation_stream(
      '2a000000-0000-4000-8000-000000000001',
      (select source_a_id from phase2e_refs),
      'weather.temperature_c',
      'PHASE2E-TEMP-A',
      'Phase 2E temperature A'
    )
  $$,
  'owner creates stream A'
);

select extensions.lives_ok(
  $$
    select public.create_observation_stream(
      '2a000000-0000-4000-8000-000000000001',
      (select source_b_id from phase2e_refs),
      'weather.humidity_pct',
      'PHASE2E-HUMIDITY-B',
      'Phase 2E humidity B'
    )
  $$,
  'owner creates stream B'
);

update phase2e_refs
set stream_b_id = (
  select id from public.observation_streams where stream_code = 'PHASE2E-HUMIDITY-B'
);

select extensions.lives_ok(
  $$
    update phase2e_refs
    set creation_response = public.create_collection_agent(
      '2a000000-0000-4000-8000-000000000001',
      'PHASE2E-COLLECTOR',
      'Phase 2E collector',
      'WEATHER_COLLECTOR',
      array[source_a_id]
    )
  $$,
  'owner creates the lifecycle-managed collection agent'
);

update phase2e_refs
set agent_id = (
  select id from public.collection_agents where agent_code = 'PHASE2E-COLLECTOR'
);

select extensions.is(
  jsonb_array_length((select creation_response -> 'authorized_source_ids' from phase2e_refs)),
  1,
  'agent creation preserves the Phase 2C authorized source response'
);

select extensions.ok(
  (
    select version = 1 and status = 'ACTIVE'
    from public.collection_agents
    where id = (select agent_id from phase2e_refs)
  ),
  'new collection agent starts active at version one'
);

select extensions.is(
  (
    select count(*)::integer
    from public.collection_agent_status_transitions
    where agent_id = (select agent_id from phase2e_refs)
      and from_status is null
      and to_status = 'ACTIVE'
  ),
  1,
  'agent registration creates the initial status receipt'
);

select extensions.is(
  (
    select count(*)::integer
    from public.collection_agent_source_grant_events
    where agent_id = (select agent_id from phase2e_refs)
      and event_type = 'GRANTED'
  ),
  1,
  'agent registration creates the initial source grant receipt'
);

set local request.jwt.claim.sub = '1a000000-0000-4000-8000-000000000002';

select extensions.throws_ok(
  $$
    select public.transition_collection_agent_status(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      1,
      'PAUSED',
      'WORKER_ATTEMPT',
      null
    )
  $$,
  'P0001',
  null,
  'farm worker cannot transition a collection agent'
);

set local request.jwt.claim.sub = '1a000000-0000-4000-8000-000000000001';

select extensions.lives_ok(
  $$
    select public.rotate_collection_agent_credential(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      1,
      null,
      'vault://collection-agents/phase2e/v1',
      repeat('a', 64),
      now() + interval '90 days',
      'INITIAL_CREDENTIAL',
      'Initial Vault reference'
    )
  $$,
  'owner registers the first credential reference'
);

select extensions.is(
  (select version from public.collection_agents where id = (select agent_id from phase2e_refs)),
  2,
  'credential registration increments the aggregate version'
);

select extensions.ok(
  (
    select status = 'ACTIVE'
      and credential_version = 1
      and secret_reference = 'vault://collection-agents/phase2e/v1'
    from public.collection_agent_credentials
    where agent_id = (select agent_id from phase2e_refs)
  ),
  'first credential stores only active Vault metadata'
);

select extensions.ok(
  (
    select secret_fingerprint_sha256 = repeat('a', 64)
      and secret_reference like 'vault://%'
    from public.collection_agent_credentials
    where agent_id = (select agent_id from phase2e_refs)
  ),
  'credential record contains a reference and fingerprint rather than a secret'
);

select extensions.throws_ok(
  $$
    select public.rotate_collection_agent_credential(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      2,
      (
        select id from public.collection_agent_credentials
        where agent_id = (select agent_id from phase2e_refs) and status = 'ACTIVE'
      ),
      'vault://collection-agents/phase2e/duplicate',
      repeat('a', 64),
      now() + interval '90 days',
      'ROTATION',
      null
    )
  $$,
  'P0001',
  null,
  'credential fingerprint reuse is rejected'
);

select extensions.lives_ok(
  $$
    select public.rotate_collection_agent_credential(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      2,
      (
        select id from public.collection_agent_credentials
        where agent_id = (select agent_id from phase2e_refs) and status = 'ACTIVE'
      ),
      'vault://collection-agents/phase2e/v2',
      repeat('b', 64),
      now() + interval '120 days',
      'SCHEDULED_ROTATION',
      'Quarterly rotation'
    )
  $$,
  'owner rotates to the second credential generation'
);

select extensions.is(
  (select version from public.collection_agents where id = (select agent_id from phase2e_refs)),
  3,
  'credential rotation increments the aggregate version'
);

select extensions.ok(
  (
    select count(*) = 2
      and count(*) filter (where status = 'ACTIVE') = 1
      and count(*) filter (where status = 'RETIRED') = 1
    from public.collection_agent_credentials
    where agent_id = (select agent_id from phase2e_refs)
  ),
  'rotation leaves one active and one retired generation'
);

select extensions.ok(
  (
    select rotated_from_credential_id = (
      select id
      from public.collection_agent_credentials
      where agent_id = (select agent_id from phase2e_refs)
        and credential_version = 1
    )
    from public.collection_agent_credentials
    where agent_id = (select agent_id from phase2e_refs)
      and credential_version = 2
  ),
  'second credential links to the previous generation'
);

select extensions.is(
  (
    select count(*)::integer
    from public.collection_agent_credential_events
    where agent_id = (select agent_id from phase2e_refs)
  ),
  3,
  'registration and rotation create three credential receipts'
);

select extensions.lives_ok(
  $$
    select public.set_collection_agent_sources(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      3,
      array[(select source_b_id from phase2e_refs)],
      'SOURCE_SCOPE_CHANGE',
      'Move collection to source B'
    )
  $$,
  'owner atomically replaces the source grant set'
);

select extensions.is(
  (select version from public.collection_agents where id = (select agent_id from phase2e_refs)),
  4,
  'source grant replacement increments the aggregate version'
);

select extensions.ok(
  (
    select count(*) filter (where status = 'ACTIVE') = 1
      and count(*) filter (where status = 'REVOKED') = 1
    from public.collection_agent_sources
    where agent_id = (select agent_id from phase2e_refs)
  ),
  'source A is revoked while source B is active'
);

select extensions.is(
  (
    select count(*)::integer
    from public.collection_agent_source_grant_events
    where agent_id = (select agent_id from phase2e_refs)
  ),
  3,
  'source scope replacement preserves grant and revocation receipts'
);

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.throws_ok(
  $$
    select public.get_collection_agent_configuration(
      'phase2e-farm', 'PHASE2E-COLLECTOR', 'PHASE2E-SOURCE-A'
    )
  $$,
  'P0001',
  null,
  'revoked source cannot resolve collector configuration'
);

select extensions.ok(
  (
    public.get_collection_agent_configuration(
      'phase2e-farm', 'PHASE2E-COLLECTOR', 'PHASE2E-SOURCE-B'
    ) -> 'credential' ->> 'credential_version'
  )::integer = 2
  and jsonb_array_length(
    public.get_collection_agent_configuration(
      'phase2e-farm', 'PHASE2E-COLLECTOR', 'PHASE2E-SOURCE-B'
    ) -> 'streams'
  ) = 1,
  'active source configuration includes the current credential metadata and stream'
);

select extensions.lives_ok(
  $$
    update phase2e_refs
    set batch_id = (
      public.open_observation_ingest_batch(
        '2a000000-0000-4000-8000-000000000001',
        agent_id,
        source_b_id,
        'phase2e:batch:001',
        1
      ) ->> 'id'
    )::uuid
  $$,
  'service role opens a batch for the active source grant'
);

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '1a000000-0000-4000-8000-000000000001';

select extensions.lives_ok(
  $$
    select public.transition_collection_agent_status(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      4,
      'PAUSED',
      'MAINTENANCE',
      'Scheduled gateway maintenance'
    )
  $$,
  'owner pauses the collection agent'
);

select extensions.ok(
  (
    select status = 'PAUSED' and version = 5
    from public.collection_agents
    where id = (select agent_id from phase2e_refs)
  )
  and (
    select count(*) = 2
    from public.collection_agent_status_transitions
    where agent_id = (select agent_id from phase2e_refs)
  ),
  'pause is recorded at aggregate version five'
);

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.throws_ok(
  $$
    select public.get_collection_agent_configuration(
      'phase2e-farm', 'PHASE2E-COLLECTOR', 'PHASE2E-SOURCE-B'
    )
  $$,
  'P0001',
  null,
  'paused agent cannot resolve collector configuration'
);

select extensions.throws_ok(
  $$
    select public.record_agent_stream_observation(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      (select batch_id from phase2e_refs),
      (select stream_b_id from phase2e_refs),
      now() - interval '1 minute',
      'phase2e:paused:observation',
      70,
      null,
      null,
      now(),
      'VALID',
      'phase2e-paused'
    )
  $$,
  'P0001',
  null,
  'paused agent cannot record into an already-open batch'
);

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '1a000000-0000-4000-8000-000000000001';

select extensions.lives_ok(
  $$
    select public.transition_collection_agent_status(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      5,
      'ACTIVE',
      'MAINTENANCE_COMPLETE',
      'Gateway checks passed'
    )
  $$,
  'owner resumes the paused collection agent'
);

select extensions.ok(
  (
    select status = 'ACTIVE' and version = 6
    from public.collection_agents
    where id = (select agent_id from phase2e_refs)
  ),
  'resumed agent becomes active at version six'
);

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.lives_ok(
  $$
    select public.record_agent_stream_observation(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      (select batch_id from phase2e_refs),
      (select stream_b_id from phase2e_refs),
      now() - interval '1 minute',
      'phase2e:active:observation',
      70,
      null,
      null,
      now(),
      'VALID',
      'phase2e-active'
    )
  $$,
  'resumed agent records into the existing batch'
);

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '1a000000-0000-4000-8000-000000000001';

select extensions.is(
  (
    select accepted_count
    from public.observation_ingest_batches
    where id = (select batch_id from phase2e_refs)
  ),
  1,
  'successful resumed observation increments the batch receipt'
);

select extensions.lives_ok(
  $$
    select public.revoke_collection_agent_credential(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      (
        select id from public.collection_agent_credentials
        where agent_id = (select agent_id from phase2e_refs) and status = 'ACTIVE'
      ),
      6,
      'CREDENTIAL_EXPOSURE',
      'Credential was replaced immediately'
    )
  $$,
  'owner revokes the active credential generation'
);

select extensions.ok(
  (
    select version = 7
    from public.collection_agents
    where id = (select agent_id from phase2e_refs)
  )
  and not exists (
    select 1
    from public.collection_agent_credentials
    where agent_id = (select agent_id from phase2e_refs) and status = 'ACTIVE'
  ),
  'credential revocation increments the agent version and removes the active generation'
);

select extensions.lives_ok(
  $$
    select public.rotate_collection_agent_credential(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      7,
      null,
      'vault://collection-agents/phase2e/v3',
      repeat('c', 64),
      now() + interval '120 days',
      'INCIDENT_RECOVERY',
      'Post-incident credential'
    )
  $$,
  'owner registers a replacement after revocation'
);

select extensions.ok(
  (
    select version = 8
    from public.collection_agents
    where id = (select agent_id from phase2e_refs)
  )
  and (
    select credential_version = 3 and status = 'ACTIVE'
    from public.collection_agent_credentials
    where agent_id = (select agent_id from phase2e_refs)
      and secret_fingerprint_sha256 = repeat('c', 64)
  ),
  'replacement credential becomes generation three at agent version eight'
);

select extensions.ok(
  (
    select rotated_from_credential_id = (
      select id
      from public.collection_agent_credentials
      where agent_id = (select agent_id from phase2e_refs)
        and credential_version = 2
    )
    from public.collection_agent_credentials
    where agent_id = (select agent_id from phase2e_refs)
      and credential_version = 3
  ),
  'post-revocation replacement retains the credential chain'
);

select extensions.lives_ok(
  $$
    select public.set_collection_agent_sources(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      8,
      array[
        (select source_a_id from phase2e_refs),
        (select source_b_id from phase2e_refs)
      ],
      'SOURCE_SCOPE_EXPANSION',
      'Restore source A after review'
    )
  $$,
  'owner regrants source A without deleting its history'
);

select extensions.ok(
  (
    select version = 9
    from public.collection_agents
    where id = (select agent_id from phase2e_refs)
  )
  and (
    select count(*) = 2
    from public.collection_agent_sources
    where agent_id = (select agent_id from phase2e_refs)
      and status = 'ACTIVE'
  ),
  'source expansion advances the agent and leaves two active grants'
);

select extensions.is(
  (
    select version
    from public.collection_agent_sources
    where agent_id = (select agent_id from phase2e_refs)
      and source_id = (select source_a_id from phase2e_refs)
  ),
  3,
  'regranted source keeps a monotonic grant version'
);

select extensions.throws_ok(
  $$
    select public.transition_collection_agent_status(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      8,
      'PAUSED',
      'STALE_REQUEST',
      null
    )
  $$,
  '40001',
  null,
  'stale collection agent version is rejected'
);

select extensions.lives_ok(
  $$
    select public.transition_collection_agent_status(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      9,
      'REVOKED',
      'DEVICE_DECOMMISSIONED',
      'Gateway removed from the farm'
    )
  $$,
  'owner terminally revokes the collection agent'
);

select extensions.ok(
  (
    select status = 'REVOKED' and version = 10
    from public.collection_agents
    where id = (select agent_id from phase2e_refs)
  ),
  'terminal revocation is stored at version ten'
);

select extensions.is(
  (
    select count(*)::integer
    from public.collection_agent_sources
    where agent_id = (select agent_id from phase2e_refs)
      and status = 'REVOKED'
  ),
  2,
  'terminal agent revocation removes every active source grant'
);

select extensions.is(
  (
    select count(*)::integer
    from public.collection_agent_credentials
    where agent_id = (select agent_id from phase2e_refs)
      and status = 'REVOKED'
  ),
  3,
  'terminal agent revocation marks every credential generation revoked'
);

select extensions.is(
  (
    select count(*)::integer
    from public.collection_agent_status_transitions
    where agent_id = (select agent_id from phase2e_refs)
  ),
  4,
  'status ledger contains registration, pause, resume, and revocation'
);

select extensions.is(
  (
    select count(*)::integer
    from public.collection_agent_source_grant_events
    where agent_id = (select agent_id from phase2e_refs)
  ),
  6,
  'source grant ledger preserves all six lifecycle events'
);

select extensions.is(
  (
    select count(*)::integer
    from public.collection_agent_credential_events
    where agent_id = (select agent_id from phase2e_refs)
  ),
  7,
  'credential ledger preserves registration, rotation, retirement, and revocations'
);

set local role service_role;
set local request.jwt.claim.role = 'service_role';

select extensions.throws_ok(
  $$
    select public.get_collection_agent_configuration(
      'phase2e-farm', 'PHASE2E-COLLECTOR', 'PHASE2E-SOURCE-B'
    )
  $$,
  'P0001',
  null,
  'revoked agent cannot resolve collector configuration'
);

select extensions.throws_ok(
  $$
    select public.open_observation_ingest_batch(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      (select source_b_id from phase2e_refs),
      'phase2e:batch:revoked',
      1
    )
  $$,
  'P0001',
  null,
  'revoked agent cannot open another ingest batch'
);

set local role authenticated;
set local request.jwt.claim.role = 'authenticated';
set local request.jwt.claim.sub = '1a000000-0000-4000-8000-000000000001';

select extensions.throws_ok(
  $$
    select public.transition_collection_agent_status(
      '2a000000-0000-4000-8000-000000000001',
      (select agent_id from phase2e_refs),
      10,
      'ACTIVE',
      'INVALID_REACTIVATION',
      null
    )
  $$,
  'P0001',
  null,
  'revoked collection agent cannot be reactivated'
);

select extensions.is(
  (
    select count(*)::integer
    from public.collection_agent_credentials
    where agent_id = (select agent_id from phase2e_refs)
  ),
  3,
  'farm owner can read every credential generation'
);

set local request.jwt.claim.sub = '1a000000-0000-4000-8000-000000000002';

select extensions.is(
  (
    select count(*)::integer
    from public.collection_agent_credentials
    where agent_id = (select agent_id from phase2e_refs)
  ),
  0,
  'farm worker cannot read credential metadata'
);

select extensions.is(
  (
    select count(*)::integer
    from public.collection_agent_status_transitions
    where agent_id = (select agent_id from phase2e_refs)
  ),
  0,
  'farm worker cannot read collection agent lifecycle history'
);

select extensions.throws_ok(
  $$ insert into public.collection_agent_credentials default values $$,
  '42501',
  null,
  'authenticated clients cannot directly write credential generations'
);

reset role;

select extensions.is(
  (
    select count(*)::integer
    from public.collection_agent_status_transitions
    where agent_id = (select agent_id from phase2e_refs)
      and changed_by = '1a000000-0000-4000-8000-000000000001'
  ),
  4,
  'every status transition preserves the manager actor'
);

select * from extensions.finish();

rollback;
