import { json } from '@sveltejs/kit';
import { isUuid, optionalText } from '$lib/server/apiValidation';
import type { RequestHandler } from './$types';

const PROPOSAL_STATUSES = ['PROPOSED', 'APPROVED', 'REJECTED', 'APPLIED'];

export const GET: RequestHandler = async ({ params, url, locals }) => {
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

	const status = optionalText(url.searchParams.get('status'));
	if (status && !PROPOSAL_STATUSES.includes(status)) {
		return json({ error: 'status is not supported.' }, { status: 400 });
	}

	let query = supabase
		.from('activity_proposals')
		.select(
			'id, farm_id, project_id, rule_run_id, proposal_key, template_id, template_version, wbs_id, calendar_id, cultivation_cycle_id, operation_type_code, activity_code, name, description, activity_type, percent_complete_type, planned_start_at, planned_finish_at, planned_duration_minutes, status, version, created_by, updated_by, created_at, updated_at, activity_proposal_work_areas(work_area_id, is_primary), activity_proposal_decisions(id, decision, reason_code, note, decided_by, decided_at), activity_proposal_applications(id, activity_id, idempotency_key, applied_by, applied_at)'
		)
		.eq('farm_id', farmId)
		.eq('project_id', projectId);

	if (status) {
		query = query.eq('status', status);
	}

	const { data, error } = await query.order('planned_start_at', { ascending: true });

	if (error) {
		console.error('Activity proposal list query failed:', error);
		return json({ error: 'Unable to load activity proposals.' }, { status: 500 });
	}

	return json({ activity_proposals: data ?? [] });
};
