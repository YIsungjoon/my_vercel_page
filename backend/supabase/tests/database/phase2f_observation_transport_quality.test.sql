begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(61);

select extensions.has_table(
  'public', 'observation_stream_quality_policy_versions', 'quality policy history exists'
);
select extensions.has_table(
  'public', 'observation_stream_sequence_states', 'sequence high-watermark state exists'
);
select extensions.has_table(
  'public', 'observation_transport_quality_receipts', 'transport quality receipts exist'
);
select extensions.has_column(
  'public', 'observation_streams', 'sequence_policy', 'streams carry a sequence policy'
);
select extensions.has_column(
  'public', 'observation_streams', 'clock_drift_tolerance_seconds',
  'streams carry a future clock drift tolerance'
);
select extensions.has_column(
  'public', 'observation_streams', 'quality_policy_version',
  'stream quality policy uses optimistic versions'
);
select extensions.has_fk(
  'public', 'observation_transport_quality_receipts',
  'transport receipt belongs to its observation stream'
);

select extensions.is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'observation_stream_quality_policy_versions',
        'observation_stream_sequence_states',
        'observation_transport_quality_receipts'
      )
      and data_type in ('json', 'jsonb')
  ),
  0,
  'phase 2F persists no JSON or JSONB columns'
);

select extensions.ok(
  has_function_privilege(
    'authenticated',
    'public.update_observation_stream_quality_policy(uuid,uuid,integer,text,integer,text,text)',
    'EXECUTE'
  ),
  'authenticated managers can invoke quality policy updates'
);
select extensions.ok(
  not has_function_privilege(
    'anon',
    'public.update_observation_stream_quality_policy(uuid,uuid,integer,text,integer,text,text)',
    'EXECUTE'
  ),
  'anonymous clients cannot update stream quality policy'
);

insert into auth.users (id, email)
values
  ('1b000000-0000-4000-8000-000000000001', 'phase2f-owner@example.test'),
  ('1b000000-0000-4000-8000-000000000002', 'phase2f-worker@example.test'),
  ('1b000000-0000-4000-8000-000000000003', 'phase2f-outsider@example.test');

insert into public.farms (
  id, slug, name, region, country_code, latitude, longitude, timezone, created_by
)
values (
  '2b000000-0000-4000-8000-000000000001',
  'phase2f-farm',
  'Phase 2F Farm',
  'Test Region',
  'KR',
  35.8,
  126.8,
  'Asia/Seoul',
  '1b000000-0000-4000-8000-000000000001'
);

insert into public.farm_memberships (farm_id, user_id, role)
values
  (
    '2b000000-0000-4000-8000-000000000001',
    '1b000000-0000-4000-8000-000000000001',
    'owner'
  ),
  (
    '2b000000-0000-4000-8000-000000000001',
    '1b000000-0000-4000-8000-000000000002',
    'worker'
  );

create temporary table phase2f_refs (
  source_id uuid,
  stream_id uuid,
  received_at timestamptz not null,
  first_response jsonb
);
insert into phase2f_refs (received_at) values (date_trunc('second', now()) - interval '1 minute');
grant select, update on phase2f_refs to authenticated;

set local role authenticated;
set local request.jwt.claim.sub = '1b000000-0000-4000-8000-000000000001';
set local request.jwt.claim.role = 'authenticated';

select extensions.lives_ok(
  $$
    select public.create_observation_source(
      '2b000000-0000-4000-8000-000000000001',
      'PHASE2F-GATEWAY',
      'Phase 2F gateway',
      'WEATHER_API',
      'phase2f-provider'
    )
  $$,
  'owner creates the sequence source'
);

update phase2f_refs
set source_id = (
  select id from public.observation_sources where source_code = 'PHASE2F-GATEWAY'
);

select extensions.lives_ok(
  $$
    select public.create_observation_stream(
      '2b000000-0000-4000-8000-000000000001',
      (select source_id from phase2f_refs),
      'weather.temperature_c',
      'PHASE2F-TEMPERATURE',
      'Phase 2F temperature'
    )
  $$,
  'owner creates the sequence stream'
);

update phase2f_refs
set stream_id = (
  select id from public.observation_streams where stream_code = 'PHASE2F-TEMPERATURE'
);

