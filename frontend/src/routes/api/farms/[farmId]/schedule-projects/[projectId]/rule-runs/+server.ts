import { json } from '@sveltejs/kit';
import { isUuid } from '$lib/server/apiValidation';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ params, locals }) => {
	const farmId = params.farmId ?? '';
	const projectId = params.projectId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) {
		return json({ error: 'Supabase is not configured.' }, { status: 503 });
	}
	if (!user) {
		return json({ error: 'Authentication is required.' }, { status: 401 });
	}
	if (!isUuid(farmId) || !isUuid(projectId)) {
		return json({ error: 'Invalid farm or project id.' }, { status: 400 });
	}

	const { data, error } = await supabase
		.from('activity_rule_runs')
		.select(
			'id, farm_id, project_id, run_kind, recurrence_rule_id, trigger_rule_id, source_rule_version, source_template_version, idempotency_key, window_start_date, window_end_date, status, outcome_code, started_at, finished_at, created_by, created_at, activity_trigger_evaluations(evaluated_at, event_type, match_mode, predicate_count, matched_count, insufficient_count), activity_proposals(id, proposal_key, activity_code, name, planned_start_at, planned_finish_at, status, version)'
		)
		.eq('farm_id', farmId)
		.eq('project_id', projectId)
		.order('created_at', { ascending: false });

	if (error) {
		console.error('Activity rule run list query failed:', error);
		return json({ error: 'Unable to load activity rule runs.' }, { status: 500 });
	}

	return json({ rule_runs: data ?? [] });
};
