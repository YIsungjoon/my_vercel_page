-- Phase 2B: relational observation provenance, quality, calibration, and trigger evidence.

create table public.measurement_units (
  code text primary key,
  name text not null,
  symbol text not null,
  quantity_kind text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint measurement_units_code_format_check
    check (code ~ '^[A-Za-z][A-Za-z0-9_./%-]*$'),
  constraint measurement_units_name_check check (char_length(trim(name)) > 0),
  constraint measurement_units_symbol_check check (char_length(trim(symbol)) > 0),
  constraint measurement_units_quantity_check
    check (quantity_kind ~ '^[A-Z][A-Z0-9_]*$')
);

insert into public.measurement_units (code, name, symbol, quantity_kind)
values
  ('degC', 'degree Celsius', 'degC', 'TEMPERATURE'),
  ('pct', 'percent', '%', 'RATIO'),
  ('mm', 'millimetre', 'mm', 'LENGTH'),
  ('mm_h', 'millimetres per hour', 'mm/h', 'PRECIPITATION_RATE'),
  ('kph', 'kilometres per hour', 'km/h', 'SPEED'),
  ('deg', 'degree', 'deg', 'ANGLE'),
  ('ppm', 'parts per million', 'ppm', 'CONCENTRATION'),
  ('umol_m2_s', 'micromoles per square metre per second', 'umol/m2/s', 'LIGHT_FLUX'),
  ('kPa', 'kilopascal', 'kPa', 'PRESSURE'),
  ('pH', 'potential of hydrogen', 'pH', 'ACIDITY'),
  ('mS_cm', 'millisiemens per centimetre', 'mS/cm', 'CONDUCTIVITY'),
  ('L', 'litre', 'L', 'VOLUME'),
  ('L_min', 'litres per minute', 'L/min', 'FLOW_RATE'),
  ('count', 'count', 'count', 'COUNT');

create table public.observation_fields (
  code text primary key,
  name text not null,
  event_type text not null,
  value_type text not null,
  canonical_unit_code text references public.measurement_units(code) on delete restrict,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint observation_fields_code_format_check
    check (code ~ '^[a-z][a-z0-9_.]*$'),
  constraint observation_fields_event_type_check
    check (event_type in ('WEATHER_OBSERVATION', 'SENSOR_OBSERVATION')),
  constraint observation_fields_value_type_check
    check (value_type in ('NUMERIC', 'TEXT', 'BOOLEAN')),
  constraint observation_fields_unit_check
    check (
      (value_type = 'NUMERIC' and canonical_unit_code is not null)
      or (value_type <> 'NUMERIC' and canonical_unit_code is null)
    )
);

insert into public.observation_fields (
  code, name, event_type, value_type, canonical_unit_code
)
values
  ('weather.temperature_c', 'Weather temperature', 'WEATHER_OBSERVATION', 'NUMERIC', 'degC'),
  ('weather.humidity_pct', 'Weather relative humidity', 'WEATHER_OBSERVATION', 'NUMERIC', 'pct'),
  ('weather.rainfall_mm', 'Weather rainfall', 'WEATHER_OBSERVATION', 'NUMERIC', 'mm'),
  ('weather.precipitation_mm', 'Weather precipitation', 'WEATHER_OBSERVATION', 'NUMERIC', 'mm'),
  ('weather.wind_speed_kph', 'Weather wind speed', 'WEATHER_OBSERVATION', 'NUMERIC', 'kph'),
  ('weather.wind_direction_deg', 'Weather wind direction', 'WEATHER_OBSERVATION', 'NUMERIC', 'deg'),
  ('weather.weather_code', 'Weather condition code', 'WEATHER_OBSERVATION', 'NUMERIC', 'count'),
  ('sensor.temperature_c', 'Sensor temperature', 'SENSOR_OBSERVATION', 'NUMERIC', 'degC'),
  ('sensor.humidity_pct', 'Sensor relative humidity', 'SENSOR_OBSERVATION', 'NUMERIC', 'pct'),
  ('sensor.co2_ppm', 'Sensor carbon dioxide', 'SENSOR_OBSERVATION', 'NUMERIC', 'ppm'),
  ('sensor.light_umol_m2_s', 'Sensor photosynthetic photon flux', 'SENSOR_OBSERVATION', 'NUMERIC', 'umol_m2_s'),
  ('sensor.vpd_kpa', 'Sensor vapour pressure deficit', 'SENSOR_OBSERVATION', 'NUMERIC', 'kPa'),
  ('sensor.soil_moisture_pct', 'Sensor soil moisture', 'SENSOR_OBSERVATION', 'NUMERIC', 'pct'),
  ('sensor.nutrient_ph', 'Nutrient solution pH', 'SENSOR_OBSERVATION', 'NUMERIC', 'pH'),
  ('sensor.nutrient_ec_ms_cm', 'Nutrient solution EC', 'SENSOR_OBSERVATION', 'NUMERIC', 'mS_cm'),
  ('sensor.flow_l_min', 'Sensor flow rate', 'SENSOR_OBSERVATION', 'NUMERIC', 'L_min'),
  ('sensor.device_online', 'Sensor device availability', 'SENSOR_OBSERVATION', 'BOOLEAN', null),
  ('sensor.alarm_state', 'Sensor alarm state', 'SENSOR_OBSERVATION', 'TEXT', null);

