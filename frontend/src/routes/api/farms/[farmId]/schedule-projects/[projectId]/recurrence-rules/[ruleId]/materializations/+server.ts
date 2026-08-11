import { json } from '@sveltejs/kit';
import { isUuid, requiredText } from '$lib/server/apiValidation';
import {
	dateValue,
	expectedVersion,
	isVersionConflict
} from '$lib/server/activityRuleValidation';
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
		const body = await request.json();
		const { data, error } = await supabase.rpc(
			'materialize_activity_recurrence_rule',
			{
				target_farm_id: farmId,
				target_project_id: projectId,
				target_rule_id: ruleId,
				expected_rule_version: expectedVersion(body.expected_version),
				target_window_start: dateValue(
					body.window_start,
					'window_start',
					true
				),
				target_window_end: dateValue(body.window_end, 'window_end', true),
				run_idempotency_key: requiredText(
					body.idempotency_key,
					'idempotency_key'
				)
			}
		);

		if (error) {
			console.error('Recurrence materialization failed:', error);
			if (isVersionConflict(error)) {
				return json({ error: 'Recurrence rule version conflict.' }, { status: 409 });
			}
			return json({ error: 'Unable to materialize recurrence rule.' }, { status: 400 });
		}

		return json(data, { status: 201 });
	} catch (error) {
		return json(
			{
				error:
					error instanceof Error ? error.message : 'Invalid materialization request.'
			},
			{ status: 400 }
		);
	}
};
