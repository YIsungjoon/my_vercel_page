import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

const TASK_FIELDS =
	'id, farm_id, cultivation_cycle_id, operation_type_code, title, description, scheduled_date, category, status, priority, is_followup, parent_task_id, created_at, updated_at, task_work_areas(work_area_id, is_primary)';

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

function optionalUuid(value: unknown, field: string) {
	const parsed = optionalText(value);
	if (parsed && !isUuid(parsed)) {
		throw new Error(field + ' must be a valid UUID.');
	}

	return parsed;
}

function optionalUuidArray(value: unknown, field: string) {
	if (value === undefined || value === null) {
		return [];
	}

	if (!Array.isArray(value)) {
		throw new Error(field + ' must be an array of UUIDs.');
	}

	return [
		...new Set(
			value.map((item) => {
				const parsed = requiredText(item, field);
				if (!isUuid(parsed)) {
					throw new Error(field + ' must contain valid UUIDs.');
				}
				return parsed;
			})
		)
	];
}

function normalizeTask(task: Record<string, unknown>) {
	const links = Array.isArray(task.task_work_areas)
		? (task.task_work_areas as Record<string, unknown>[])
		: [];
	const { task_work_areas: _links, ...fields } = task;

	return {
		...fields,
		work_area_ids: links
			.sort((left, right) => Number(right.is_primary === true) - Number(left.is_primary === true))
			.map((link) => link.work_area_id)
			.filter((id): id is string => typeof id === 'string')
	};
}

export const GET: RequestHandler = async ({ params, locals }) => {
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

	const { data, error } = await supabase
		.from('tasks')
		.select(TASK_FIELDS)
		.eq('farm_id', farmId)
		.order('scheduled_date', { ascending: true })
		.order('created_at', { ascending: true });

	if (error) {
		console.error('Task list query failed:', error);
		return json({ error: 'Unable to load tasks.' }, { status: 500 });
	}

	return json({
		tasks: (data ?? []).map((task) => normalizeTask(task as Record<string, unknown>))
	});
};

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
		const title = requiredText(body.title, 'title');
		const scheduledDate = requiredText(body.scheduled_date, 'scheduled_date');
		const category = requiredText(body.category, 'category');
		const priority = optionalText(body.priority) ?? 'medium';
		const description = optionalText(body.description);
		const parentTaskId = optionalUuid(body.parent_task_id, 'parent_task_id');
		const cultivationCycleId = optionalUuid(
			body.cultivation_cycle_id,
			'cultivation_cycle_id'
		);
		const operationTypeCode = optionalText(body.operation_type_code);
		const workAreaIds = optionalUuidArray(body.work_area_ids, 'work_area_ids');

		if (!['high', 'medium', 'low'].includes(priority)) {
			throw new Error('priority must be high, medium, or low.');
		}

		if (operationTypeCode && !/^[a-z][a-z0-9_]*$/.test(operationTypeCode)) {
			throw new Error('operation_type_code has an invalid format.');
		}

		const { data, error } = await supabase.rpc('create_farm_task', {
			target_farm_id: farmId,
			task_title: title,
			task_scheduled_date: scheduledDate,
			task_category: category,
			task_description: description,
			task_priority: priority,
			task_parent_task_id: parentTaskId,
			target_cycle_id: cultivationCycleId,
			target_operation_type_code: operationTypeCode,
			target_work_area_ids: workAreaIds,
			task_is_followup: body.is_followup === true
		});

		if (error) {
			console.error('Task creation failed:', error);
			return json({ error: 'Unable to create task.' }, { status: 400 });
		}

		return json({ task: data }, { status: 201 });
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid task request.' },
			{ status: 400 }
		);
	}
};
