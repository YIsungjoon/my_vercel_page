create table public.countries (
  id bigint primary key generated always as identity,
  name text not null
);

insert into public.countries (name)
values
  ('Canada'),
  ('United States'),
  ('Mexico');

alter table public.countries enable row level security;

grant select on table public.countries to anon, authenticated;

create policy "public can read countries"
on public.countries
for select
to anon, authenticated
using (true);
