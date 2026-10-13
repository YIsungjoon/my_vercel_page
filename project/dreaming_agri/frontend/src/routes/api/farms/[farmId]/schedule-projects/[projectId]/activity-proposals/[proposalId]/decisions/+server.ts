import { json } from '@sveltejs/kit';
import {
	isUuid,
	optionalText,
	requiredText
} from '$agri/server/apiValidation';
import {
	expectedVersion,
	isVersionConflict
} from '$agri/server/activityRuleValidation';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async ({ params, request, locals }) => {
	const farmId = params.farmId ?? '';
	const projectId = params.projectId ?? '';
	const proposalId = params.proposalId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) {
		return json({ error: 'Supabase is not configured.' }, { status: 503 });
	}
	if (!user) {
		return json({ error: 'Authentication is required.' }, { status: 401 });
	}
	if (!isUuid(farmId) || !isUuid(projectId) || !isUuid(proposalId)) {
		return json({ error: 'Invalid farm, project, or proposal id.' }, { status: 400 });
	}

	try {
		const body = await request.json();
		const decision = requiredText(body.decision, 'decision');
		if (!['APPROVED', 'REJECTED'].includes(decision)) {
			throw new Error('decision must be APPROVED or REJECTED.');
		}

		const { data, error } = await supabase.rpc('decide_activity_proposal', {
			target_farm_id: farmId,
			target_project_id: projectId,
			target_proposal_id: proposalId,
			expected_version: expectedVersion(body.expected_version),
			proposal_decision: decision,
			decision_reason_code: optionalText(body.reason_code),
			decision_note: optionalText(body.note)
		});

		if (error) {
			console.error('Activity proposal decision failed:', error);
			if (isVersionConflict(error)) {
				return json({ error: 'Activity proposal version conflict.' }, { status: 409 });
			}
			return json({ error: 'Unable to decide activity proposal.' }, { status: 400 });
		}

		return json(data);
	} catch (error) {
		return json(
			{
				error:
					error instanceof Error ? error.message : 'Invalid proposal decision request.'
			},
			{ status: 400 }
		);
	}
};
