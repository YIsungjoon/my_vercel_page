import { json } from '@sveltejs/kit';
import { isUuid, optionalText } from '$lib/server/apiValidation';
import { boundedInteger, OUTBOX_MESSAGE_STATUSES } from '$lib/server/observationValidation';
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
		if (status && !OUTBOX_MESSAGE_STATUSES.includes(status)) {
			throw new Error('status is not supported.');
		}
		const limit = boundedInteger(url.searchParams.get('limit'), 100, 'limit', 1, 500);
		let query = supabase
			.from('outbox_messages')
			.select(
				'id, farm_id, event_id, topic, status, attempt_count, max_attempts, available_at, locked_at, locked_by, published_at, last_error_code, last_error_message, created_at, updated_at, outbox_delivery_attempts(id, attempt_no, worker_id, status, claimed_at, finished_at, error_code, error_message), outbox_dead_letters(final_attempt_no, reason_code, reason_message, dead_lettered_at)'
			)
			.eq('farm_id', farmId);

		if (status) query = query.eq('status', status);
		const { data, error } = await query
			.order('created_at', { ascending: false })
			.limit(limit);

		if (error) {
			console.error('Outbox message list query failed:', error);
			return json({ error: 'Unable to load outbox messages.' }, { status: 500 });
		}

		return json({ outbox_messages: data ?? [] });
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid outbox query.' },
			{ status: 400 }
		);
	}
};
