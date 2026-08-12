import { createClient } from 'npm:@supabase/supabase-js@2.110.5';

const FARM_SLUG = Deno.env.get('WEATHER_FARM_SLUG') ?? 'gimje-demo-farm';
const AGENT_CODE = Deno.env.get('WEATHER_AGENT_CODE') ?? 'OPEN-METEO-COLLECTOR';
const SOURCE_CODE = Deno.env.get('WEATHER_SOURCE_CODE') ?? 'OPEN-METEO';
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

type CollectorConfiguration = {
	farm: {
		id: string;
		name: string;
		slug: string;
		latitude: number;
		longitude: number;
		timezone: string;
	};
	agent: { id: string; agent_code: string; agent_kind: string };
	source: { id: string; source_code: string; provider_code: string | null };
	streams: Array<{
		id: string;
		field_code: string;
		stream_code: string;
		unit_code: string | null;
	}>;
};

type IngestBatch = {
	id: string;
	status: 'OPEN' | 'COMPLETED' | 'PARTIAL' | 'FAILED';
	accepted_count: number;
	rejected_count: number;
};

const METRICS = [
	{ fieldCode: 'weather.temperature_c', responseKey: 'temperature_2m' },
	{ fieldCode: 'weather.humidity_pct', responseKey: 'relative_humidity_2m' },
	{ fieldCode: 'weather.precipitation_mm', responseKey: 'precipitation' },
	{ fieldCode: 'weather.rainfall_mm', responseKey: 'rain' },
	{ fieldCode: 'weather.weather_code', responseKey: 'weather_code' },
	{ fieldCode: 'weather.wind_speed_kph', responseKey: 'wind_speed_10m' },
	{ fieldCode: 'weather.wind_direction_deg', responseKey: 'wind_direction_10m' }
] as const;

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

function requireConfiguration(value: unknown): CollectorConfiguration {
	const configuration = value as CollectorConfiguration | null;

	if (
		!configuration?.farm?.id ||
		!configuration.agent?.id ||
		!configuration.source?.id ||
		!Array.isArray(configuration.streams)
	) {
		throw new Error('Collector configuration is incomplete.');
	}

	return configuration;
}

