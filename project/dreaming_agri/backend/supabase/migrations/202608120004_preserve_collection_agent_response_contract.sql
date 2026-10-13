-- Preserve the Phase 2C collection agent response while adding lifecycle detail.

create or replace function public.collection_agent_management_response(target_agent_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_agent public.collection_agents;
  selected_sources jsonb;
  selected_authorized_source_ids jsonb;
  selected_credentials jsonb;
begin
  select * into selected_agent
  from public.collection_agents
  where id = target_agent_id;

  if not found then
    raise exception 'Collection agent was not found';
  end if;

  select coalesce(
    jsonb_agg(to_jsonb(grant_row) order by grant_row.status, grant_row.source_id),
    '[]'::jsonb
  ) into selected_sources
  from public.collection_agent_sources as grant_row
  where grant_row.agent_id = target_agent_id;

  select coalesce(
    jsonb_agg(grant_row.source_id order by grant_row.source_id),
    '[]'::jsonb
  ) into selected_authorized_source_ids
  from public.collection_agent_sources as grant_row
  where grant_row.agent_id = target_agent_id
    and grant_row.status = 'ACTIVE';

  select coalesce(
    jsonb_agg(to_jsonb(credential) order by credential.credential_version desc),
    '[]'::jsonb
  ) into selected_credentials
  from public.collection_agent_credentials as credential
  where credential.agent_id = target_agent_id;

  return jsonb_build_object(
    'agent', to_jsonb(selected_agent),
    'authorized_source_ids', selected_authorized_source_ids,
    'source_grants', selected_sources,
    'credentials', selected_credentials
  );
end;
$$;

revoke execute on function public.collection_agent_management_response(uuid)
from public, anon, authenticated, service_role;
