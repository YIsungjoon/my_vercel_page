create table public.farms (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  region text not null,
  country_code text not null check (char_length(country_code) = 2),
  latitude numeric(8, 5) not null check (latitude between -90 and 90),
  longitude numeric(8, 5) not null check (longitude between -180 and 180),
  timezone text not null,
  is_virtual boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.weather_observations (
  id uuid primary key default gen_random_uuid(),
  farm_id uuid not null references public.farms(id) on delete cascade,
  observed_at timestamptz not null,
  temperature_c numeric(5, 2) not null,
  relative_humidity_pct numeric(5, 2) not null check (
    relative_humidity_pct between 0 and 100
  ),
  precipitation_mm numeric(8, 2) not null check (precipitation_mm >= 0),
  rain_mm numeric(8, 2) not null check (rain_mm >= 0),
  weather_code smallint not null,
  wind_speed_kph numeric(6, 2) not null check (wind_speed_kph >= 0),
  wind_direction_deg numeric(5, 2) not null check (
    wind_direction_deg between 0 and 360
  ),
  source text not null default 'open-meteo',
  source_payload jsonb not null,
  recorded_at timestamptz not null default now(),
  unique (farm_id, observed_at, source)
);

create index weather_observations_farm_time_idx
on public.weather_observations (farm_id, observed_at desc);

comment on table public.farms is 'Farm locations used by the operations platform.';
comment on table public.weather_observations is 'Weather API observations recorded for a farm.';

alter table public.farms enable row level security;
alter table public.weather_observations enable row level security;

grant select on table public.farms to anon, authenticated;
grant select on table public.weather_observations to anon, authenticated;
grant select on table public.farms to service_role;
grant select, insert, update on table public.weather_observations to service_role;

create policy "public can read virtual farms"
on public.farms
for select
to anon, authenticated
using (is_virtual = true);

create policy "public can read virtual farm weather"
on public.weather_observations
for select
to anon, authenticated
using (
  exists (
    select 1
    from public.farms
    where farms.id = weather_observations.farm_id
      and farms.is_virtual = true
  )
);

insert into public.farms (
  slug,
  name,
  region,
  country_code,
  latitude,
  longitude,
  timezone,
  is_virtual
)
values (
  'gimje-demo-farm',
  '김제 가상농장',
  '전북특별자치도 김제시',
  'KR',
  35.80167,
  126.88889,
  'Asia/Seoul',
  true
);