Deno.serve(async (request) => {
	if (request.method !== 'POST') {
		return Response.json({ error: 'Method not allowed' }, { status: 405 });
	}

	if (!hasValidCronSecret(request)) {
		return Response.json({ error: 'Unauthorized' }, { status: 401 });
	}

	let openedBatch: IngestBatch | null = null;
	let acceptedCount = 0;
	let supabase: ReturnType<typeof createClient> | null = null;
	let farmId: string | null = null;

	try {
		const supabaseUrl = Deno.env.get('SUPABASE_URL');
		const adminKey = getAdminKey();

		if (!supabaseUrl || !adminKey) {
			throw new Error('Supabase function environment is not configured.');
		}

		supabase = createClient(supabaseUrl, adminKey, {
			auth: { autoRefreshToken: false, persistSession: false }
		});

		const { data: configurationData, error: configurationError } = await supabase.rpc(
			'get_collection_agent_configuration',
			{
				target_farm_slug: FARM_SLUG,
				target_agent_code: AGENT_CODE,
				target_source_code: SOURCE_CODE
			}
		);

		if (configurationError) throw new Error(configurationError.message);

		const configuration = requireConfiguration(configurationData);
		farmId = configuration.farm.id;
		const streamByField = new Map(
			configuration.streams.map((stream) => [stream.field_code, stream])
		);

		for (const metric of METRICS) {
			if (!streamByField.has(metric.fieldCode)) {
				throw new Error(`Active stream for ${metric.fieldCode} is not configured.`);
			}
		}

		const weatherUrl = new URL(WEATHER_API_URL);
		weatherUrl.searchParams.set('latitude', String(configuration.farm.latitude));
		weatherUrl.searchParams.set('longitude', String(configuration.farm.longitude));
		weatherUrl.searchParams.set(
			'current',
			METRICS.map((metric) => metric.responseKey).join(',')
		);
		weatherUrl.searchParams.set('timezone', 'UTC');
		weatherUrl.searchParams.set('forecast_days', '1');

		const weatherResponse = await fetch(weatherUrl, {
			headers: { 'User-Agent': 'dreaming-agri/0.2 weather-collector' }
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

		const observedAtIso = observedAt.toISOString();
		const values = new Map<string, number>(
			METRICS.map((metric) => [
				metric.fieldCode,
				requireNumber(current[metric.responseKey], metric.responseKey)
			])
		);
		const batchExternalKey = `open-meteo:${observedAtIso}`;
		const { data: batchData, error: batchError } = await supabase.rpc(
			'open_observation_ingest_batch',
			{
				target_farm_id: configuration.farm.id,
				target_agent_id: configuration.agent.id,
				target_source_id: configuration.source.id,
				batch_external_key: batchExternalKey,
				batch_expected_count: METRICS.length
			}
		);

		if (batchError) throw new Error(batchError.message);
		openedBatch = batchData as IngestBatch;

		const recordedObservations: unknown[] = [];
		for (const metric of METRICS) {
			const stream = streamByField.get(metric.fieldCode);
			if (!stream) throw new Error(`Stream for ${metric.fieldCode} disappeared.`);

			const { data, error } = await supabase.rpc('record_agent_stream_observation', {
				target_farm_id: configuration.farm.id,
				target_agent_id: configuration.agent.id,
				target_ingest_batch_id: openedBatch.id,
				target_stream_id: stream.id,
				observation_observed_at: observedAtIso,
				observation_idempotency_key: `open-meteo:${metric.fieldCode}:${observedAtIso}`,
				observation_numeric_value: values.get(metric.fieldCode),
				source_quality_status: 'VALID',
				source_sequence: `${observedAtIso}:${metric.fieldCode}`
			});

			if (error) throw new Error(error.message);
			acceptedCount += 1;
			recordedObservations.push(data);
		}

		const { data: completedBatch, error: completionError } = await supabase.rpc(
			'complete_observation_ingest_batch',
			{
				target_farm_id: configuration.farm.id,
				target_batch_id: openedBatch.id,
				completion_status: 'COMPLETED',
				batch_expected_count: METRICS.length,
				batch_rejected_count: 0
			}
		);

		if (completionError) throw new Error(completionError.message);

		const legacyObservation = {
			farm_id: configuration.farm.id,
			observed_at: observedAtIso,
			temperature_c: values.get('weather.temperature_c'),
			relative_humidity_pct: values.get('weather.humidity_pct'),
			precipitation_mm: values.get('weather.precipitation_mm'),
			rain_mm: values.get('weather.rainfall_mm'),
			weather_code: values.get('weather.weather_code'),
			wind_speed_kph: values.get('weather.wind_speed_kph'),
			wind_direction_deg: values.get('weather.wind_direction_deg'),
			source: 'open-meteo'
		};
		const { data: legacyData, error: legacyError } = await supabase
			.from('weather_observations')
			.upsert(legacyObservation, { onConflict: 'farm_id,observed_at,source' })
			.select('id, observed_at')
			.single();

		if (legacyError) {
			console.error('Legacy weather compatibility write failed:', legacyError);
		}

		return Response.json({
			farm: { id: configuration.farm.id, name: configuration.farm.name },
			batch: completedBatch,
			observations: recordedObservations,
			legacy_observation: legacyData ?? null
		});
	} catch (error) {
		console.error(error);

		if (supabase && farmId && openedBatch?.id) {
			const rejectedCount = METRICS.length - acceptedCount;
			const { error: completionError } = await supabase.rpc(
				'complete_observation_ingest_batch',
				{
					target_farm_id: farmId,
					target_batch_id: openedBatch.id,
					completion_status: acceptedCount === 0 ? 'FAILED' : 'PARTIAL',
					batch_expected_count: METRICS.length,
					batch_rejected_count: rejectedCount,
					batch_failure_code: 'COLLECTION_FAILED',
					batch_failure_message:
						error instanceof Error ? error.message : 'Unknown weather collection error.'
				}
			);

			if (completionError) {
				console.error('Ingest batch failure receipt could not be recorded:', completionError);
			}
		}

		return Response.json(
			{ error: error instanceof Error ? error.message : 'Unknown weather recording error.' },
			{ status: 500 }
		);
	}
});
