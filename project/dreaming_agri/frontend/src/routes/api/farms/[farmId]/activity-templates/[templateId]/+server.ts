import { json } from '@sveltejs/kit';
import {
	integerOrDefault,
	isUuid,
	optionalText,
	requiredText
} from '$agri/server/apiValidation';
import {
	ACTIVITY_TYPES,
	PERCENT_TYPES,
	expectedVersion,
	isVersionConflict
} from '$agri/server/activityRuleValidation';
import type { RequestHandler } from './$types';

const TEMPLATE_FIELDS =
	'id, farm_id, template_code, name, description, operation_type_code, activity_type, percent_complete_type, default_duration_minutes, is_active, created_by, updated_by, version, created_at, updated_at';

export const PATCH: RequestHandler = async ({ params, request, locals }) => {
	const farmId = params.farmId ?? '';
	const templateId = params.templateId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) {
		return json({ error: 'Supabase is not configured.' }, { status: 503 });
	}
	if (!user) {
		return json({ error: 'Authentication is required.' }, { status: 401 });
	}
	if (!isUuid(farmId) || !isUuid(templateId)) {
		return json({ error: 'Invalid farm or template id.' }, { status: 400 });
	}

	try {
		const body = await request.json();
		const { data: current, error: currentError } = await supabase
			.from('activity_templates')
			.select(TEMPLATE_FIELDS)
			.eq('farm_id', farmId)
			.eq('id', templateId)
			.maybeSingle();

		if (currentError) {
			console.error('Activity template lookup failed:', currentError);
			return json({ error: 'Unable to load activity template.' }, { status: 500 });
		}
		if (!current) {
			return json({ error: 'Activity template was not found.' }, { status: 404 });
		}

		const activityType =
			body.activity_type === undefined
				? current.activity_type
				: requiredText(body.activity_type, 'activity_type');
		const percentType =
			body.percent_complete_type === undefined
				? current.percent_complete_type
				: requiredText(body.percent_complete_type, 'percent_complete_type');
		const duration =
			body.default_duration_minutes === undefined
				? current.default_duration_minutes
				: integerOrDefault(
						body.default_duration_minutes,
						0,
						'default_duration_minutes'
					);
		const isActive =
			body.is_active === undefined ? current.is_active : body.is_active;

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
		if (typeof isActive !== 'boolean') {
			throw new Error('is_active must be a boolean.');
		}

		const { data, error } = await supabase.rpc('update_activity_template', {
			target_farm_id: farmId,
			target_template_id: templateId,
			expected_version: expectedVersion(body.expected_version),
			template_code:
				body.template_code === undefined
					? current.template_code
					: requiredText(body.template_code, 'template_code'),
			template_name:
				body.name === undefined ? current.name : requiredText(body.name, 'name'),
			target_operation_type_code:
				body.operation_type_code === undefined
					? current.operation_type_code
					: requiredText(body.operation_type_code, 'operation_type_code'),
			template_activity_type: activityType,
			template_percent_complete_type: percentType,
			template_default_duration_minutes: duration,
			template_description:
				body.description === undefined
					? current.description
					: optionalText(body.description),
			template_is_active: isActive
		});

		if (error) {
			console.error('Activity template update failed:', error);
			if (isVersionConflict(error)) {
				return json({ error: 'Activity template version conflict.' }, { status: 409 });
			}
			return json({ error: 'Unable to update activity template.' }, { status: 400 });
		}

		return json({ template: data });
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

export const DELETE: RequestHandler = async ({ params, url, locals }) => {
	const farmId = params.farmId ?? '';
	const templateId = params.templateId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) {
		return json({ error: 'Supabase is not configured.' }, { status: 503 });
	}
	if (!user) {
		return json({ error: 'Authentication is required.' }, { status: 401 });
	}
	if (!isUuid(farmId) || !isUuid(templateId)) {
		return json({ error: 'Invalid farm or template id.' }, { status: 400 });
	}

	try {
		const { error } = await supabase.rpc('delete_activity_template', {
			target_farm_id: farmId,
			target_template_id: templateId,
			expected_version: expectedVersion(url.searchParams.get('expected_version'))
		});

		if (error) {
			console.error('Activity template deletion failed:', error);
			if (isVersionConflict(error)) {
				return json({ error: 'Activity template version conflict.' }, { status: 409 });
			}
			return json({ error: 'Unable to delete activity template.' }, { status: 400 });
		}

		return new Response(null, { status: 204 });
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
