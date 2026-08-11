-- Phase 1C: optimistic concurrency and controlled activity-rule lifecycle.

create or replace function public.validate_activity_rule_status_transition()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.status not in ('DRAFT', 'ACTIVE') then
      raise exception 'A new activity rule must be draft or active';
    end if;
    return new;
  end if;

  if old.status = 'ARCHIVED' then
    raise exception 'An archived activity rule is immutable';
  end if;

  if not (
    (old.status = 'DRAFT' and new.status in ('DRAFT', 'ACTIVE', 'ARCHIVED'))
    or (old.status = 'ACTIVE' and new.status in ('ACTIVE', 'PAUSED', 'ARCHIVED'))
    or (old.status = 'PAUSED' and new.status in ('PAUSED', 'ACTIVE', 'ARCHIVED'))
  ) then
    raise exception 'Activity rule status transition from % to % is not allowed',
      old.status,
      new.status;
  end if;

  return new;
end;
$$;

create trigger validate_recurrence_rule_status_transition
before insert or update of status on public.activity_recurrence_rules
for each row execute function public.validate_activity_rule_status_transition();

create trigger validate_trigger_rule_status_transition
before insert or update of status on public.activity_trigger_rules
for each row execute function public.validate_activity_rule_status_transition();

create or replace function public.validate_activity_model_version_increment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.version <> old.version + 1 then
    raise exception 'Activity model version must increase by exactly one';
  end if;

  return new;
end;
$$;

create trigger validate_activity_template_version_increment
before update on public.activity_templates
for each row execute function public.validate_activity_model_version_increment();

create trigger validate_recurrence_rule_version_increment
before update on public.activity_recurrence_rules
for each row execute function public.validate_activity_model_version_increment();

create trigger validate_trigger_rule_version_increment
before update on public.activity_trigger_rules
for each row execute function public.validate_activity_model_version_increment();

create or replace function public.validate_activity_template_deactivation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.is_active and not new.is_active and (
    exists (
      select 1
      from public.activity_recurrence_rules
      where template_id = old.id
        and status = 'ACTIVE'
    )
    or exists (
      select 1
      from public.activity_trigger_rules
      where template_id = old.id
        and status = 'ACTIVE'
    )
  ) then
    raise exception 'Pause or archive active rules before deactivating their template';
  end if;

  return new;
end;
$$;

create trigger validate_activity_template_deactivation
before update of is_active on public.activity_templates
for each row execute function public.validate_activity_template_deactivation();

create or replace function public.validate_activity_template_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.is_active then
    raise exception 'Deactivate an activity template before deleting it';
  end if;

  if exists (
    select 1 from public.activity_recurrence_rules where template_id = old.id
  ) or exists (
    select 1 from public.activity_trigger_rules where template_id = old.id
  ) then
    raise exception 'An activity template referenced by rules cannot be deleted';
  end if;

  return old;
end;
$$;

create trigger validate_activity_template_delete
before delete on public.activity_templates
for each row execute function public.validate_activity_template_delete();

create or replace function public.validate_draft_activity_rule_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status <> 'DRAFT' then
    raise exception 'Only draft activity rules can be deleted';
  end if;

  return old;
end;
$$;

create trigger validate_draft_recurrence_rule_delete
before delete on public.activity_recurrence_rules
for each row execute function public.validate_draft_activity_rule_delete();

create trigger validate_draft_trigger_rule_delete
before delete on public.activity_trigger_rules
for each row execute function public.validate_draft_activity_rule_delete();

revoke insert, update, delete on table
  public.activity_templates,
  public.activity_recurrence_rules,
  public.activity_recurrence_weekdays,
  public.activity_trigger_rules,
  public.activity_trigger_predicates,
  public.activity_trigger_rule_work_areas
from authenticated;

