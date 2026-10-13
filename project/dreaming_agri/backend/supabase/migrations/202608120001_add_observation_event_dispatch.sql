-- Phase 2D: observation outbox dispatch and service-actor trigger evaluation.

alter table public.activity_rule_runs
  add column execution_worker_id text,
  alter column created_by drop not null,
  add constraint activity_rule_runs_actor_check
    check (num_nonnulls(created_by, execution_worker_id) = 1),
  add constraint activity_rule_runs_worker_check
    check (
      execution_worker_id is null
      or char_length(trim(execution_worker_id)) between 1 and 100
    );

alter table public.activity_proposals
  add column created_by_worker_id text,
  add column updated_by_worker_id text,
  alter column created_by drop not null;

update public.activity_proposals
set updated_by = created_by
where updated_by is null;

alter table public.activity_proposals
  add constraint activity_proposals_created_actor_check
    check (num_nonnulls(created_by, created_by_worker_id) = 1),
  add constraint activity_proposals_updated_actor_check
    check (num_nonnulls(updated_by, updated_by_worker_id) = 1),
  add constraint activity_proposals_created_worker_check
    check (
      created_by_worker_id is null
      or char_length(trim(created_by_worker_id)) between 1 and 100
    ),
  add constraint activity_proposals_updated_worker_check
    check (
      updated_by_worker_id is null
      or char_length(trim(updated_by_worker_id)) between 1 and 100
    );

create or replace function public.normalize_activity_proposal_update_actor()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.updated_by is distinct from old.updated_by
     and new.updated_by is not null then
    new.updated_by_worker_id := null;
  elsif new.updated_by_worker_id is distinct from old.updated_by_worker_id
        and new.updated_by_worker_id is not null then
    new.updated_by := null;
  end if;

  return new;
end;
$$;

create trigger normalize_activity_proposal_update_actor
before update of updated_by, updated_by_worker_id
on public.activity_proposals
for each row execute function public.normalize_activity_proposal_update_actor();

alter table public.outbox_messages
  add constraint outbox_messages_farm_event_id_id_key
  unique (farm_id, event_id, id);

create table public.observation_event_consumptions (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  event_id uuid not null,
  outbox_message_id uuid not null,
  worker_id text not null,
  status text not null default 'PROCESSING',
  matching_rule_count integer not null default 0,
  evaluated_rule_count integer not null default 0,
  reused_rule_count integer not null default 0,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  constraint observation_event_consumptions_event_key unique (event_id),
  constraint observation_event_consumptions_message_key unique (outbox_message_id),
  constraint observation_event_consumptions_farm_event_id_key
    unique (farm_id, event_id, id),
  constraint observation_event_consumptions_event_same_farm_fkey
    foreign key (farm_id, event_id)
    references public.domain_events(farm_id, id)
    on delete restrict,
  constraint observation_event_consumptions_message_same_event_fkey
    foreign key (farm_id, event_id, outbox_message_id)
    references public.outbox_messages(farm_id, event_id, id)
    on delete restrict,
  constraint observation_event_consumptions_worker_check
    check (char_length(trim(worker_id)) between 1 and 100),
  constraint observation_event_consumptions_status_check
    check (status in ('PROCESSING', 'COMPLETED')),
  constraint observation_event_consumptions_counts_check
    check (
      matching_rule_count >= 0
      and evaluated_rule_count >= 0
      and reused_rule_count >= 0
      and evaluated_rule_count + reused_rule_count <= matching_rule_count
    ),
  constraint observation_event_consumptions_finish_check
    check (
      (status = 'PROCESSING' and finished_at is null)
      or (status = 'COMPLETED' and finished_at is not null)
    )
);

create table public.observation_event_rule_consumptions (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  event_id uuid not null,
  consumption_id uuid not null,
  project_id uuid not null,
  trigger_rule_id uuid not null,
  source_rule_version integer not null,
  rule_run_id uuid not null,
  dispatch_status text not null,
  created_at timestamptz not null default now(),
  constraint observation_event_rule_consumptions_rule_key
    unique (consumption_id, trigger_rule_id),
  constraint observation_event_rule_consumptions_consumption_same_event_fkey
    foreign key (farm_id, event_id, consumption_id)
    references public.observation_event_consumptions(farm_id, event_id, id)
    on delete cascade,
  constraint observation_event_rule_consumptions_rule_same_project_fkey
    foreign key (farm_id, project_id, trigger_rule_id)
    references public.activity_trigger_rules(farm_id, project_id, id)
    on delete restrict,
  constraint observation_event_rule_consumptions_run_same_project_fkey
    foreign key (farm_id, project_id, rule_run_id)
    references public.activity_rule_runs(farm_id, project_id, id)
    on delete restrict,
  constraint observation_event_rule_consumptions_version_check
    check (source_rule_version >= 1),
  constraint observation_event_rule_consumptions_status_check
    check (dispatch_status in ('EVALUATED', 'REUSED'))
);

