import { json } from '@sveltejs/kit';
import { isUuid, optionalText } from '$agri/server/apiValidation';
import { boundedInteger } from '$agri/server/observationValidation';
import type { RequestHandler } from './$types';

const CONSUMPTION_STATUSES = ['PROCESSING', 'COMPLETED'];

export const GET: RequestHandler = async ({ params, url, locals }) => {
	const farmId = params.farmId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) return json({ error: 'Supabase is not configured.' }, { status: 503 });
	if (!user) return json({ error: 'Authentication is required.' }, { status: 401 });
	if (!isUuid(farmId)) return json({ error: 'Invalid farm id.' }, { status: 400 });

	try {
		const status = optionalText(url.searchParams.get('status'));
		if (status && !CONSUMPTION_STATUSES.includes(status)) {
			throw new Error('status is not supported.');
		}
		const eventId = optionalText(url.searchParams.get('event_id'));
		if (eventId && !isUuid(eventId)) throw new Error('event_id must be a valid UUID.');
		const limit = boundedInteger(url.searchParams.get('limit'), 100, 'limit', 1, 500);

		let query = supabase
			.from('observation_event_consumptions')
			.select(
				'id, farm_id, event_id, outbox_message_id, worker_id, status, matching_rule_count, evaluated_rule_count, reused_rule_count, started_at, finished_at, created_at, observation_event_rule_consumptions(id, project_id, trigger_rule_id, source_rule_version, rule_run_id, dispatch_status, created_at)'
			)
			.eq('farm_id', farmId);

		if (status) query = query.eq('status', status);
		if (eventId) query = query.eq('event_id', eventId);

		const { data, error } = await query
			.order('started_at', { ascending: false })
			.limit(limit);

		if (error) {
			console.error('Observation event consumption list query failed:', error);
			return json({ error: 'Unable to load event consumptions.' }, { status: 500 });
		}

		return json({ event_consumptions: data ?? [] });
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid event consumption query.' },
			{ status: 400 }
		);
	}
};
