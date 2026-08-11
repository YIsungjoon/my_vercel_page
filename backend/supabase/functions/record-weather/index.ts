import { createClient } from 'npm:@supabase/supabase-js@2.110.5';

const FARM_SLUG = 'gimje-demo-farm';
const WEATHER_API_URL = 'https://api.open-meteo.com/v1/forecast';

type WeatherResponse = {
	current?: {
		time?: string;
		temperature_2m?: number;
		relative_humidity_2m?: number;
		precipitation?: number;
		rain?: number;
		weather_code?: number;
		wind_speed_10m?: number;
		wind_direction_10m?: number;
	};
};

function getAdminKey() {
	const secretKeys = Deno.env.get('SUPABASE_SECRET_KEYS');

	if (secretKeys) {
		const keys = JSON.parse(secretKeys) as Record<string, string>;
		const key = keys.default ?? Object.values(keys)[0];

		if (key) return key;
	}

	return Deno.env.get('SUPABASE_SECRET_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
}

function hasValidCronSecret(request: Request) {
	const expected = Deno.env.get('WEATHER_CRON_SECRET');
	const supplied = request.headers.get('x-weather-cron-secret');

	if (!expected || !supplied || expected.length !== supplied.length) return false;

	let difference = 0;

	for (let index = 0; index < expected.length; index += 1) {
		difference |= expected.charCodeAt(index) ^ supplied.charCodeAt(index);
	}

	return difference === 0;
}

function requireNumber(value: unknown, field: string) {
	if (typeof value !== 'number' || !Number.isFinite(value)) {
		throw new Error(`Open-Meteo response is missing ${field}.`);
	}

	return value;
}

Deno.serve(async (request) => {
	if (request.method !== 'POST') {
		return Response.json({ error: 'Method not allowed' }, { status: 405 });
	}

	if (!hasValidCronSecret(request)) {
		return Response.json({ error: 'Unauthorized' }, { status: 401 });
	}

	try {
		const supabaseUrl = Deno.env.get('SUPABASE_URL');
		const adminKey = getAdminKey();

		if (!supabaseUrl || !adminKey) {
			throw new Error('Supabase function environment is not configured.');
		}

		const supabase = createClient(supabaseUrl, adminKey, {
			auth: { autoRefreshToken: false, persistSession: false }
		});
		const { data: farm, error: farmError } = await supabase
			.from('farms')
			.select('id, name, latitude, longitude')
			.eq('slug', FARM_SLUG)
			.single();

		if (farmError || !farm) {
			throw new Error(farmError?.message ?? `Farm ${FARM_SLUG} was not found.`);
		}

		const weatherUrl = new URL(WEATHER_API_URL);
		weatherUrl.searchParams.set('latitude', String(farm.latitude));
		weatherUrl.searchParams.set('longitude', String(farm.longitude));
		weatherUrl.searchParams.set(
			'current',
			[
				'temperature_2m',
				'relative_humidity_2m',
				'precipitation',
				'rain',
				'weather_code',
				'wind_speed_10m',
				'wind_direction_10m'
			].join(',')
		);
		weatherUrl.searchParams.set('timezone', 'UTC');
		weatherUrl.searchParams.set('forecast_days', '1');

		const weatherResponse = await fetch(weatherUrl, {
			headers: { 'User-Agent': 'dreaming-agri/0.1 weather-recorder' }
		});

		if (!weatherResponse.ok) {
			throw new Error(`Open-Meteo request failed with status ${weatherResponse.status}.`);
		}

		const weather = (await weatherResponse.json()) as WeatherResponse;
		const current = weather.current;

		if (!current?.time) {
			throw new Error('Open-Meteo response is missing the observation time.');
		}

		const observedAt = new Date(current.time.endsWith('Z') ? current.time : `${current.time}Z`);

		if (Number.isNaN(observedAt.getTime())) {
			throw new Error('Open-Meteo returned an invalid observation time.');
		}

		const observation = {
			farm_id: farm.id,
			observed_at: observedAt.toISOString(),
			temperature_c: requireNumber(current.temperature_2m, 'temperature_2m'),
			relative_humidity_pct: requireNumber(
				current.relative_humidity_2m,
				'relative_humidity_2m'
			),
			precipitation_mm: requireNumber(current.precipitation, 'precipitation'),
			rain_mm: requireNumber(current.rain, 'rain'),
			weather_code: requireNumber(current.weather_code, 'weather_code'),
			wind_speed_kph: requireNumber(current.wind_speed_10m, 'wind_speed_10m'),
			wind_direction_deg: requireNumber(current.wind_direction_10m, 'wind_direction_10m'),
			source: 'open-meteo'
		};
		const { data, error } = await supabase
			.from('weather_observations')
			.upsert(observation, { onConflict: 'farm_id,observed_at,source' })
			.select(
				'id, observed_at, temperature_c, relative_humidity_pct, precipitation_mm, weather_code, wind_speed_kph'
			)
			.single();

		if (error) throw new Error(error.message);

		return Response.json({ farm: { id: farm.id, name: farm.name }, observation: data });
	} catch (error) {
		console.error(error);

		return Response.json(
			{ error: error instanceof Error ? error.message : 'Unknown weather recording error.' },
			{ status: 500 }
		);
	}
});