select extensions.ok(
  (
    select sequence_policy = 'NONE'
      and clock_drift_tolerance_seconds = 300
      and quality_policy_version = 1
    from public.observation_streams
    where id = (select stream_id from phase2f_refs)
  ),
  'new stream keeps the compatibility quality policy defaults'
);

select extensions.is(
  (
    select count(*)::integer
    from public.observation_stream_quality_policy_versions
    where stream_id = (select stream_id from phase2f_refs)
      and policy_version = 1
      and reason_code = 'INITIAL_POLICY'
  ),
  1,
  'new stream records its initial policy version'
);

set local request.jwt.claim.sub = '1b000000-0000-4000-8000-000000000002';

select extensions.throws_ok(
  $$
    select public.update_observation_stream_quality_policy(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      1,
      'MONOTONIC_INTEGER',
      30,
      'WORKER_ATTEMPT',
      null
    )
  $$,
  'P0001',
  null,
  'farm worker cannot update the stream quality policy'
);

set local request.jwt.claim.sub = '1b000000-0000-4000-8000-000000000001';

select extensions.lives_ok(
  $$
    select public.update_observation_stream_quality_policy(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      1,
      'MONOTONIC_INTEGER',
      30,
      'ENABLE_GATEWAY_SEQUENCE',
      'Gateway emits integer counters'
    )
  $$,
  'owner enables monotonic sequence tracking'
);

select extensions.ok(
  (
    select quality_policy_version = 2
      and sequence_policy = 'MONOTONIC_INTEGER'
      and clock_drift_tolerance_seconds = 30
    from public.observation_streams
    where id = (select stream_id from phase2f_refs)
  ),
  'quality policy update advances the stream policy version'
);

select extensions.throws_ok(
  $$
    select public.update_observation_stream_quality_policy(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      1,
      'NONE',
      300,
      'STALE_POLICY',
      null
    )
  $$,
  '40001',
  null,
  'stale quality policy version is rejected'
);

select extensions.throws_ok(
  $$
    select public.record_stream_observation(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      (select received_at from phase2f_refs),
      'phase2f:invalid-sequence',
      20,
      null,
      null,
      (select received_at from phase2f_refs),
      'VALID',
      'not-an-integer'
    )
  $$,
  'P0001',
  null,
  'tracked stream rejects non-integer source sequences'
);

select extensions.lives_ok(
  $$
    update phase2f_refs
    set first_response = public.record_stream_observation(
      '2b000000-0000-4000-8000-000000000001',
      stream_id,
      received_at,
      'phase2f:sequence:100',
      20,
      null,
      null,
      received_at,
      'VALID',
      '100'
    )
  $$,
  'first tracked observation is recorded'
);

select extensions.ok(
  (
    select first_response -> 'transport_quality_receipt' ->> 'sequence_status' = 'FIRST'
      and first_response -> 'observation' ->> 'quality_status' = 'VALID'
    from phase2f_refs
  ),
  'first observation response contains a valid FIRST receipt'
);

select extensions.ok(
  (
    select last_sequence_value = 100
      and receipt_count = 1
      and anomaly_count = 0
    from public.observation_stream_sequence_states
    where stream_id = (select stream_id from phase2f_refs)
  ),
  'first observation establishes the sequence high watermark'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      (select received_at from phase2f_refs),
      'phase2f:sequence:100',
      20,
      null,
      null,
      (select received_at from phase2f_refs),
      'VALID',
      '100'
    )
  $$,
  'same idempotency key returns the first observation'
);

select extensions.ok(
  (
    select receipt_count = 1 and last_sequence_value = 100
    from public.observation_stream_sequence_states
    where stream_id = (select stream_id from phase2f_refs)
  ),
  'idempotent retry does not advance sequence state'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      (select received_at from phase2f_refs) + interval '1 second',
      'phase2f:sequence:101',
      21,
      null,
      null,
      (select received_at from phase2f_refs) + interval '1 second',
      'VALID',
      '101'
    )
  $$,
  'contiguous observation is recorded'
);

