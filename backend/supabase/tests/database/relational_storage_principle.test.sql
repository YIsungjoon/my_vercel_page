begin;

create extension if not exists pgtap with schema extensions;

select extensions.plan(5);

select extensions.is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and data_type in ('json', 'jsonb')
  ),
  0,
  'public domain tables contain no JSON or JSONB persistence columns'
);

select extensions.has_table(
  'public',
  'chat_log_retrieved_documents',
  'retrieved chat evidence uses a relational child table'
);

select extensions.has_column(
  'public',
  'chat_log_retrieved_documents',
  'retrieval_rank',
  'retrieved evidence preserves ranking relationally'
);

select extensions.has_fk(
  'public',
  'chat_log_retrieved_documents',
  'retrieved evidence references its parent chat log'
);

select extensions.is(
  (
    select count(*)::integer
    from information_schema.columns
    where table_schema = 'public'
      and (
        (table_name = 'farm_work_areas' and column_name = 'properties')
        or (table_name = 'chat_logs' and column_name = 'retrieved_doc_ids')
        or (
          table_name = 'weather_observations'
          and column_name = 'source_payload'
        )
      )
  ),
  0,
  'legacy JSONB persistence columns are removed'
);

select * from extensions.finish();

rollback;
