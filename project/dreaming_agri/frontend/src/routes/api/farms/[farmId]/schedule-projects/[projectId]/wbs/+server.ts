import { json } from '@sveltejs/kit';
import {
	integerOrDefault,
	isUuid,
	optionalText,
	requiredText,
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
		const { data, error } = await supabase.rpc('create_schedule_wbs_node', {
			target_farm_id: farmId,
			target_project_id: projectId,
			target_parent_id: requiredUuid(body.parent_id, 'parent_id'),
			node_code: requiredText(body.wbs_code, 'wbs_code'),
			node_name: requiredText(body.name, 'name'),
			node_description: optionalText(body.description),
			node_sequence: integerOrDefault(body.sequence_no, 0, 'sequence_no')
		});

		if (error) {
			console.error('WBS creation failed:', error);
			return json({ error: 'Unable to create WBS node.' }, { status: 400 });
		}

		return json({ wbs_node: data }, { status: 201 });
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid WBS request.' },
			{ status: 400 }
		);
	}
};
