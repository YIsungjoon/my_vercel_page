-- Enforce relational persistence for application-owned public schema data.
-- JSON remains an API transport format, not a domain storage model.

do $$
begin
  if exists (
    select 1
    from public.farm_work_areas
    where properties <> '{}'::jsonb
  ) then
    raise exception
      'farm_work_areas.properties contains data that requires an explicit relational migration';
  end if;
end;
$$;

alter table public.farm_work_areas
  drop constraint farm_work_areas_properties_object_check,
  drop column properties;

create table public.chat_log_retrieved_documents (
  chat_log_id uuid not null
    references public.chat_logs(id) on delete cascade,
  document_id text not null,
  retrieval_rank integer not null,
  created_at timestamptz not null default now(),
  primary key (chat_log_id, document_id),
  constraint chat_log_retrieved_documents_rank_key
    unique (chat_log_id, retrieval_rank),
  constraint chat_log_retrieved_documents_rank_check
    check (retrieval_rank > 0),
  constraint chat_log_retrieved_documents_document_id_check
    check (char_length(trim(document_id)) > 0)
);

insert into public.chat_log_retrieved_documents (
  chat_log_id,
  document_id,
  retrieval_rank
)
select
  migrated.chat_log_id,
  migrated.document_id,
  migrated.retrieval_rank
from (
  select distinct on (log.id, document.document_id)
    log.id as chat_log_id,
    document.document_id,
    document.retrieval_rank::integer
  from public.chat_logs as log
  cross join lateral jsonb_array_elements_text(
    coalesce(log.retrieved_doc_ids, '[]'::jsonb)
  ) with ordinality as document(document_id, retrieval_rank)
  order by log.id, document.document_id, document.retrieval_rank
) as migrated;

alter table public.chat_logs
  drop column retrieved_doc_ids;

alter table public.weather_observations
  drop column source_payload;

alter table public.chat_log_retrieved_documents enable row level security;

create policy members_read_chat_retrieved_documents
on public.chat_log_retrieved_documents
for select to authenticated
using (
  exists (
    select 1
    from public.chat_logs as log
    where log.id = chat_log_id
      and log.farm_id is not null
      and public.is_farm_member(log.farm_id)
  )
);

create policy members_write_chat_retrieved_documents
on public.chat_log_retrieved_documents
for insert to authenticated
with check (
  exists (
    select 1
    from public.chat_logs as log
    where log.id = chat_log_id
      and log.farm_id is not null
      and public.is_farm_member(log.farm_id)
  )
);

grant select, insert on public.chat_log_retrieved_documents to authenticated;
revoke all on public.chat_log_retrieved_documents from anon;
revoke update, delete, truncate, trigger, references
on public.chat_log_retrieved_documents
from authenticated;

comment on table public.chat_log_retrieved_documents is
  'Ranked relational evidence documents retrieved for a chat log.';

comment on column public.weather_observations.source is
  'Stable source identifier. Raw provider payloads are not persisted in the relational database.';
