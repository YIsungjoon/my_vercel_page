import { json } from '@sveltejs/kit';
import { isUuid, optionalText } from '$lib/server/apiValidation';
import { boundedInteger } from '$lib/server/observationValidation';
import type { RequestHandler } from './$types';

const OBSERVATION_EVENT_TYPES = ['WEATHER_OBSERVATION', 'SENSOR_OBSERVATION'];

export const GET: RequestHandler = async ({ params, url, locals }) => {
	const farmId = params.farmId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) return json({ error: 'Supabase is not configured.' }, { status: 503 });
	if (!user) return json({ error: 'Authentication is required.' }, { status: 401 });
	if (!isUuid(farmId)) return json({ error: 'Invalid farm id.' }, { status: 400 });

	try {
		const eventType = optionalText(url.searchParams.get('observation_event_type'));
		if (eventType && !OBSERVATION_EVENT_TYPES.includes(eventType)) {
			throw new Error('observation_event_type is not supported.');
		}
		const limit = boundedInteger(url.searchParams.get('limit'), 100, 'limit', 1, 500);
		let query = supabase
			.from('domain_events')
			.select(
				'id, farm_id, source_id, stream_id, observation_id, collector_agent_id, ingest_batch_id, event_name, observation_event_type, occurred_at, recorded_at'
			)
			.eq('farm_id', farmId);

		if (eventType) query = query.eq('observation_event_type', eventType);
		const { data, error } = await query
			.order('occurred_at', { ascending: false })
			.limit(limit);

		if (error) {
			console.error('Domain event list query failed:', error);
			return json({ error: 'Unable to load domain events.' }, { status: 500 });
		}

		return json({ domain_events: data ?? [] });
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid domain event query.' },
			{ status: 400 }
		);
	}
};
