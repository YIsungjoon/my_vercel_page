-- Compatibility migration for the legacy summary weather schema.
-- The canonical detailed weather_observations table may already exist from
-- 202607220001_create_demo_farm_weather.sql.

CREATE TABLE IF NOT EXISTS public.weather_observations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    farm_id UUID REFERENCES public.farms(id) ON DELETE SET NULL,
    region TEXT NOT NULL,
    temperature NUMERIC(4, 1) NOT NULL,
    humidity NUMERIC(4, 1) NOT NULL,
    precipitation_probability NUMERIC(4, 1) DEFAULT 0,
    sky_condition TEXT DEFAULT 'sunny',
    warning_type TEXT DEFAULT 'none',
    warning_message TEXT,
    recommendation TEXT,
    observed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_weather_obs_farm_id ON public.weather_observations(farm_id);
CREATE INDEX IF NOT EXISTS idx_weather_obs_observed_at ON public.weather_observations(observed_at DESC);

ALTER TABLE public.weather_observations ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'weather_observations'
          AND column_name = 'region'
    ) THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_weather_obs_region ON public.weather_observations(region)';

        EXECUTE 'DROP POLICY IF EXISTS "Allow public select for weather_observations" ON public.weather_observations';
        EXECUTE 'CREATE POLICY "Allow public select for weather_observations" ON public.weather_observations FOR SELECT USING (true)';

        EXECUTE 'DROP POLICY IF EXISTS "Allow public insert for weather_observations" ON public.weather_observations';
        EXECUTE 'CREATE POLICY "Allow public insert for weather_observations" ON public.weather_observations FOR INSERT WITH CHECK (true)';
    END IF;
END
$$;