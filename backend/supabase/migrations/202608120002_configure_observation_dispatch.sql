-- Phase 2D dispatcher scheduling, RLS, and execution grants.

create or replace function public.configure_observation_dispatch(
  project_url text,
  dispatch_secret text,
  dispatch_schedule text default '* * * * *'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  project_url_secret_id uuid;
  dispatch_secret_id uuid;
begin
  if project_url !~ '^https://[a-z0-9]+\.supabase\.co$' then
    raise exception 'Invalid Supabase project URL';
  end if;

  if dispatch_secret is null or char_length(dispatch_secret) < 32 then
    raise exception 'An observation dispatch secret of at least 32 characters is required';
  end if;

  if nullif(trim(dispatch_schedule), '') is null
     or char_length(trim(dispatch_schedule)) > 100
     or dispatch_schedule ~ '[;\r\n]' then
    raise exception 'A valid pg_cron dispatch schedule is required';
  end if;

  select id into project_url_secret_id
  from vault.secrets
  where name = 'dreaming_agri_project_url';

  if project_url_secret_id is null then
    perform vault.create_secret(
      project_url,
      'dreaming_agri_project_url',
      'Dreaming Agri Edge Function base URL'
    );
  else
    perform vault.update_secret(
      project_url_secret_id,
      project_url,
      'dreaming_agri_project_url',
      'Dreaming Agri Edge Function base URL'
    );
  end if;

  select id into dispatch_secret_id
  from vault.secrets
  where name = 'dreaming_agri_observation_dispatch_secret';

  if dispatch_secret_id is null then
    perform vault.create_secret(
      dispatch_secret,
      'dreaming_agri_observation_dispatch_secret',
      'Random secret used only by the observation dispatcher cron job'
    );
  else
    perform vault.update_secret(
      dispatch_secret_id,
      dispatch_secret,
      'dreaming_agri_observation_dispatch_secret',
      'Random secret used only by the observation dispatcher cron job'
    );
  end if;

  perform cron.unschedule(jobid)
  from cron.job
  where jobname = 'dispatch-observation-events';

  perform cron.schedule(
    'dispatch-observation-events',
    trim(dispatch_schedule),
    $schedule$
      select net.http_post(
        url := (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'dreaming_agri_project_url'
        ) || '/functions/v1/dispatch-observation-events',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-observation-dispatch-secret', (
            select decrypted_secret
            from vault.decrypted_secrets
            where name = 'dreaming_agri_observation_dispatch_secret'
          )
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 30000
      ) as request_id;
    $schedule$
  );

  return (
    select jsonb_build_object(
      'job_id', jobid,
      'job_name', jobname,
      'schedule', schedule,
      'active', active
    )
    from cron.job
    where jobname = 'dispatch-observation-events'
  );
end;
$$;

alter table public.observation_event_consumptions enable row level security;
alter table public.observation_event_rule_consumptions enable row level security;

drop policy if exists managers_read_observation_event_consumptions
on public.observation_event_consumptions;
create policy managers_read_observation_event_consumptions
on public.observation_event_consumptions
for select to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']));

drop policy if exists managers_read_observation_event_rule_consumptions
on public.observation_event_rule_consumptions;
create policy managers_read_observation_event_rule_consumptions
on public.observation_event_rule_consumptions
for select to authenticated
using (public.has_farm_role(farm_id, array['owner', 'manager']));

grant select on table
  public.observation_event_consumptions,
  public.observation_event_rule_consumptions
to authenticated;

revoke all on table
  public.observation_event_consumptions,
  public.observation_event_rule_consumptions
from anon;

revoke insert, update, delete, truncate, trigger, references on table
  public.observation_event_consumptions,
  public.observation_event_rule_consumptions
from authenticated;

revoke execute on function public.normalize_activity_proposal_update_actor()
from public, anon, authenticated, service_role;

revoke execute on function public.evaluate_activity_trigger_rule_internal(
  uuid, uuid, uuid, integer, timestamptz, text, uuid, text
) from public, anon, authenticated, service_role;

revoke execute on function public.observation_event_consumption_response(uuid)
from public, anon, authenticated, service_role;

revoke execute on function public.consume_observation_outbox_message(
  uuid, uuid, text, integer
) from public, anon, authenticated;

revoke execute on function public.claim_outbox_topic_messages(
  text, text, integer, integer
) from public, anon, authenticated;

revoke execute on function public.configure_observation_dispatch(text, text, text)
from public, anon, authenticated;

revoke execute on function public.evaluate_activity_trigger_rule(
  uuid, uuid, uuid, integer, timestamptz, text
) from public, anon;

grant execute on function public.evaluate_activity_trigger_rule(
  uuid, uuid, uuid, integer, timestamptz, text
) to authenticated;

grant execute on function public.consume_observation_outbox_message(
  uuid, uuid, text, integer
) to service_role;

grant execute on function public.claim_outbox_topic_messages(
  text, text, integer, integer
) to service_role;

grant execute on function public.configure_observation_dispatch(text, text, text)
to service_role;

comment on function public.consume_observation_outbox_message(uuid, uuid, text, integer) is
  'Idempotently evaluates active trigger rules relevant to one claimed observation event.';

comment on function public.claim_outbox_topic_messages(text, text, integer, integer) is
  'Claims only due outbox messages for one dispatcher topic and recovers expired leases.';

comment on function public.configure_observation_dispatch(text, text, text) is
  'Stores the dispatcher cron secret in Vault and schedules observation event delivery.';