create index observation_event_consumptions_farm_started_idx
on public.observation_event_consumptions(farm_id, started_at desc);

create index observation_event_rule_consumptions_run_idx
on public.observation_event_rule_consumptions(rule_run_id, event_id);

comment on table public.observation_event_consumptions is
  'One idempotent service-consumer receipt for an observation domain event.';

comment on table public.observation_event_rule_consumptions is
  'Rule-level links from an observation event to evaluated or reused trigger runs.';

create or replace function public.evaluate_activity_trigger_rule_internal(
  target_farm_id uuid,
  target_project_id uuid,
  target_rule_id uuid,
  expected_rule_version integer,
  target_evaluated_at timestamptz,
  run_idempotency_key text,
  actor_user_id uuid,
  actor_worker_id text
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
  if num_nonnulls(actor_user_id, nullif(trim(actor_worker_id), '')) <> 1 then
    raise exception 'Exactly one trigger evaluation actor is required';
  end if;

  if actor_user_id is not null and actor_user_id is distinct from auth.uid() then
    raise exception 'Trigger evaluation user does not match the authenticated user';
  end if;

  if actor_worker_id is not null and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role is required for worker trigger evaluation';
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
    idempotency_key, status, created_by, execution_worker_id
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
    actor_user_id,
    nullif(trim(actor_worker_id), '')
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
      planned_duration_minutes, status, created_by, updated_by,
      created_by_worker_id, updated_by_worker_id
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
      actor_user_id,
      actor_user_id,
      nullif(trim(actor_worker_id), ''),
      nullif(trim(actor_worker_id), '')
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
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to evaluate a trigger rule';
  end if;

  return public.evaluate_activity_trigger_rule_internal(
    target_farm_id,
    target_project_id,
    target_rule_id,
    expected_rule_version,
    target_evaluated_at,
    run_idempotency_key,
    auth.uid(),
    null
  );
end;
$$;

create or replace function public.observation_event_consumption_response(
  target_consumption_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_consumption public.observation_event_consumptions;
  selected_rules jsonb;
begin
  select * into selected_consumption
  from public.observation_event_consumptions
  where id = target_consumption_id;

  if not found then
    raise exception 'Observation event consumption was not found';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(rule_receipt) order by rule_receipt.created_at, rule_receipt.id),
    '[]'::jsonb
  ) into selected_rules
  from public.observation_event_rule_consumptions as rule_receipt
  where rule_receipt.consumption_id = target_consumption_id;

  return jsonb_build_object(
    'consumption', to_jsonb(selected_consumption),
    'rule_consumptions', selected_rules
  );
end;
$$;