select extensions.ok(
  (
    select receipt.sequence_status = 'CONTIGUOUS'
      and observation.quality_status = 'VALID'
    from public.observation_transport_quality_receipts as receipt
    join public.stream_observations as observation on observation.id = receipt.observation_id
    where observation.idempotency_key = 'phase2f:sequence:101'
  ),
  'contiguous sequence remains valid'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      (select received_at from phase2f_refs) + interval '2 seconds',
      'phase2f:sequence:104',
      22,
      null,
      null,
      (select received_at from phase2f_refs) + interval '2 seconds',
      'VALID',
      '104'
    )
  $$,
  'gap observation is preserved'
);

select extensions.ok(
  (
    select receipt.sequence_status = 'GAP'
      and receipt.previous_high_watermark = 101
      and receipt.missing_sequence_count = 2
      and receipt.sequence_state_advanced
      and observation.quality_status = 'SUSPECT'
    from public.observation_transport_quality_receipts as receipt
    join public.stream_observations as observation on observation.id = receipt.observation_id
    where observation.idempotency_key = 'phase2f:sequence:104'
  ),
  'gap receipt records the previous watermark and missing count'
);

select extensions.is(
  (
    select count(*)::integer
    from public.observation_quality_findings as finding
    join public.stream_observations as observation on observation.id = finding.observation_id
    where observation.idempotency_key = 'phase2f:sequence:104'
      and finding.finding_code = 'SOURCE_SEQUENCE_GAP'
  ),
  1,
  'gap creates a normalized quality finding'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      (select received_at from phase2f_refs) + interval '3 seconds',
      'phase2f:sequence:103-late-order',
      23,
      null,
      null,
      (select received_at from phase2f_refs) + interval '3 seconds',
      'VALID',
      '103'
    )
  $$,
  'out-of-order observation is preserved'
);

select extensions.ok(
  (
    select receipt.sequence_status = 'OUT_OF_ORDER'
      and not receipt.sequence_state_advanced
      and observation.quality_status = 'SUSPECT'
    from public.observation_transport_quality_receipts as receipt
    join public.stream_observations as observation on observation.id = receipt.observation_id
    where observation.idempotency_key = 'phase2f:sequence:103-late-order'
  ),
  'out-of-order receipt does not advance sequence state'
);

select extensions.is(
  (
    select last_sequence_value
    from public.observation_stream_sequence_states
    where stream_id = (select stream_id from phase2f_refs)
  ),
  104::bigint,
  'out-of-order observation leaves the high watermark unchanged'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      (select received_at from phase2f_refs) + interval '4 seconds',
      'phase2f:sequence:104-duplicate',
      24,
      null,
      null,
      (select received_at from phase2f_refs) + interval '4 seconds',
      'VALID',
      '104'
    )
  $$,
  'duplicate sequence with a distinct idempotency key is preserved'
);

select extensions.ok(
  (
    select receipt.sequence_status = 'DUPLICATE'
      and not receipt.sequence_state_advanced
      and observation.quality_status = 'SUSPECT'
    from public.observation_transport_quality_receipts as receipt
    join public.stream_observations as observation on observation.id = receipt.observation_id
    where observation.idempotency_key = 'phase2f:sequence:104-duplicate'
  ),
  'duplicate sequence creates a suspect non-advancing receipt'
);

select extensions.is(
  (
    select count(*)::integer
    from public.stream_observations
    where stream_id = (select stream_id from phase2f_refs)
      and source_sequence = '104'
  ),
  2,
  'duplicate sequence evidence is retained as two immutable observations'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      (select received_at from phase2f_refs) + interval '65 seconds',
      'phase2f:sequence:105-clock-ahead',
      25,
      null,
      null,
      (select received_at from phase2f_refs) + interval '5 seconds',
      'VALID',
      '105'
    )
  $$,
  'future clock observation inside the hard limit is preserved'
);

select extensions.ok(
  (
    select receipt.sequence_status = 'CONTIGUOUS'
      and receipt.clock_status = 'CLOCK_AHEAD'
      and receipt.clock_drift_seconds = 60
      and observation.quality_status = 'SUSPECT'
    from public.observation_transport_quality_receipts as receipt
    join public.stream_observations as observation on observation.id = receipt.observation_id
    where observation.idempotency_key = 'phase2f:sequence:105-clock-ahead'
  ),
  'clock-ahead receipt snapshots drift and marks the observation suspect'
);

