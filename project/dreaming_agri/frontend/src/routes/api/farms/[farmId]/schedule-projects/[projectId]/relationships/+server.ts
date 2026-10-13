import { json } from '@sveltejs/kit';
import {
	integerOrDefault,
	isUuid,
	optionalText,
	requiredUuid
} from '$agri/server/apiValidation';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async ({ params, request, locals }) => {
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

	try {
		const body = await request.json();
		const relationshipType = optionalText(body.relationship_type) ?? 'FS';
		if (!['FS', 'SS', 'FF', 'SF'].includes(relationshipType)) {
			throw new Error('relationship_type is not supported.');
		}

		const { data, error } = await supabase.rpc('create_schedule_relationship', {
			target_farm_id: farmId,
			target_project_id: projectId,
			predecessor_id: requiredUuid(
				body.predecessor_activity_id,
				'predecessor_activity_id'
			),
			successor_id: requiredUuid(
				body.successor_activity_id,
				'successor_activity_id'
			),
			relationship_kind: relationshipType,
			relationship_lag_minutes: integerOrDefault(
				body.lag_minutes,
				0,
				'lag_minutes'
			)
		});

		if (error) {
			console.error('Schedule relationship creation failed:', error);
			return json({ error: 'Unable to create schedule relationship.' }, { status: 400 });
		}

		return json({ relationship: data }, { status: 201 });
	} catch (error) {
		return json(
			{
				error:
					error instanceof Error ? error.message : 'Invalid schedule relationship request.'
			},
			{ status: 400 }
		);
	}
};
