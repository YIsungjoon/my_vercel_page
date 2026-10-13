import { json } from '@sveltejs/kit';
import {
	integerOrDefault,
	isUuid,
	optionalText,
	requiredText
} from '$lib/server/apiValidation';
import {
	ACTIVITY_TYPES,
	PERCENT_TYPES
} from '$lib/server/activityRuleValidation';
import type { RequestHandler } from './$types';

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
		.from('activity_templates')
		.select(
			'id, farm_id, template_code, name, description, operation_type_code, activity_type, percent_complete_type, default_duration_minutes, is_active, created_by, updated_by, version, created_at, updated_at'
		)
		.eq('farm_id', farmId)
		.order('template_code', { ascending: true });

	if (error) {
		console.error('Activity template list query failed:', error);
		return json({ error: 'Unable to load activity templates.' }, { status: 500 });
	}

	return json({ templates: data ?? [] });
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
		const activityType = optionalText(body.activity_type) ?? 'TASK_DEPENDENT';
		const percentType = optionalText(body.percent_complete_type) ?? 'DURATION';
		const duration = integerOrDefault(
			body.default_duration_minutes,
			0,
			'default_duration_minutes'
		);

		if (!ACTIVITY_TYPES.includes(activityType)) {
			throw new Error('activity_type is not supported.');
		}
		if (!PERCENT_TYPES.includes(percentType)) {
			throw new Error('percent_complete_type is not supported.');
		}
		if (duration < 0) {
			throw new Error('default_duration_minutes must be non-negative.');
		}
		if (
			['START_MILESTONE', 'FINISH_MILESTONE'].includes(activityType) &&
			duration !== 0
		) {
			throw new Error('Milestone duration must be zero.');
		}

		const { data, error } = await supabase.rpc('create_activity_template', {
			target_farm_id: farmId,
			template_code: requiredText(body.template_code, 'template_code'),
			template_name: requiredText(body.name, 'name'),
			target_operation_type_code:
				optionalText(body.operation_type_code) ?? 'other',
			template_activity_type: activityType,
			template_percent_complete_type: percentType,
			template_default_duration_minutes: duration,
			template_description: optionalText(body.description)
		});

		if (error) {
			console.error('Activity template creation failed:', error);
			return json({ error: 'Unable to create activity template.' }, { status: 400 });
		}

		return json({ template: data }, { status: 201 });
	} catch (error) {
		return json(
			{
				error:
					error instanceof Error ? error.message : 'Invalid activity template request.'
			},
			{ status: 400 }
		);
	}
};