select extensions.is(
  (
    select count(*)::integer
    from public.observation_quality_findings as finding
    join public.stream_observations as observation on observation.id = finding.observation_id
    where observation.idempotency_key = 'phase2f:sequence:105-clock-ahead'
      and finding.finding_code = 'SOURCE_CLOCK_AHEAD'
  ),
  1,
  'clock drift creates a normalized quality finding'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      (select received_at from phase2f_refs) + interval '16 seconds',
      'phase2f:sequence:106-within-drift',
      26,
      null,
      null,
      (select received_at from phase2f_refs) + interval '6 seconds',
      'VALID',
      '106'
    )
  $$,
  'future timestamp inside policy tolerance is recorded'
);

select extensions.ok(
  (
    select receipt.clock_status = 'WITHIN_TOLERANCE'
      and receipt.clock_drift_seconds = 10
      and observation.quality_status = 'VALID'
    from public.observation_transport_quality_receipts as receipt
    join public.stream_observations as observation on observation.id = receipt.observation_id
    where observation.idempotency_key = 'phase2f:sequence:106-within-drift'
  ),
  'timestamp inside tolerance remains valid'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      (select received_at from phase2f_refs) - interval '31 minutes',
      'phase2f:sequence:107-late',
      27,
      null,
      null,
      (select received_at from phase2f_refs),
      'VALID',
      '107'
    )
  $$,
  'late observation remains accepted under the existing latency policy'
);

select extensions.ok(
  (
    select receipt.clock_status = 'WITHIN_TOLERANCE'
      and receipt.clock_drift_seconds = 0
      and observation.quality_status = 'LATE'
    from public.observation_transport_quality_receipts as receipt
    join public.stream_observations as observation on observation.id = receipt.observation_id
    where observation.idempotency_key = 'phase2f:sequence:107-late'
  ),
  'past network latency remains distinct from future clock drift'
);

select extensions.ok(
  (
    select last_sequence_value = 107
      and receipt_count = 8
      and anomaly_count = 3
    from public.observation_stream_sequence_states
    where stream_id = (select stream_id from phase2f_refs)
  ),
  'sequence state summarizes eight receipts and three sequence anomalies'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      (select received_at from phase2f_refs) + interval '10 seconds',
      'phase2f:sequence:101-old-duplicate',
      30,
      null,
      null,
      (select received_at from phase2f_refs) + interval '10 seconds',
      'VALID',
      '101'
    )
  $$,
  'previously processed sequence is preserved when replayed after a later watermark'
);

select extensions.ok(
  (
    select receipt.sequence_status = 'DUPLICATE'
      and not receipt.sequence_state_advanced
      and observation.quality_status = 'SUSPECT'
    from public.observation_transport_quality_receipts as receipt
    join public.stream_observations as observation on observation.id = receipt.observation_id
    where observation.idempotency_key = 'phase2f:sequence:101-old-duplicate'
  )
  and (
    select count(*) = 1
    from public.observation_quality_findings as finding
    join public.stream_observations as observation on observation.id = finding.observation_id
    where observation.idempotency_key = 'phase2f:sequence:101-old-duplicate'
      and finding.finding_code = 'SOURCE_SEQUENCE_DUPLICATE'
  ),
  'historical replay is normalized to duplicate receipt and finding'
);

select extensions.is(
  (
    select count(*)::integer
    from public.observation_transport_quality_receipts
    where farm_id = '2b000000-0000-4000-8000-000000000001'
  ),
  9,
  'each accepted observation has exactly one transport receipt'
);

select extensions.lives_ok(
  $$
    select public.update_observation_stream_quality_policy(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      2,
      'NONE',
      300,
      'DISABLE_SEQUENCE_TRACKING',
      'Gateway counter maintenance'
    )
  $$,
  'owner disables sequence tracking'
);

select extensions.is(
  (
    select count(*)::integer
    from public.observation_stream_sequence_states
    where stream_id = (select stream_id from phase2f_refs)
  ),
  0,
  'sequence policy mode change resets the current high watermark state'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      (select received_at from phase2f_refs) + interval '8 seconds',
      'phase2f:untracked:alpha',
      28,
      null,
      null,
      (select received_at from phase2f_refs) + interval '8 seconds',
      'VALID',
      'alpha-sequence'
    )
  $$,
  'untracked policy accepts an opaque source sequence'
);

