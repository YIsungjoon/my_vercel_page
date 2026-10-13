create or replace function public.configure_weather_collection(
  project_url text,
  secret_key text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  project_url_secret_id uuid;
  api_key_secret_id uuid;
begin
  if project_url !~ '^https://[a-z0-9]+\.supabase\.co$' then
    raise exception 'Invalid Supabase project URL';
  end if;

  if secret_key is null or char_length(secret_key) < 32 then
    raise exception 'A weather cron secret of at least 32 characters is required';
  end if;

  select id
  into project_url_secret_id
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

  select id
  into api_key_secret_id
  from vault.secrets
  where name = 'dreaming_agri_weather_cron_secret';

  if api_key_secret_id is null then
    perform vault.create_secret(
      secret_key,
      'dreaming_agri_weather_cron_secret',
      'Random secret used only by the weather collection cron job'
    );
  else
    perform vault.update_secret(
      api_key_secret_id,
      secret_key,
      'dreaming_agri_weather_cron_secret',
      'Random secret used only by the weather collection cron job'
    );
  end if;

  perform cron.unschedule(jobid)
  from cron.job
  where jobname = 'record-weather-four-times-daily';

  perform cron.schedule(
    'record-weather-four-times-daily',
    '0 3,9,15,21 * * *',
    $schedule$
      select net.http_post(
        url := (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'dreaming_agri_project_url'
        ) || '/functions/v1/record-weather',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-weather-cron-secret', (
            select decrypted_secret
            from vault.decrypted_secrets
            where name = 'dreaming_agri_weather_cron_secret'
          )
        ),
        body := '{}'::jsonb,
        timeout_milliseconds := 10000
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
    where jobname = 'record-weather-four-times-daily'
  );
end;
$function$;

comment on function public.configure_weather_collection(text, text) is
'Stores a random weather cron secret in Vault and schedules collection at 00:00, 06:00, 12:00, and 18:00 Asia/Seoul.';