create table public.observation_sources (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  source_code text not null,
  name text not null,
  source_kind text not null,
  provider_code text,
  external_reference text,
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint observation_sources_farm_code_key unique (farm_id, source_code),
  constraint observation_sources_farm_id_id_key unique (farm_id, id),
  constraint observation_sources_code_format_check
    check (source_code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'),
  constraint observation_sources_name_check check (char_length(trim(name)) > 0),
  constraint observation_sources_kind_check
    check (source_kind in ('WEATHER_API', 'SENSOR_DEVICE', 'SENSOR_GATEWAY', 'MANUAL', 'SYSTEM')),
  constraint observation_sources_provider_check
    check (provider_code is null or provider_code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'),
  constraint observation_sources_external_reference_check
    check (external_reference is null or char_length(trim(external_reference)) > 0)
);

create table public.observation_streams (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  source_id uuid not null,
  work_area_id uuid,
  field_code text not null references public.observation_fields(code) on delete restrict,
  stream_code text not null,
  name text not null,
  unit_code text references public.measurement_units(code) on delete restrict,
  max_latency_minutes integer not null default 15,
  requires_calibration boolean not null default false,
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint observation_streams_source_code_key unique (source_id, stream_code),
  constraint observation_streams_farm_id_id_key unique (farm_id, id),
  constraint observation_streams_code_format_check
    check (stream_code ~ '^[A-Za-z0-9][A-Za-z0-9_.-]*$'),
  constraint observation_streams_name_check check (char_length(trim(name)) > 0),
  constraint observation_streams_latency_check
    check (max_latency_minutes between 0 and 10080),
  constraint observation_streams_source_same_farm_fkey
    foreign key (farm_id, source_id)
    references public.observation_sources(farm_id, id)
    on delete cascade,
  constraint observation_streams_area_same_farm_fkey
    foreign key (farm_id, work_area_id)
    references public.farm_work_areas(farm_id, id)
    on delete restrict
);

create table public.observation_calibrations (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  stream_id uuid not null,
  calibration_code text not null,
  valid_from timestamptz not null,
  valid_until timestamptz,
  status text not null default 'VALID',
  reference_standard text,
  certificate_reference text,
  performed_by text,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint observation_calibrations_stream_code_key unique (stream_id, calibration_code),
  constraint observation_calibrations_farm_stream_id_id_key unique (farm_id, stream_id, id),
  constraint observation_calibrations_code_format_check
    check (calibration_code ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]*$'),
  constraint observation_calibrations_status_check check (status in ('VALID', 'REVOKED')),
  constraint observation_calibrations_valid_range_check
    check (valid_until is null or valid_until > valid_from),
  constraint observation_calibrations_stream_same_farm_fkey
    foreign key (farm_id, stream_id)
    references public.observation_streams(farm_id, id)
    on delete restrict
);

create table public.stream_observations (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  stream_id uuid not null,
  calibration_id uuid,
  observed_at timestamptz not null,
  received_at timestamptz not null,
  numeric_value numeric,
  text_value text,
  boolean_value boolean,
  source_quality_status text not null default 'VALID',
  quality_status text not null,
  source_sequence text,
  idempotency_key text not null,
  recorded_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now(),
  constraint stream_observations_stream_idempotency_key unique (stream_id, idempotency_key),
  constraint stream_observations_farm_stream_id_id_key unique (farm_id, stream_id, id),
  constraint stream_observations_exactly_one_value_check
    check (num_nonnulls(numeric_value, text_value, boolean_value) = 1),
  constraint stream_observations_source_quality_check
    check (source_quality_status in ('VALID', 'SUSPECT', 'INVALID')),
  constraint stream_observations_quality_check
    check (quality_status in ('VALID', 'SUSPECT', 'INVALID', 'LATE', 'UNCALIBRATED')),
  constraint stream_observations_timestamp_check
    check (observed_at <= received_at + interval '5 minutes'),
  constraint stream_observations_idempotency_format_check
    check (idempotency_key ~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$'),
  constraint stream_observations_source_sequence_check
    check (source_sequence is null or char_length(trim(source_sequence)) > 0),
  constraint stream_observations_stream_same_farm_fkey
    foreign key (farm_id, stream_id)
    references public.observation_streams(farm_id, id)
    on delete restrict,
  constraint stream_observations_calibration_same_stream_fkey
    foreign key (farm_id, stream_id, calibration_id)
    references public.observation_calibrations(farm_id, stream_id, id)
    on delete restrict
);

create unique index stream_observations_source_sequence_idx
on public.stream_observations(stream_id, source_sequence)
where source_sequence is not null;

create table public.observation_quality_findings (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  stream_id uuid not null,
  observation_id uuid not null,
  finding_code text not null,
  severity text not null,
  detail text,
  detected_at timestamptz not null default now(),
  constraint observation_quality_findings_observation_code_key
    unique (observation_id, finding_code),
  constraint observation_quality_findings_code_format_check
    check (finding_code ~ '^[A-Z][A-Z0-9_]*$'),
  constraint observation_quality_findings_severity_check
    check (severity in ('WARNING', 'ERROR')),
  constraint observation_quality_findings_observation_same_stream_fkey
    foreign key (farm_id, stream_id, observation_id)
    references public.stream_observations(farm_id, stream_id, id)
    on delete cascade
);

alter table public.activity_trigger_predicates
  add constraint activity_trigger_predicates_farm_project_id_id_key
  unique (farm_id, project_id, id);

create table public.activity_trigger_evaluations (
  rule_run_id uuid primary key,
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  trigger_rule_id uuid not null,
  source_rule_version integer not null,
  evaluated_at timestamptz not null,
  event_type text not null,
  match_mode text not null,
  predicate_count integer not null,
  matched_count integer not null default 0,
  insufficient_count integer not null default 0,
  created_at timestamptz not null default now(),
  constraint activity_trigger_evaluations_farm_project_run_key
    unique (farm_id, project_id, rule_run_id),
  constraint activity_trigger_evaluations_rule_version_time_key
    unique (trigger_rule_id, source_rule_version, evaluated_at),
  constraint activity_trigger_evaluations_version_check check (source_rule_version >= 1),
  constraint activity_trigger_evaluations_event_type_check
    check (event_type in ('WEATHER_OBSERVATION', 'SENSOR_OBSERVATION')),
  constraint activity_trigger_evaluations_match_mode_check check (match_mode in ('ALL', 'ANY')),
  constraint activity_trigger_evaluations_counts_check
    check (
      predicate_count >= 1
      and matched_count between 0 and predicate_count
      and insufficient_count between 0 and predicate_count
      and matched_count + insufficient_count <= predicate_count
    ),
  constraint activity_trigger_evaluations_run_same_project_fkey
    foreign key (farm_id, project_id, rule_run_id)
    references public.activity_rule_runs(farm_id, project_id, id)
    on delete restrict,
  constraint activity_trigger_evaluations_rule_same_project_fkey
    foreign key (farm_id, project_id, trigger_rule_id)
    references public.activity_trigger_rules(farm_id, project_id, id)
    on delete restrict
);

create table public.activity_trigger_evaluation_work_areas (
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  rule_run_id uuid not null,
  work_area_id uuid not null,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (rule_run_id, work_area_id),
  constraint activity_trigger_evaluation_areas_run_same_project_fkey
    foreign key (farm_id, project_id, rule_run_id)
    references public.activity_trigger_evaluations(farm_id, project_id, rule_run_id)
    on delete cascade,
  constraint activity_trigger_evaluation_areas_area_same_farm_fkey
    foreign key (farm_id, work_area_id)
    references public.farm_work_areas(farm_id, id)
    on delete restrict
);

create unique index activity_trigger_evaluation_areas_one_primary_idx
on public.activity_trigger_evaluation_work_areas(rule_run_id)
where is_primary;

create table public.activity_trigger_predicate_evaluations (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  project_id uuid not null,
  rule_run_id uuid not null,
  trigger_predicate_id uuid not null,
  predicate_sequence_no integer not null,
  source_field_code text not null,
  comparison_operator text not null,
  expected_numeric_value numeric,
  expected_text_value text,
  expected_boolean_value boolean,
  expected_unit_code text,
  observation_id uuid,
  observation_stream_id uuid,
  observed_numeric_value numeric,
  observed_text_value text,
  observed_boolean_value boolean,
  observed_unit_code text,
  observed_at timestamptz,
  observation_quality_status text,
  result_status text not null,
  reason_code text,
  created_at timestamptz not null default now(),
  constraint activity_trigger_predicate_evaluations_run_predicate_key
    unique (rule_run_id, trigger_predicate_id),
  constraint activity_trigger_predicate_evaluations_sequence_check
    check (predicate_sequence_no >= 1),
  constraint activity_trigger_predicate_evaluations_field_check
    check (source_field_code ~ '^[a-z][a-z0-9_.]*$'),
  constraint activity_trigger_predicate_evaluations_operator_check
    check (comparison_operator in ('GT', 'GTE', 'LT', 'LTE', 'EQ', 'NEQ')),
  constraint activity_trigger_predicate_evaluations_expected_value_check
    check (num_nonnulls(expected_numeric_value, expected_text_value, expected_boolean_value) = 1),
  constraint activity_trigger_predicate_evaluations_observed_value_check
    check (
      (
        observation_id is null
        and observation_stream_id is null
        and observed_at is null
        and observation_quality_status is null
        and num_nonnulls(observed_numeric_value, observed_text_value, observed_boolean_value) = 0
      )
      or (
        observation_id is not null
        and observation_stream_id is not null
        and observed_at is not null
        and observation_quality_status is not null
        and num_nonnulls(observed_numeric_value, observed_text_value, observed_boolean_value) = 1
      )
    ),
  constraint activity_trigger_predicate_evaluations_result_check
    check (result_status in ('MATCHED', 'NOT_MATCHED', 'INSUFFICIENT')),
  constraint activity_trigger_predicate_evaluations_reason_check
    check (
      (result_status = 'INSUFFICIENT' and reason_code is not null)
      or (result_status <> 'INSUFFICIENT' and reason_code is null)
    ),
  constraint activity_trigger_predicate_evaluations_run_same_project_fkey
    foreign key (farm_id, project_id, rule_run_id)
    references public.activity_trigger_evaluations(farm_id, project_id, rule_run_id)
    on delete cascade,
  constraint activity_trigger_predicate_evaluations_predicate_same_project_fkey
    foreign key (farm_id, project_id, trigger_predicate_id)
    references public.activity_trigger_predicates(farm_id, project_id, id)
    on delete restrict,
  constraint activity_trigger_predicate_evaluations_observation_same_stream_fkey
    foreign key (farm_id, observation_stream_id, observation_id)
    references public.stream_observations(farm_id, stream_id, id)
    on delete restrict,
  constraint activity_trigger_predicate_evaluations_expected_unit_fkey
    foreign key (expected_unit_code) references public.measurement_units(code),
  constraint activity_trigger_predicate_evaluations_observed_unit_fkey
    foreign key (observed_unit_code) references public.measurement_units(code)
);

create index observation_sources_farm_active_idx
on public.observation_sources(farm_id, is_active, source_code);

create index observation_streams_farm_field_area_idx
on public.observation_streams(farm_id, field_code, work_area_id)
where is_active;

create index observation_calibrations_stream_valid_idx
on public.observation_calibrations(stream_id, valid_from desc, valid_until)
where status = 'VALID';

create index stream_observations_stream_observed_idx
on public.stream_observations(stream_id, observed_at desc);

create index stream_observations_farm_quality_time_idx
on public.stream_observations(farm_id, quality_status, observed_at desc);

create index activity_trigger_predicate_evaluations_run_sequence_idx
on public.activity_trigger_predicate_evaluations(rule_run_id, predicate_sequence_no);

create trigger set_observation_sources_updated_at
before update on public.observation_sources
for each row execute function public.set_updated_at();

create trigger set_observation_streams_updated_at
before update on public.observation_streams
for each row execute function public.set_updated_at();

create or replace function public.validate_observation_stream_definition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_field public.observation_fields;
  selected_source public.observation_sources;
begin
  select * into selected_field
  from public.observation_fields
  where code = new.field_code and is_active;

  if not found then
    raise exception 'An active observation field is required';
  end if;

  select * into selected_source
  from public.observation_sources
  where farm_id = new.farm_id and id = new.source_id;

  if not found then
    raise exception 'Observation source was not found for this farm';
  end if;

  if new.unit_code is distinct from selected_field.canonical_unit_code then
    raise exception 'Observation stream unit must match the field canonical unit';
  end if;

  if selected_source.source_kind = 'WEATHER_API'
     and selected_field.event_type <> 'WEATHER_OBSERVATION' then
    raise exception 'Weather sources require weather observation fields';
  end if;

  if selected_source.source_kind in ('SENSOR_DEVICE', 'SENSOR_GATEWAY')
     and selected_field.event_type <> 'SENSOR_OBSERVATION' then
    raise exception 'Sensor sources require sensor observation fields';
  end if;

  return new;
end;
$$;

alter table public.measurement_units enable row level security;
alter table public.observation_fields enable row level security;
alter table public.observation_sources enable row level security;
alter table public.observation_streams enable row level security;
alter table public.observation_calibrations enable row level security;
alter table public.stream_observations enable row level security;
alter table public.observation_quality_findings enable row level security;
alter table public.activity_trigger_evaluations enable row level security;
alter table public.activity_trigger_evaluation_work_areas enable row level security;
alter table public.activity_trigger_predicate_evaluations enable row level security;

create policy measurement_units_are_readable
on public.measurement_units
for select to anon, authenticated
using (true);

create policy observation_fields_are_readable
on public.observation_fields
for select to anon, authenticated
using (true);

create policy members_read_observation_sources
on public.observation_sources
for select to authenticated
using (public.is_farm_member(farm_id));

create policy members_read_observation_streams
on public.observation_streams
for select to authenticated
using (public.is_farm_member(farm_id));

create policy members_read_observation_calibrations
on public.observation_calibrations
for select to authenticated
using (public.is_farm_member(farm_id));

create policy members_read_stream_observations
on public.stream_observations
for select to authenticated
using (public.is_farm_member(farm_id));

create policy members_read_observation_quality_findings
on public.observation_quality_findings
for select to authenticated
using (public.is_farm_member(farm_id));

create policy members_read_activity_trigger_evaluations
on public.activity_trigger_evaluations
for select to authenticated
using (public.is_farm_member(farm_id));

create policy members_read_activity_trigger_evaluation_areas
on public.activity_trigger_evaluation_work_areas
for select to authenticated
using (public.is_farm_member(farm_id));

create policy members_read_activity_trigger_predicate_evaluations
on public.activity_trigger_predicate_evaluations
for select to authenticated
using (public.is_farm_member(farm_id));

grant select on table
  public.measurement_units,
  public.observation_fields
to anon, authenticated;

grant select on table
  public.observation_sources,
  public.observation_streams,
  public.observation_calibrations,
  public.stream_observations,
  public.observation_quality_findings,
  public.activity_trigger_evaluations,
  public.activity_trigger_evaluation_work_areas,
  public.activity_trigger_predicate_evaluations
to authenticated;

revoke all on table
  public.observation_sources,
  public.observation_streams,
  public.observation_calibrations,
  public.stream_observations,
  public.observation_quality_findings,
  public.activity_trigger_evaluations,
  public.activity_trigger_evaluation_work_areas,
  public.activity_trigger_predicate_evaluations
from anon;

revoke insert, update, delete, truncate, trigger, references on table
  public.measurement_units,
  public.observation_fields,
  public.observation_sources,
  public.observation_streams,
  public.observation_calibrations,
  public.stream_observations,
  public.observation_quality_findings,
  public.activity_trigger_evaluations,
  public.activity_trigger_evaluation_work_areas,
  public.activity_trigger_predicate_evaluations
from anon, authenticated;

comment on table public.stream_observations is
  'Immutable typed observations. JSON is transport only; quality details use child rows.';

comment on table public.activity_trigger_predicate_evaluations is
  'Predicate-level immutable evidence for a trigger evaluation run.';

create trigger validate_observation_stream_definition
before insert or update of farm_id, source_id, field_code, unit_code
on public.observation_streams
for each row execute function public.validate_observation_stream_definition();

create or replace function public.create_observation_source(
  target_farm_id uuid,
  source_code text,
  source_name text,
  source_kind text,
  provider_code text default null,
  external_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  created_source public.observation_sources;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to create an observation source';
  end if;

  insert into public.observation_sources (
    farm_id, source_code, name, source_kind, provider_code,
    external_reference, created_by
  )
  values (
    target_farm_id,
    trim(source_code),
    trim(source_name),
    source_kind,
    nullif(trim(provider_code), ''),
    nullif(trim(external_reference), ''),
    auth.uid()
  )
  returning * into created_source;

  return to_jsonb(created_source);
end;
$$;

create or replace function public.create_observation_stream(
  target_farm_id uuid,
  target_source_id uuid,
  target_field_code text,
  stream_code text,
  stream_name text,
  target_work_area_id uuid default null,
  max_latency_minutes integer default 15,
  requires_calibration boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  selected_field public.observation_fields;
  created_stream public.observation_streams;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to create an observation stream';
  end if;

  select * into selected_field
  from public.observation_fields
  where code = trim(target_field_code) and is_active;

  if not found then
    raise exception 'An active observation field was not found';
  end if;

  if target_work_area_id is not null and not exists (
    select 1
    from public.farm_work_areas
    where farm_id = target_farm_id
      and id = target_work_area_id
      and is_active
  ) then
    raise exception 'An active work area was not found for this farm';
  end if;

  insert into public.observation_streams (
    farm_id, source_id, work_area_id, field_code, stream_code, name,
    unit_code, max_latency_minutes, requires_calibration, created_by
  )
  values (
    target_farm_id,
    target_source_id,
    target_work_area_id,
    selected_field.code,
    trim(stream_code),
    trim(stream_name),
    selected_field.canonical_unit_code,
    max_latency_minutes,
    requires_calibration,
    auth.uid()
  )
  returning * into created_stream;

  return to_jsonb(created_stream);
end;
$$;

create or replace function public.record_observation_calibration(
  target_farm_id uuid,
  target_stream_id uuid,
  calibration_code text,
  valid_from timestamptz,
  valid_until timestamptz default null,
  reference_standard text default null,
  certificate_reference text default null,
  performed_by text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  created_calibration public.observation_calibrations;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to record a calibration';
  end if;

  if not exists (
    select 1
    from public.observation_streams
    where farm_id = target_farm_id and id = target_stream_id
  ) then
    raise exception 'Observation stream was not found for this farm';
  end if;

  if $4 is null
     or ($5 is not null and $5 <= $4) then
    raise exception 'A valid calibration period is required';
  end if;

  if exists (
    select 1
    from public.observation_calibrations as calibration
    where calibration.stream_id = target_stream_id
      and calibration.status = 'VALID'
      and calibration.valid_from < coalesce($5, 'infinity'::timestamptz)
      and coalesce(calibration.valid_until, 'infinity'::timestamptz) > $4
  ) then
    raise exception 'Calibration validity periods cannot overlap';
  end if;

  insert into public.observation_calibrations (
    farm_id, stream_id, calibration_code, valid_from, valid_until,
    reference_standard, certificate_reference, performed_by, recorded_by
  )
  values (
    target_farm_id,
    target_stream_id,
    trim(calibration_code),
    $4,
    $5,
    nullif(trim(reference_standard), ''),
    nullif(trim(certificate_reference), ''),
    nullif(trim(performed_by), ''),
    auth.uid()
  )
  returning * into created_calibration;

  return to_jsonb(created_calibration);
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
  )
  into selected_findings
  from public.observation_quality_findings as finding
  where finding.observation_id = selected_observation.id;

  return jsonb_build_object(
    'observation', to_jsonb(selected_observation),
    'quality_findings', selected_findings
  );
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
declare
  selected_stream record;
  selected_calibration public.observation_calibrations;
  existing_observation public.stream_observations;
  created_observation public.stream_observations;
  derived_quality_status text;
  latency_minutes numeric;
  effective_received_at timestamptz;
begin
  if not public.has_farm_role(
    target_farm_id,
    array['owner', 'manager', 'worker']
  ) then
    raise exception 'Farm action permission is required to record an observation';
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
         is distinct from nullif(trim(source_sequence), '') then
      raise exception 'Observation idempotency key is already used by another request';
    end if;

    return public.stream_observation_response(existing_observation.id);
  end if;

  select
    stream.*,
    source.is_active as source_is_active,
    field.value_type
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
    farm_id, stream_id, calibration_id, observed_at, received_at,
    numeric_value, text_value, boolean_value, source_quality_status,
    quality_status, source_sequence, idempotency_key, recorded_by
  )
  values (
    target_farm_id,
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
    auth.uid()
  )
  returning * into created_observation;

  if source_quality_status = 'SUSPECT' then
    insert into public.observation_quality_findings (
      farm_id, stream_id, observation_id, finding_code, severity, detail
    )
    values (
      target_farm_id, target_stream_id, created_observation.id,
      'SOURCE_SUSPECT', 'WARNING',
      'The source reported this observation as suspect.'
    );
  elsif source_quality_status = 'INVALID' then
    insert into public.observation_quality_findings (
      farm_id, stream_id, observation_id, finding_code, severity, detail
    )
    values (
      target_farm_id, target_stream_id, created_observation.id,
      'SOURCE_INVALID', 'ERROR',
      'The source reported this observation as invalid.'
    );
  end if;

  if selected_stream.requires_calibration and selected_calibration.id is null then
    insert into public.observation_quality_findings (
      farm_id, stream_id, observation_id, finding_code, severity, detail
    )
    values (
      target_farm_id, target_stream_id, created_observation.id,
      'NO_VALID_CALIBRATION', 'ERROR',
      'No valid calibration covered the observation time.'
    );
  end if;

  if latency_minutes > selected_stream.max_latency_minutes then
    insert into public.observation_quality_findings (
      farm_id, stream_id, observation_id, finding_code, severity, detail
    )
    values (
      target_farm_id, target_stream_id, created_observation.id,
      'RECEIVED_LATE', 'WARNING',
      'The observation exceeded the stream latency threshold.'
    );
  end if;

  return public.stream_observation_response(created_observation.id);
end;
$$;

create or replace function public.activity_trigger_evaluation_response(
  target_run_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_run public.activity_rule_runs;
  selected_evaluation public.activity_trigger_evaluations;
  selected_predicates jsonb;
  selected_areas jsonb;
  selected_proposals jsonb;
begin
  select * into selected_run
  from public.activity_rule_runs
  where id = target_run_id;

  select * into selected_evaluation
  from public.activity_trigger_evaluations
  where rule_run_id = target_run_id;

  if selected_run.id is null or selected_evaluation.rule_run_id is null then
    raise exception 'Activity trigger evaluation was not found';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(result) order by result.predicate_sequence_no),
    '[]'::jsonb
  )
  into selected_predicates
  from public.activity_trigger_predicate_evaluations as result
  where result.rule_run_id = target_run_id;

  select coalesce(
    jsonb_agg(to_jsonb(area) order by area.is_primary desc, area.created_at),
    '[]'::jsonb
  )
  into selected_areas
  from public.activity_trigger_evaluation_work_areas as area
  where area.rule_run_id = target_run_id;

  select coalesce(
    jsonb_agg(to_jsonb(proposal) order by proposal.planned_start_at),
    '[]'::jsonb
  )
  into selected_proposals
  from public.activity_proposals as proposal
  where proposal.rule_run_id = target_run_id;

  return jsonb_build_object(
    'run', to_jsonb(selected_run),
    'evaluation', to_jsonb(selected_evaluation),
    'predicate_evaluations', selected_predicates,
    'work_areas', selected_areas,
    'proposals', selected_proposals
  );
end;
$$;

create or replace function public.evaluate_activity_trigger_rule(
  target_farm_id uuid,
  target_project_id uuid,
  target_rule_id uuid,
  expected_rule_version integer,
  target_evaluated_at timestamptz,
  run_idempotency_key text
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  current_rule public.activity_trigger_rules;
  current_template public.activity_templates;
  current_predicate public.activity_trigger_predicates;
  selected_observation public.stream_observations;
  selected_observed_unit text;
  selected_value_type text;
  existing_run public.activity_rule_runs;
  created_run public.activity_rule_runs;
  predicate_count integer;
  result_matched_count integer := 0;
  result_insufficient_count integer := 0;
  current_result text;
  current_reason text;
  is_match boolean;
  should_propose boolean;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to evaluate a trigger rule';
  end if;

  if nullif(trim(run_idempotency_key), '') is null
     or trim(run_idempotency_key) !~ '^[A-Za-z0-9][A-Za-z0-9_.:-]{7,127}$' then
    raise exception 'A valid run idempotency key is required';
  end if;

  if target_evaluated_at is null
     or target_evaluated_at > now() + interval '5 minutes' then
    raise exception 'A valid non-future evaluation time is required';
  end if;

  select * into existing_run
  from public.activity_rule_runs
  where project_id = target_project_id
    and idempotency_key = trim(run_idempotency_key);

  if found then
    if existing_run.farm_id <> target_farm_id
       or existing_run.run_kind <> 'TRIGGER_EVALUATION'
       or existing_run.trigger_rule_id <> target_rule_id
       or existing_run.source_rule_version <> expected_rule_version
       or not exists (
         select 1
         from public.activity_trigger_evaluations as evaluation
         where evaluation.rule_run_id = existing_run.id
           and evaluation.evaluated_at = target_evaluated_at
       ) then
      raise exception 'Run idempotency key is already used by another request';
    end if;

    return public.activity_trigger_evaluation_response(existing_run.id);
  end if;

  select * into current_rule
  from public.activity_trigger_rules
  where farm_id = target_farm_id
    and project_id = target_project_id
    and id = target_rule_id
  for share;

  if not found then
    raise exception 'Trigger rule was not found for this project';
  end if;

  if current_rule.status <> 'ACTIVE' then
    raise exception 'Only an active trigger rule can be evaluated';
  end if;

  if current_rule.event_type not in ('WEATHER_OBSERVATION', 'SENSOR_OBSERVATION') then
    raise exception 'This trigger event type does not use stream observations';
  end if;

  if current_rule.version <> expected_rule_version then
    raise exception using
      errcode = '40001',
      message = 'Trigger rule version conflict';
  end if;

  if current_rule.valid_from is not null
     and target_evaluated_at < current_rule.valid_from then
    raise exception 'Trigger rule is not valid at the evaluation time';
  end if;

  if current_rule.valid_until is not null
     and target_evaluated_at > current_rule.valid_until then
    raise exception 'Trigger rule is not valid at the evaluation time';
  end if;

  select * into current_template
  from public.activity_templates
  where farm_id = target_farm_id
    and id = current_rule.template_id
    and is_active;

  if not found then
    raise exception 'An active activity template is required for evaluation';
  end if;

  select count(*)::integer into predicate_count
  from public.activity_trigger_predicates
  where trigger_rule_id = current_rule.id;

  if predicate_count = 0 then
    raise exception 'A stream trigger rule requires at least one predicate';
  end if;

  if exists (
    select 1
    from public.activity_trigger_evaluations
    where trigger_rule_id = current_rule.id
      and source_rule_version = current_rule.version
      and evaluated_at = target_evaluated_at
  ) then
    raise exception 'This trigger rule version and time were already evaluated';
  end if;

  insert into public.activity_rule_runs (
    farm_id, project_id, run_kind, trigger_rule_id,
    source_rule_version, source_template_version,
    idempotency_key, status, created_by
  )
  values (
    target_farm_id,
    target_project_id,
    'TRIGGER_EVALUATION',
    current_rule.id,
    current_rule.version,
    current_template.version,
    trim(run_idempotency_key),
    'RUNNING',
    auth.uid()
  )
  returning * into created_run;

  insert into public.activity_trigger_evaluations (
    rule_run_id, farm_id, project_id, trigger_rule_id,
    source_rule_version, evaluated_at, event_type, match_mode, predicate_count
  )
  values (
    created_run.id,
    target_farm_id,
    target_project_id,
    current_rule.id,
    current_rule.version,
    target_evaluated_at,
    current_rule.event_type,
    current_rule.predicate_match_mode,
    predicate_count
  );

  insert into public.activity_trigger_evaluation_work_areas (
    farm_id, project_id, rule_run_id, work_area_id, is_primary
  )
  select
    target_farm_id,
    target_project_id,
    created_run.id,
    area.work_area_id,
    area.is_primary
  from public.activity_trigger_rule_work_areas as area
  where area.trigger_rule_id = current_rule.id;

  if current_rule.cooldown_minutes > 0 and exists (
    select 1
    from public.activity_trigger_evaluations as previous_evaluation
    join public.activity_rule_runs as previous_run
      on previous_run.id = previous_evaluation.rule_run_id
    where previous_evaluation.trigger_rule_id = current_rule.id
      and previous_evaluation.evaluated_at < target_evaluated_at
      and previous_evaluation.evaluated_at
        > target_evaluated_at - make_interval(mins => current_rule.cooldown_minutes)
      and previous_run.outcome_code = 'PROPOSAL_CREATED'
  ) then
    update public.activity_rule_runs
    set status = 'SKIPPED',
        outcome_code = 'COOLDOWN_ACTIVE',
        finished_at = now()
    where id = created_run.id
    returning * into created_run;

    return public.activity_trigger_evaluation_response(created_run.id);
  end if;

  for current_predicate in
    select *
    from public.activity_trigger_predicates
    where trigger_rule_id = current_rule.id
    order by sequence_no
  loop
    selected_observation := null;
    selected_observed_unit := null;
    selected_value_type := null;
    current_result := null;
    current_reason := null;
    is_match := false;

    if current_predicate.observation_window_minutes is null then
      current_result := 'INSUFFICIENT';
      current_reason := 'WINDOW_NOT_CONFIGURED';
    else
      select observation.*
      into selected_observation
      from public.stream_observations as observation
      join public.observation_streams as stream
        on stream.farm_id = observation.farm_id
       and stream.id = observation.stream_id
      join public.observation_sources as source
        on source.farm_id = stream.farm_id
       and source.id = stream.source_id
      join public.observation_fields as field
        on field.code = stream.field_code
      where observation.farm_id = target_farm_id
        and stream.field_code = current_predicate.source_field_code
        and field.event_type = current_rule.event_type
        and stream.is_active
        and source.is_active
        and observation.observed_at <= target_evaluated_at
        and observation.observed_at >= target_evaluated_at
          - make_interval(mins => current_predicate.observation_window_minutes)
        and (
          not exists (
            select 1
            from public.activity_trigger_rule_work_areas
            where trigger_rule_id = current_rule.id
          )
          or stream.work_area_id in (
            select area.work_area_id
            from public.activity_trigger_rule_work_areas as area
            where area.trigger_rule_id = current_rule.id
          )
        )
      order by observation.observed_at desc, observation.received_at desc
      limit 1;

      if selected_observation.id is null then
        current_result := 'INSUFFICIENT';
        current_reason := 'NO_OBSERVATION';
      else
        select field.value_type, stream.unit_code
        into selected_value_type, selected_observed_unit
        from public.observation_streams as stream
        join public.observation_fields as field
          on field.code = stream.field_code
        where stream.id = selected_observation.stream_id;

        if selected_observation.quality_status <> 'VALID' then
          current_result := 'INSUFFICIENT';
          current_reason := 'OBSERVATION_' || selected_observation.quality_status;
        elsif current_predicate.numeric_value is not null
              and selected_value_type <> 'NUMERIC' then
          current_result := 'INSUFFICIENT';
          current_reason := 'VALUE_TYPE_MISMATCH';
        elsif current_predicate.text_value is not null
              and selected_value_type <> 'TEXT' then
          current_result := 'INSUFFICIENT';
          current_reason := 'VALUE_TYPE_MISMATCH';
        elsif current_predicate.boolean_value is not null
              and selected_value_type <> 'BOOLEAN' then
          current_result := 'INSUFFICIENT';
          current_reason := 'VALUE_TYPE_MISMATCH';
        elsif current_predicate.numeric_value is not null
              and (
                current_predicate.unit_code is null
                or selected_observed_unit is distinct from current_predicate.unit_code
              ) then
          current_result := 'INSUFFICIENT';
          current_reason := 'UNIT_MISMATCH';
        elsif current_predicate.numeric_value is null
              and current_predicate.comparison_operator not in ('EQ', 'NEQ') then
          current_result := 'INSUFFICIENT';
          current_reason := 'OPERATOR_VALUE_TYPE_MISMATCH';
        else
          is_match := case current_predicate.comparison_operator
            when 'GT' then
              selected_observation.numeric_value > current_predicate.numeric_value
            when 'GTE' then
              selected_observation.numeric_value >= current_predicate.numeric_value
            when 'LT' then
              selected_observation.numeric_value < current_predicate.numeric_value
            when 'LTE' then
              selected_observation.numeric_value <= current_predicate.numeric_value
            when 'EQ' then
              coalesce(
                selected_observation.numeric_value = current_predicate.numeric_value,
                selected_observation.text_value = current_predicate.text_value,
                selected_observation.boolean_value = current_predicate.boolean_value,
                false
              )
            when 'NEQ' then
              coalesce(
                selected_observation.numeric_value <> current_predicate.numeric_value,
                selected_observation.text_value <> current_predicate.text_value,
                selected_observation.boolean_value <> current_predicate.boolean_value,
                false
              )
            else false
          end;

          current_result := case when is_match then 'MATCHED' else 'NOT_MATCHED' end;
        end if;
      end if;
    end if;

    if current_result = 'MATCHED' then
      result_matched_count := result_matched_count + 1;
    elsif current_result = 'INSUFFICIENT' then
      result_insufficient_count := result_insufficient_count + 1;
    end if;

    insert into public.activity_trigger_predicate_evaluations (
      farm_id, project_id, rule_run_id, trigger_predicate_id,
      predicate_sequence_no, source_field_code, comparison_operator,
      expected_numeric_value, expected_text_value, expected_boolean_value,
      expected_unit_code, observation_id, observation_stream_id,
      observed_numeric_value, observed_text_value, observed_boolean_value,
      observed_unit_code, observed_at, observation_quality_status,
      result_status, reason_code
    )
    values (
      target_farm_id,
      target_project_id,
      created_run.id,
      current_predicate.id,
      current_predicate.sequence_no,
      current_predicate.source_field_code,
      current_predicate.comparison_operator,
      current_predicate.numeric_value,
      current_predicate.text_value,
      current_predicate.boolean_value,
      current_predicate.unit_code,
      selected_observation.id,
      selected_observation.stream_id,
      selected_observation.numeric_value,
      selected_observation.text_value,
      selected_observation.boolean_value,
      selected_observed_unit,
      selected_observation.observed_at,
      selected_observation.quality_status,
      current_result,
      current_reason
    );
  end loop;

  update public.activity_trigger_evaluations as evaluation
  set matched_count = result_matched_count,
      insufficient_count = result_insufficient_count
  where evaluation.rule_run_id = created_run.id;

  should_propose := case current_rule.predicate_match_mode
    when 'ALL' then result_matched_count = predicate_count
    when 'ANY' then result_matched_count > 0
    else false
  end;

  if should_propose then
    insert into public.activity_proposals (
      farm_id, project_id, rule_run_id, proposal_key, template_id,
      template_version, wbs_id, calendar_id, cultivation_cycle_id,
      operation_type_code, activity_code, name, description, activity_type,
      percent_complete_type, planned_start_at, planned_finish_at,
      planned_duration_minutes, status, created_by, updated_by
    )
    values (
      target_farm_id,
      target_project_id,
      created_run.id,
      'trigger:' || current_rule.id::text
        || ':v' || current_rule.version::text
        || ':' || to_char(target_evaluated_at at time zone 'UTC', 'YYYYMMDDHH24MISSUS'),
      current_template.id,
      current_template.version,
      current_rule.wbs_id,
      current_rule.calendar_id,
      current_rule.cultivation_cycle_id,
      current_template.operation_type_code,
      current_rule.rule_code
        || '-TRG-'
        || to_char(target_evaluated_at at time zone 'UTC', 'YYYYMMDDHH24MISS')
        || '-' || substr(md5(target_evaluated_at::text), 1, 6),
      current_template.name,
      current_template.description,
      current_template.activity_type,
      current_template.percent_complete_type,
      target_evaluated_at,
      target_evaluated_at
        + make_interval(mins => current_template.default_duration_minutes),
      current_template.default_duration_minutes,
      'PROPOSED',
      auth.uid(),
      auth.uid()
    );

    insert into public.activity_proposal_work_areas (
      farm_id, project_id, proposal_id, work_area_id, is_primary
    )
    select
      target_farm_id,
      target_project_id,
      proposal.id,
      area.work_area_id,
      area.is_primary
    from public.activity_proposals as proposal
    cross join public.activity_trigger_rule_work_areas as area
    where proposal.rule_run_id = created_run.id
      and area.trigger_rule_id = current_rule.id;
  end if;

  update public.activity_rule_runs
  set status = case
        when should_propose then 'SUCCEEDED'
        when result_insufficient_count > 0 then 'SKIPPED'
        else 'SUCCEEDED'
      end,
      outcome_code = case
        when should_propose then 'PROPOSAL_CREATED'
        when result_insufficient_count > 0 then 'INSUFFICIENT_EVIDENCE'
        else 'PREDICATES_NOT_MATCHED'
      end,
      finished_at = now()
  where id = created_run.id
  returning * into created_run;

  return public.activity_trigger_evaluation_response(created_run.id);
end;
$$;

revoke execute on function public.validate_observation_stream_definition()
from public, anon, authenticated;

revoke execute on function public.stream_observation_response(uuid)
from public, anon, authenticated;

revoke execute on function public.activity_trigger_evaluation_response(uuid)
from public, anon, authenticated;

revoke execute on function public.create_observation_source(
  uuid, text, text, text, text, text
) from public, anon;

revoke execute on function public.create_observation_stream(
  uuid, uuid, text, text, text, uuid, integer, boolean
) from public, anon;

revoke execute on function public.record_observation_calibration(
  uuid, uuid, text, timestamptz, timestamptz, text, text, text
) from public, anon;

revoke execute on function public.record_stream_observation(
  uuid, uuid, timestamptz, text, numeric, text, boolean, timestamptz, text, text
) from public, anon;

revoke execute on function public.evaluate_activity_trigger_rule(
  uuid, uuid, uuid, integer, timestamptz, text
) from public, anon;

grant execute on function public.create_observation_source(
  uuid, text, text, text, text, text
) to authenticated;

grant execute on function public.create_observation_stream(
  uuid, uuid, text, text, text, uuid, integer, boolean
) to authenticated;

grant execute on function public.record_observation_calibration(
  uuid, uuid, text, timestamptz, timestamptz, text, text, text
) to authenticated;

grant execute on function public.record_stream_observation(
  uuid, uuid, timestamptz, text, numeric, text, boolean, timestamptz, text, text
) to authenticated;

grant execute on function public.evaluate_activity_trigger_rule(
  uuid, uuid, uuid, integer, timestamptz, text
) to authenticated;