create or replace function public.consume_observation_outbox_message(
  target_farm_id uuid,
  target_message_id uuid,
  worker_id text,
  attempt_no integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  selected_message record;
  existing_consumption public.observation_event_consumptions;
  created_consumption public.observation_event_consumptions;
  current_rule public.activity_trigger_rules;
  evaluation_result jsonb;
  selected_run_id uuid;
  run_already_existed boolean;
  run_key text;
  matching_count integer := 0;
  evaluated_count integer := 0;
  reused_count integer := 0;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role is required';
  end if;

  if nullif(trim(worker_id), '') is null or char_length(trim(worker_id)) > 100 then
    raise exception 'A valid observation consumer worker id is required';
  end if;

  if attempt_no < 1 then
    raise exception 'A valid outbox attempt number is required';
  end if;

  select
    message.id,
    message.farm_id,
    message.event_id,
    message.topic,
    message.status,
    message.attempt_count,
    message.locked_by,
    event.occurred_at,
    event.observation_event_type,
    stream.field_code
  into selected_message
  from public.outbox_messages as message
  join public.domain_events as event
    on event.farm_id = message.farm_id
   and event.id = message.event_id
  join public.observation_streams as stream
    on stream.farm_id = event.farm_id
   and stream.id = event.stream_id
  where message.farm_id = target_farm_id
    and message.id = target_message_id
  for update of message;

  if not found then
    raise exception 'Observation outbox message was not found for this farm';
  end if;

  if selected_message.topic <> 'observation.recorded.v1'
     or selected_message.status <> 'CLAIMED'
     or selected_message.locked_by <> trim(worker_id)
     or selected_message.attempt_count <> attempt_no then
    raise exception 'Observation outbox claim does not match this consumer request';
  end if;

  select * into existing_consumption
  from public.observation_event_consumptions
  where event_id = selected_message.event_id;

  if found then
    if existing_consumption.farm_id <> target_farm_id
       or existing_consumption.outbox_message_id <> target_message_id
       or existing_consumption.status <> 'COMPLETED' then
      raise exception 'Observation event consumption is not reusable';
    end if;

    return public.observation_event_consumption_response(existing_consumption.id);
  end if;

  insert into public.observation_event_consumptions (
    farm_id, event_id, outbox_message_id, worker_id
  ) values (
    target_farm_id,
    selected_message.event_id,
    target_message_id,
    trim(worker_id)
  )
  on conflict (event_id) do nothing
  returning * into created_consumption;

  if created_consumption.id is null then
    select * into existing_consumption
    from public.observation_event_consumptions
    where event_id = selected_message.event_id;

    if existing_consumption.status <> 'COMPLETED' then
      raise exception 'Observation event consumption is still processing';
    end if;

    return public.observation_event_consumption_response(existing_consumption.id);
  end if;

  select count(distinct rule.id)::integer into matching_count
  from public.activity_trigger_rules as rule
  join public.activity_trigger_predicates as predicate
    on predicate.farm_id = rule.farm_id
   and predicate.project_id = rule.project_id
   and predicate.trigger_rule_id = rule.id
  where rule.farm_id = target_farm_id
    and rule.status = 'ACTIVE'
    and rule.event_type = selected_message.observation_event_type
    and predicate.source_field_code = selected_message.field_code
    and (rule.valid_from is null or rule.valid_from <= selected_message.occurred_at)
    and (rule.valid_until is null or rule.valid_until >= selected_message.occurred_at);

  for current_rule in
    select distinct rule.*
    from public.activity_trigger_rules as rule
    join public.activity_trigger_predicates as predicate
      on predicate.farm_id = rule.farm_id
     and predicate.project_id = rule.project_id
     and predicate.trigger_rule_id = rule.id
    where rule.farm_id = target_farm_id
      and rule.status = 'ACTIVE'
      and rule.event_type = selected_message.observation_event_type
      and predicate.source_field_code = selected_message.field_code
      and (rule.valid_from is null or rule.valid_from <= selected_message.occurred_at)
      and (rule.valid_until is null or rule.valid_until >= selected_message.occurred_at)
    order by rule.project_id, rule.id
  loop
    run_key := 'obs:' || current_rule.id::text
      || ':v' || current_rule.version::text
      || ':' || to_char(
        selected_message.occurred_at at time zone 'UTC',
        'YYYYMMDDHH24MISSUS'
      );

    perform pg_advisory_xact_lock(
      hashtextextended(
        current_rule.id::text || ':' || current_rule.version::text
          || ':' || selected_message.occurred_at::text,
        0
      )
    );

    run_already_existed := exists (
      select 1
      from public.activity_rule_runs
      where project_id = current_rule.project_id
        and idempotency_key = run_key
    );

    evaluation_result := public.evaluate_activity_trigger_rule_internal(
      target_farm_id,
      current_rule.project_id,
      current_rule.id,
      current_rule.version,
      selected_message.occurred_at,
      run_key,
      null,
      trim(worker_id)
    );

    selected_run_id := (evaluation_result -> 'run' ->> 'id')::uuid;

    insert into public.observation_event_rule_consumptions (
      farm_id, event_id, consumption_id, project_id, trigger_rule_id,
      source_rule_version, rule_run_id, dispatch_status
    ) values (
      target_farm_id,
      selected_message.event_id,
      created_consumption.id,
      current_rule.project_id,
      current_rule.id,
      current_rule.version,
      selected_run_id,
      case when run_already_existed then 'REUSED' else 'EVALUATED' end
    );

    if run_already_existed then
      reused_count := reused_count + 1;
    else
      evaluated_count := evaluated_count + 1;
    end if;
  end loop;

  update public.observation_event_consumptions
  set status = 'COMPLETED',
      matching_rule_count = matching_count,
      evaluated_rule_count = evaluated_count,
      reused_rule_count = reused_count,
      finished_at = now()
  where id = created_consumption.id
  returning * into created_consumption;

  return public.observation_event_consumption_response(created_consumption.id);
end;
$$;

create or replace function public.claim_outbox_topic_messages(
  target_topic text,
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

  if nullif(trim(target_topic), '') is null
     or trim(target_topic) !~ '^[a-z][a-z0-9_.-]*$' then
    raise exception 'A valid outbox topic is required';
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
    where message.topic = trim(target_topic)
      and message.status = 'CLAIMED'
      and message.locked_at <= now() - make_interval(secs => lease_seconds)
    order by message.locked_at
    for update skip locked
  loop
    update public.outbox_delivery_attempts as delivery_attempt
    set status = 'FAILED',
        finished_at = now(),
        error_code = 'LEASE_EXPIRED',
        error_message = 'The outbox delivery lease expired before completion.'
    where delivery_attempt.message_id = expired_message.id
      and delivery_attempt.attempt_no = expired_message.attempt_count
      and delivery_attempt.status = 'CLAIMED';

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
    where message.topic = trim(target_topic)
      and message.status in ('PENDING', 'RETRY')
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
    'topic', trim(target_topic),
    'claimed_count', jsonb_array_length(claimed_messages),
    'messages', claimed_messages
  );
end;
$$;
