import { json } from '@sveltejs/kit';
import { isUuid, requiredText } from '$agri/server/apiValidation';
import {
	expectedVersion,
	isVersionConflict
} from '$agri/server/activityRuleValidation';
import { requiredTimestamp } from '$agri/server/observationValidation';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async ({ params, request, locals }) => {
	const farmId = params.farmId ?? '';
	const projectId = params.projectId ?? '';
	const ruleId = params.ruleId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) {
		return json({ error: 'Supabase is not configured.' }, { status: 503 });
	}
	if (!user) {
		return json({ error: 'Authentication is required.' }, { status: 401 });
	}
	if (!isUuid(farmId) || !isUuid(projectId) || !isUuid(ruleId)) {
		return json({ error: 'Invalid farm, project, or rule id.' }, { status: 400 });
	}

	try {
		const body = (await request.json()) as Record<string, unknown>;
		const { data, error } = await supabase.rpc('evaluate_activity_trigger_rule', {
			target_farm_id: farmId,
			target_project_id: projectId,
			target_rule_id: ruleId,
			expected_rule_version: expectedVersion(body.expected_version),
			target_evaluated_at: requiredTimestamp(body.evaluated_at, 'evaluated_at'),
			run_idempotency_key: requiredText(body.idempotency_key, 'idempotency_key')
		});

		if (error) {
			console.error('Activity trigger evaluation failed:', error);
			if (isVersionConflict(error)) {
				return json({ error: 'Trigger rule version conflict.' }, { status: 409 });
			}
			return json({ error: 'Unable to evaluate trigger rule.' }, { status: 400 });
		}

		return json(data, { status: 201 });
	} catch (error) {
		return json(
			{
				error:
					error instanceof Error ? error.message : 'Invalid trigger evaluation request.'
			},
			{ status: 400 }
		);
	}
};