create or replace function public.update_activity_template(
  target_farm_id uuid,
  target_template_id uuid,
  expected_version integer,
  template_code text,
  template_name text,
  target_operation_type_code text,
  template_activity_type text,
  template_percent_complete_type text,
  template_default_duration_minutes integer,
  template_description text,
  template_is_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_template public.activity_templates;
  updated_template public.activity_templates;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to update an activity template';
  end if;

  select *
  into current_template
  from public.activity_templates
  where farm_id = target_farm_id
    and id = target_template_id
  for update;

  if not found then
    raise exception 'Activity template was not found for this farm';
  end if;

  if current_template.version <> expected_version then
    raise exception using
      errcode = '40001',
      message = 'Activity template version conflict';
  end if;

  if nullif(trim(template_code), '') is null
     or nullif(trim(template_name), '') is null then
    raise exception 'Template code and name are required';
  end if;

  if not exists (
    select 1
    from public.agri_operation_types
    where code = target_operation_type_code
      and is_active
  ) then
    raise exception 'Active agricultural operation type is required';
  end if;

  update public.activity_templates
  set template_code = trim(update_activity_template.template_code),
      name = trim(template_name),
      description = nullif(trim(template_description), ''),
      operation_type_code = target_operation_type_code,
      activity_type = template_activity_type,
      percent_complete_type = template_percent_complete_type,
      default_duration_minutes = template_default_duration_minutes,
      is_active = template_is_active,
      updated_by = auth.uid(),
      version = current_template.version + 1
  where id = current_template.id
  returning * into updated_template;

  return to_jsonb(updated_template);
end;
$$;

create or replace function public.delete_activity_template(
  target_farm_id uuid,
  target_template_id uuid,
  expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_template public.activity_templates;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to delete an activity template';
  end if;

  select *
  into current_template
  from public.activity_templates
  where farm_id = target_farm_id
    and id = target_template_id
  for update;

  if not found then
    raise exception 'Activity template was not found for this farm';
  end if;

  if current_template.version <> expected_version then
    raise exception using
      errcode = '40001',
      message = 'Activity template version conflict';
  end if;

  delete from public.activity_templates
  where id = current_template.id;

  return to_jsonb(current_template);
end;
$$;

create or replace function public.update_activity_recurrence_rule(
  target_farm_id uuid,
  target_project_id uuid,
  target_rule_id uuid,
  expected_version integer,
  target_template_id uuid,
  target_wbs_id uuid,
  rule_code text,
  rule_name text,
  recurrence_frequency text,
  recurrence_starts_on date,
  recurrence_occurrence_time time,
  target_calendar_id uuid,
  target_cycle_id uuid,
  rule_status text,
  recurrence_interval_count integer,
  recurrence_day_of_month smallint,
  recurrence_ends_on date,
  recurrence_timezone text,
  recurrence_weekdays smallint[],
  generation_horizon_days integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth, pg_catalog
as $$
declare
  current_rule public.activity_recurrence_rules;
  updated_rule public.activity_recurrence_rules;
  selected_timezone text;
  updated_weekdays jsonb;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to update a recurrence rule';
  end if;

  if not exists (
    select 1
    from public.schedule_projects
    where farm_id = target_farm_id
      and id = target_project_id
  ) then
    raise exception 'Schedule project was not found for this farm';
  end if;

  select *
  into current_rule
  from public.activity_recurrence_rules
  where farm_id = target_farm_id
    and project_id = target_project_id
    and id = target_rule_id
  for update;

  if not found then
    raise exception 'Recurrence rule was not found for this project';
  end if;

  if current_rule.version <> expected_version then
    raise exception using
      errcode = '40001',
      message = 'Recurrence rule version conflict';
  end if;

  if not exists (
    select 1
    from public.activity_templates
    where farm_id = target_farm_id
      and id = target_template_id
      and (is_active or rule_status <> 'ACTIVE')
  ) then
    raise exception 'An active rule requires an active template from this farm';
  end if;

  if not exists (
    select 1
    from public.schedule_wbs_nodes
    where farm_id = target_farm_id
      and project_id = target_project_id
      and id = target_wbs_id
  ) then
    raise exception 'WBS node was not found for this project';
  end if;

  if target_calendar_id is null or not exists (
    select 1
    from public.schedule_calendars
    where farm_id = target_farm_id
      and project_id = target_project_id
      and id = target_calendar_id
  ) then
    raise exception 'Calendar was not found for this project';
  end if;

  if target_cycle_id is not null and not exists (
    select 1
    from public.cultivation_cycles
    where farm_id = target_farm_id
      and id = target_cycle_id
  ) then
    raise exception 'Cultivation cycle was not found for this farm';
  end if;

  if nullif(trim(rule_code), '') is null or nullif(trim(rule_name), '') is null then
    raise exception 'Recurrence rule code and name are required';
  end if;

  if recurrence_frequency = 'WEEKLY'
     and cardinality(coalesce(recurrence_weekdays, array[]::smallint[])) = 0 then
    raise exception 'A weekly recurrence rule requires at least one weekday';
  end if;

  if recurrence_frequency <> 'WEEKLY'
     and cardinality(coalesce(recurrence_weekdays, array[]::smallint[])) > 0 then
    raise exception 'Weekdays are only accepted for weekly recurrence rules';
  end if;

  if recurrence_frequency = 'MONTHLY' and recurrence_day_of_month is null then
    raise exception 'A monthly recurrence rule requires a day of month';
  end if;

  if recurrence_frequency <> 'MONTHLY' and recurrence_day_of_month is not null then
    raise exception 'Day of month is only accepted for monthly recurrence rules';
  end if;

  selected_timezone := nullif(trim(recurrence_timezone), '');
  if selected_timezone is null or not exists (
    select 1
    from pg_catalog.pg_timezone_names
    where name = selected_timezone
  ) then
    raise exception 'A valid IANA recurrence timezone is required';
  end if;

  delete from public.activity_recurrence_weekdays
  where recurrence_rule_id = current_rule.id;

  update public.activity_recurrence_rules
  set template_id = target_template_id,
      wbs_id = target_wbs_id,
      calendar_id = target_calendar_id,
      cultivation_cycle_id = target_cycle_id,
      rule_code = trim(update_activity_recurrence_rule.rule_code),
      name = trim(rule_name),
      status = rule_status,
      frequency = recurrence_frequency,
      interval_count = recurrence_interval_count,
      day_of_month = recurrence_day_of_month,
      starts_on = recurrence_starts_on,
      ends_on = recurrence_ends_on,
      occurrence_time = recurrence_occurrence_time,
      timezone = selected_timezone,
      generation_horizon_days = update_activity_recurrence_rule.generation_horizon_days,
      updated_by = auth.uid(),
      version = current_rule.version + 1
  where id = current_rule.id
  returning * into updated_rule;

  insert into public.activity_recurrence_weekdays (
    farm_id,
    project_id,
    recurrence_rule_id,
    weekday
  )
  select
    target_farm_id,
    target_project_id,
    updated_rule.id,
    requested.weekday
  from (
    select distinct unnest(coalesce(recurrence_weekdays, array[]::smallint[])) as weekday
  ) as requested;

  select coalesce(
    jsonb_agg(weekday order by weekday),
    '[]'::jsonb
  )
  into updated_weekdays
  from public.activity_recurrence_weekdays
  where recurrence_rule_id = updated_rule.id;

  return to_jsonb(updated_rule) || jsonb_build_object('weekdays', updated_weekdays);
end;
$$;

create or replace function public.delete_activity_recurrence_rule(
  target_farm_id uuid,
  target_project_id uuid,
  target_rule_id uuid,
  expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_rule public.activity_recurrence_rules;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to delete a recurrence rule';
  end if;

  select *
  into current_rule
  from public.activity_recurrence_rules
  where farm_id = target_farm_id
    and project_id = target_project_id
    and id = target_rule_id
  for update;

  if not found then
    raise exception 'Recurrence rule was not found for this project';
  end if;

  if current_rule.version <> expected_version then
    raise exception using
      errcode = '40001',
      message = 'Recurrence rule version conflict';
  end if;

  delete from public.activity_recurrence_rules
  where id = current_rule.id;

  return to_jsonb(current_rule);
end;
$$;

create or replace function public.update_activity_trigger_rule(
  target_farm_id uuid,
  target_project_id uuid,
  target_rule_id uuid,
  expected_version integer,
  target_template_id uuid,
  target_wbs_id uuid,
  rule_code text,
  rule_name text,
  trigger_event_type text,
  target_calendar_id uuid,
  target_cycle_id uuid,
  rule_status text,
  predicate_match_mode text,
  cooldown_minutes integer,
  valid_from timestamptz,
  valid_until timestamptz,
  predicate_field_codes text[],
  predicate_operators text[],
  predicate_numeric_values numeric[],
  predicate_text_values text[],
  predicate_boolean_values boolean[],
  predicate_unit_codes text[],
  predicate_window_minutes integer[],
  target_work_area_ids uuid[]
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_rule public.activity_trigger_rules;
  updated_rule public.activity_trigger_rules;
  predicate_count integer;
  predicate_index integer;
  updated_predicates jsonb;
  linked_work_areas jsonb;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to update a trigger rule';
  end if;

  if not exists (
    select 1
    from public.schedule_projects
    where farm_id = target_farm_id
      and id = target_project_id
  ) then
    raise exception 'Schedule project was not found for this farm';
  end if;

  select *
  into current_rule
  from public.activity_trigger_rules
  where farm_id = target_farm_id
    and project_id = target_project_id
    and id = target_rule_id
  for update;

  if not found then
    raise exception 'Trigger rule was not found for this project';
  end if;

  if current_rule.version <> expected_version then
    raise exception using
      errcode = '40001',
      message = 'Trigger rule version conflict';
  end if;

  if not exists (
    select 1
    from public.activity_templates
    where farm_id = target_farm_id
      and id = target_template_id
      and (is_active or rule_status <> 'ACTIVE')
  ) then
    raise exception 'An active rule requires an active template from this farm';
  end if;

  if not exists (
    select 1
    from public.schedule_wbs_nodes
    where farm_id = target_farm_id
      and project_id = target_project_id
      and id = target_wbs_id
  ) then
    raise exception 'WBS node was not found for this project';
  end if;

  if target_calendar_id is null or not exists (
    select 1
    from public.schedule_calendars
    where farm_id = target_farm_id
      and project_id = target_project_id
      and id = target_calendar_id
  ) then
    raise exception 'Calendar was not found for this project';
  end if;

  if target_cycle_id is not null and not exists (
    select 1
    from public.cultivation_cycles
    where farm_id = target_farm_id
      and id = target_cycle_id
  ) then
    raise exception 'Cultivation cycle was not found for this farm';
  end if;

  if nullif(trim(rule_code), '') is null or nullif(trim(rule_name), '') is null then
    raise exception 'Trigger rule code and name are required';
  end if;

  predicate_count := cardinality(coalesce(predicate_field_codes, array[]::text[]));
  if cardinality(coalesce(predicate_operators, array[]::text[])) <> predicate_count
     or cardinality(coalesce(predicate_numeric_values, array[]::numeric[])) <> predicate_count
     or cardinality(coalesce(predicate_text_values, array[]::text[])) <> predicate_count
     or cardinality(coalesce(predicate_boolean_values, array[]::boolean[])) <> predicate_count
     or cardinality(coalesce(predicate_unit_codes, array[]::text[])) <> predicate_count
     or cardinality(coalesce(predicate_window_minutes, array[]::integer[])) <> predicate_count then
    raise exception 'All trigger predicate arrays must have the same length';
  end if;

  if rule_status = 'ACTIVE' and trigger_event_type <> 'MANUAL' and predicate_count = 0 then
    raise exception 'An active non-manual trigger rule requires a predicate';
  end if;

  if predicate_count > 0 then
    for predicate_index in
      select generate_subscripts(predicate_field_codes, 1)
    loop
      if num_nonnulls(
        predicate_numeric_values[predicate_index],
        predicate_text_values[predicate_index],
        predicate_boolean_values[predicate_index]
      ) <> 1 then
        raise exception 'Each trigger predicate requires exactly one typed comparison value';
      end if;
    end loop;
  end if;

  if exists (
    select 1
    from unnest(coalesce(target_work_area_ids, array[]::uuid[])) as requested(id)
    left join public.farm_work_areas as area
      on area.farm_id = target_farm_id
     and area.id = requested.id
     and area.is_active
    where area.id is null
  ) then
    raise exception 'An active work area was not found for this farm';
  end if;

  delete from public.activity_trigger_predicates
  where trigger_rule_id = current_rule.id;

  delete from public.activity_trigger_rule_work_areas
  where trigger_rule_id = current_rule.id;

  update public.activity_trigger_rules
  set template_id = target_template_id,
      wbs_id = target_wbs_id,
      calendar_id = target_calendar_id,
      cultivation_cycle_id = target_cycle_id,
      rule_code = trim(update_activity_trigger_rule.rule_code),
      name = trim(rule_name),
      status = rule_status,
      event_type = trigger_event_type,
      predicate_match_mode = update_activity_trigger_rule.predicate_match_mode,
      cooldown_minutes = update_activity_trigger_rule.cooldown_minutes,
      valid_from = update_activity_trigger_rule.valid_from,
      valid_until = update_activity_trigger_rule.valid_until,
      updated_by = auth.uid(),
      version = current_rule.version + 1
  where id = current_rule.id
  returning * into updated_rule;

  insert into public.activity_trigger_predicates (
    farm_id,
    project_id,
    trigger_rule_id,
    sequence_no,
    source_field_code,
    comparison_operator,
    numeric_value,
    text_value,
    boolean_value,
    unit_code,
    observation_window_minutes
  )
  select
    target_farm_id,
    target_project_id,
    updated_rule.id,
    subscripts.predicate_index,
    trim(predicate_field_codes[subscripts.predicate_index]),
    predicate_operators[subscripts.predicate_index],
    predicate_numeric_values[subscripts.predicate_index],
    nullif(trim(predicate_text_values[subscripts.predicate_index]), ''),
    predicate_boolean_values[subscripts.predicate_index],
    nullif(trim(predicate_unit_codes[subscripts.predicate_index]), ''),
    predicate_window_minutes[subscripts.predicate_index]
  from generate_subscripts(predicate_field_codes, 1) as subscripts(predicate_index);

  with requested as (
    select area_id, min(ordinality) as ordinality
    from unnest(coalesce(target_work_area_ids, array[]::uuid[]))
      with ordinality as areas(area_id, ordinality)
    group by area_id
  )
  insert into public.activity_trigger_rule_work_areas (
    farm_id,
    project_id,
    trigger_rule_id,
    work_area_id,
    is_primary
  )
  select
    target_farm_id,
    target_project_id,
    updated_rule.id,
    area_id,
    row_number() over (order by ordinality) = 1
  from requested;

  select coalesce(
    jsonb_agg(to_jsonb(predicate_row) order by predicate_row.sequence_no),
    '[]'::jsonb
  )
  into updated_predicates
  from public.activity_trigger_predicates as predicate_row
  where predicate_row.trigger_rule_id = updated_rule.id;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'work_area_id', link.work_area_id,
        'is_primary', link.is_primary
      )
      order by link.is_primary desc, link.created_at
    ),
    '[]'::jsonb
  )
  into linked_work_areas
  from public.activity_trigger_rule_work_areas as link
  where link.trigger_rule_id = updated_rule.id;

  return to_jsonb(updated_rule) || jsonb_build_object(
    'predicates', updated_predicates,
    'work_areas', linked_work_areas
  );
end;
$$;

create or replace function public.delete_activity_trigger_rule(
  target_farm_id uuid,
  target_project_id uuid,
  target_rule_id uuid,
  expected_version integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  current_rule public.activity_trigger_rules;
begin
  if not public.has_farm_role(target_farm_id, array['owner', 'manager']) then
    raise exception 'Manager permission is required to delete a trigger rule';
  end if;

  select *
  into current_rule
  from public.activity_trigger_rules
  where farm_id = target_farm_id
    and project_id = target_project_id
    and id = target_rule_id
  for update;

  if not found then
    raise exception 'Trigger rule was not found for this project';
  end if;

  if current_rule.version <> expected_version then
    raise exception using
      errcode = '40001',
      message = 'Trigger rule version conflict';
  end if;

  delete from public.activity_trigger_rules
  where id = current_rule.id;

  return to_jsonb(current_rule);
end;
$$;

revoke execute on function public.validate_activity_rule_status_transition()
from public, anon, authenticated;
revoke execute on function public.validate_activity_model_version_increment()
from public, anon, authenticated;
revoke execute on function public.validate_activity_template_deactivation()
from public, anon, authenticated;
revoke execute on function public.validate_activity_template_delete()
from public, anon, authenticated;
revoke execute on function public.validate_draft_activity_rule_delete()
from public, anon, authenticated;

revoke execute on function public.update_activity_template(
  uuid, uuid, integer, text, text, text, text, text, integer, text, boolean
) from public, anon;
revoke execute on function public.delete_activity_template(
  uuid, uuid, integer
) from public, anon;
revoke execute on function public.update_activity_recurrence_rule(
  uuid, uuid, uuid, integer, uuid, uuid, text, text, text, date, time,
  uuid, uuid, text, integer, smallint, date, text, smallint[], integer
) from public, anon;
revoke execute on function public.delete_activity_recurrence_rule(
  uuid, uuid, uuid, integer
) from public, anon;
revoke execute on function public.update_activity_trigger_rule(
  uuid, uuid, uuid, integer, uuid, uuid, text, text, text, uuid, uuid,
  text, text, integer, timestamptz, timestamptz, text[], text[], numeric[],
  text[], boolean[], text[], integer[], uuid[]
) from public, anon;
revoke execute on function public.delete_activity_trigger_rule(
  uuid, uuid, uuid, integer
) from public, anon;

grant execute on function public.update_activity_template(
  uuid, uuid, integer, text, text, text, text, text, integer, text, boolean
) to authenticated;
grant execute on function public.delete_activity_template(
  uuid, uuid, integer
) to authenticated;
grant execute on function public.update_activity_recurrence_rule(
  uuid, uuid, uuid, integer, uuid, uuid, text, text, text, date, time,
  uuid, uuid, text, integer, smallint, date, text, smallint[], integer
) to authenticated;
grant execute on function public.delete_activity_recurrence_rule(
  uuid, uuid, uuid, integer
) to authenticated;
grant execute on function public.update_activity_trigger_rule(
  uuid, uuid, uuid, integer, uuid, uuid, text, text, text, uuid, uuid,
  text, text, integer, timestamptz, timestamptz, text[], text[], numeric[],
  text[], boolean[], text[], integer[], uuid[]
) to authenticated;
grant execute on function public.delete_activity_trigger_rule(
  uuid, uuid, uuid, integer
) to authenticated;
