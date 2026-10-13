import { json } from '@sveltejs/kit';
import { isUuid, optionalText } from '$agri/server/apiValidation';
import { boundedInteger, INGEST_BATCH_STATUSES } from '$agri/server/observationValidation';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ params, url, locals }) => {
	const farmId = params.farmId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) return json({ error: 'Supabase is not configured.' }, { status: 503 });
	if (!user) return json({ error: 'Authentication is required.' }, { status: 401 });
	if (!isUuid(farmId)) return json({ error: 'Invalid farm id.' }, { status: 400 });

	try {
		const status = optionalText(url.searchParams.get('status'));
		if (status && !INGEST_BATCH_STATUSES.includes(status)) {
			throw new Error('status is not supported.');
		}
		const agentId = optionalText(url.searchParams.get('agent_id'));
		if (agentId && !isUuid(agentId)) throw new Error('agent_id must be a valid UUID.');
		const sourceId = optionalText(url.searchParams.get('source_id'));
		if (sourceId && !isUuid(sourceId)) throw new Error('source_id must be a valid UUID.');
		const limit = boundedInteger(url.searchParams.get('limit'), 100, 'limit', 1, 500);

		let query = supabase
			.from('observation_ingest_batches')
			.select(
				'id, farm_id, agent_id, source_id, external_batch_key, status, expected_count, accepted_count, rejected_count, failure_code, failure_message, started_at, finished_at, created_at, updated_at'
			)
			.eq('farm_id', farmId);

		if (status) query = query.eq('status', status);
		if (agentId) query = query.eq('agent_id', agentId);
		if (sourceId) query = query.eq('source_id', sourceId);

		const { data, error } = await query
			.order('started_at', { ascending: false })
			.limit(limit);

		if (error) {
			console.error('Ingest batch list query failed:', error);
			return json({ error: 'Unable to load ingest batches.' }, { status: 500 });
		}

		return json({ ingest_batches: data ?? [] });
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid ingest batch query.' },
			{ status: 400 }
		);
	}
};
