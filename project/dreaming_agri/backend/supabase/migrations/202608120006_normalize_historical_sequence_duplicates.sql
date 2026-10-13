-- Keep duplicate classification correct when an older sequence value is replayed.

create or replace function public.normalize_historical_sequence_duplicate_receipt()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.sequence_policy = 'MONOTONIC_INTEGER'
     and new.sequence_status = 'OUT_OF_ORDER'
     and exists (
       select 1
       from public.observation_transport_quality_receipts as prior_receipt
       where prior_receipt.stream_id = new.stream_id
         and prior_receipt.source_sequence_value = new.source_sequence_value
     ) then
    new.sequence_status := 'DUPLICATE';
  end if;

  return new;
end;
$$;

create trigger normalize_historical_sequence_duplicate_receipt
before insert on public.observation_transport_quality_receipts
for each row execute function public.normalize_historical_sequence_duplicate_receipt();

create or replace function public.normalize_historical_sequence_duplicate_finding()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.finding_code = 'SOURCE_SEQUENCE_OUT_OF_ORDER'
     and exists (
       select 1
       from public.observation_transport_quality_receipts as receipt
       where receipt.observation_id = new.observation_id
         and receipt.sequence_status = 'DUPLICATE'
     ) then
    new.finding_code := 'SOURCE_SEQUENCE_DUPLICATE';
    new.detail := 'The source sequence was already processed by this stream.';
  end if;

  return new;
end;
$$;

create trigger normalize_historical_sequence_duplicate_finding
before insert on public.observation_quality_findings
for each row execute function public.normalize_historical_sequence_duplicate_finding();

revoke execute on function public.normalize_historical_sequence_duplicate_receipt()
from public, anon, authenticated, service_role;

revoke execute on function public.normalize_historical_sequence_duplicate_finding()
from public, anon, authenticated, service_role;
