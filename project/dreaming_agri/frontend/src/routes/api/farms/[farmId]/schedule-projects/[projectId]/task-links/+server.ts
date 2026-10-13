import { json } from '@sveltejs/kit';
import {
	isUuid,
	optionalText,
	requiredUuid
} from '$lib/server/apiValidation';
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
		const linkType = optionalText(body.link_type) ?? 'REFERENCE';
		if (!['MIGRATED', 'EXECUTION', 'FOLLOW_UP', 'REFERENCE'].includes(linkType)) {
			throw new Error('link_type is not supported.');
		}

		const { data, error } = await supabase.rpc('link_task_to_activity', {
			target_farm_id: farmId,
			target_project_id: projectId,
			target_task_id: requiredUuid(body.task_id, 'task_id'),
			target_activity_id: requiredUuid(body.activity_id, 'activity_id'),
			target_link_type: linkType,
			target_is_primary: body.is_primary === true
		});

		if (error) {
			console.error('Task activity link creation failed:', error);
			return json({ error: 'Unable to link task and activity.' }, { status: 400 });
		}

		return json({ task_activity_link: data }, { status: 201 });
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid task activity link request.' },
			{ status: 400 }
		);
	}
};