select extensions.ok(
  (
    select sequence_policy = 'NONE'
      and sequence_status = 'NOT_TRACKED'
      and source_sequence_value is null
    from public.observation_transport_quality_receipts as receipt
    join public.stream_observations as observation on observation.id = receipt.observation_id
    where observation.idempotency_key = 'phase2f:untracked:alpha'
  ),
  'untracked receipt keeps sequence evidence out of the numeric fields'
);

select extensions.lives_ok(
  $$
    select public.update_observation_stream_quality_policy(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      3,
      'MONOTONIC_INTEGER',
      15,
      'REENABLE_SEQUENCE_TRACKING',
      'Gateway counter reset completed'
    )
  $$,
  'owner re-enables sequence tracking with a new tolerance'
);

select extensions.lives_ok(
  $$
    select public.record_stream_observation(
      '2b000000-0000-4000-8000-000000000001',
      (select stream_id from phase2f_refs),
      (select received_at from phase2f_refs) + interval '9 seconds',
      'phase2f:sequence:reset-5',
      29,
      null,
      null,
      (select received_at from phase2f_refs) + interval '9 seconds',
      'VALID',
      '5'
    )
  $$,
  'first observation after re-enable starts a fresh sequence baseline'
);

select extensions.ok(
  (
    select sequence_status = 'FIRST'
      and previous_high_watermark is null
      and policy_version = 4
    from public.observation_transport_quality_receipts as receipt
    join public.stream_observations as observation on observation.id = receipt.observation_id
    where observation.idempotency_key = 'phase2f:sequence:reset-5'
  ),
  're-enabled tracking snapshots policy four and a fresh FIRST receipt'
);

select extensions.is(
  (
    select count(*)::integer
    from public.observation_stream_quality_policy_versions
    where stream_id = (select stream_id from phase2f_refs)
  ),
  4,
  'policy history preserves initial, enable, disable, and re-enable versions'
);

select extensions.is(
  (
    select count(*)::integer
    from public.stream_observations
    where farm_id = '2b000000-0000-4000-8000-000000000001'
  ),
  11,
  'invalid sequence and idempotent retry create no extra observations'
);

select extensions.is(
  (
    select count(*)::integer
    from public.domain_events
    where farm_id = '2b000000-0000-4000-8000-000000000001'
  ),
  11,
  'every accepted quality-classified observation emits one domain event'
);

set local request.jwt.claim.sub = '1b000000-0000-4000-8000-000000000002';

select extensions.is(
  (
    select count(*)::integer
    from public.observation_transport_quality_receipts
    where farm_id = '2b000000-0000-4000-8000-000000000001'
  ),
  11,
  'farm member can read transport quality receipts'
);

set local request.jwt.claim.sub = '1b000000-0000-4000-8000-000000000003';

select extensions.is(
  (
    select count(*)::integer
    from public.observation_transport_quality_receipts
    where farm_id = '2b000000-0000-4000-8000-000000000001'
  ),
  0,
  'outsider cannot read transport quality receipts'
);

select extensions.throws_ok(
  $$ insert into public.observation_transport_quality_receipts default values $$,
  '42501',
  null,
  'authenticated clients cannot directly write transport receipts'
);

reset role;

select extensions.is(
  (
    select count(*)::integer
    from public.observation_quality_findings
    where farm_id = '2b000000-0000-4000-8000-000000000001'
      and finding_code in (
        'SOURCE_SEQUENCE_GAP',
        'SOURCE_SEQUENCE_OUT_OF_ORDER',
        'SOURCE_SEQUENCE_DUPLICATE',
        'SOURCE_CLOCK_AHEAD'
      )
  ),
  5,
  'five normalized transport anomaly findings remain auditable'
);

select extensions.is(
  (
    select count(*)::integer
    from public.observation_stream_quality_policy_versions
    where stream_id = (select stream_id from phase2f_refs)
      and changed_by = '1b000000-0000-4000-8000-000000000001'
  ),
  4,
  'every policy version preserves the manager actor'
);

select * from extensions.finish();

rollback;
