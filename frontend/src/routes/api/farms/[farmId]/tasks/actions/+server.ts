import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

function requiredText(value: unknown, field: string) {
	if (typeof value !== 'string' || !value.trim()) {
		throw new Error(field + ' is required.');
	}

	return value.trim();
}

function optionalText(value: unknown) {
	return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function isUuid(value: string) {
	return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

export const POST: RequestHandler = async ({ params, request, locals }) => {
	const farmId = params.farmId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) {
		return json({ error: 'Supabase is not configured.' }, { status: 503 });
	}

	if (!user) {
		return json({ error: 'Authentication is required.' }, { status: 401 });
	}

	if (!isUuid(farmId)) {
		return json({ error: 'Invalid farm id.' }, { status: 400 });
	}

	try {
		const body = await request.json();
		const taskId = requiredText(body.task_id, 'task_id');

		if (!isUuid(taskId)) {
			throw new Error('Invalid task id.');
		}

		if (!['completed', 'skipped', 'issue'].includes(body.action)) {
			throw new Error('Invalid task action.');
		}

		const { data, error } = await supabase.rpc('record_task_action', {
			target_farm_id: farmId,
			target_task_id: taskId,
			action_name: body.action,
			action_note: optionalText(body.note) ?? '',
			action_photo_url: optionalText(body.photo_url),
			action_issue_category: optionalText(body.issue_category),
			create_followup: body.create_followup === true,
			followup_title: optionalText(body.followup_title),
			followup_date: optionalText(body.followup_date)
		});

		if (error) {
			console.error('Task action RPC failed:', error);
			return json({ error: 'Unable to record task action.' }, { status: 400 });
		}

		return json(data);
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid task action request.' },
			{ status: 400 }
		);
	}
};