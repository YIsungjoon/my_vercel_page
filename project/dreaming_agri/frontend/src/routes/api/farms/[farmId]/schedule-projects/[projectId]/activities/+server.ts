import { json } from '@sveltejs/kit';
import {
	integerOrDefault,
	isUuid,
	optionalText,
	optionalTimestamp,
	optionalUuid,
	requiredText,
	requiredUuid,
	uuidArray
} from '$agri/server/apiValidation';
import type { RequestHandler } from './$types';

const ACTIVITY_TYPES = [
	'TASK_DEPENDENT',
	'RESOURCE_DEPENDENT',
	'LEVEL_OF_EFFORT',
	'START_MILESTONE',
	'FINISH_MILESTONE',
	'WBS_SUMMARY'
];
const PERCENT_TYPES = ['DURATION', 'UNITS', 'PHYSICAL'];
const CONSTRAINT_TYPES = [
	'START_ON',
	'START_ON_OR_AFTER',
	'FINISH_ON',
	'FINISH_ON_OR_BEFORE',
	'MANDATORY_START',
	'MANDATORY_FINISH'
];

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
		const activityType = optionalText(body.activity_type) ?? 'TASK_DEPENDENT';
		const percentType = optionalText(body.percent_complete_type) ?? 'DURATION';
		const constraintType = optionalText(body.primary_constraint_type);
		const constraintAt = optionalTimestamp(
			body.primary_constraint_at,
			'primary_constraint_at'
		);
		const duration = integerOrDefault(
			body.planned_duration_minutes,
			0,
			'planned_duration_minutes'
		);

		if (!ACTIVITY_TYPES.includes(activityType)) {
			throw new Error('activity_type is not supported.');
		}
		if (!PERCENT_TYPES.includes(percentType)) {
			throw new Error('percent_complete_type is not supported.');
		}
		if (constraintType && !CONSTRAINT_TYPES.includes(constraintType)) {
			throw new Error('primary_constraint_type is not supported.');
		}
		if (Boolean(constraintType) !== Boolean(constraintAt)) {
			throw new Error('Constraint type and timestamp must be provided together.');
		}
		if (duration < 0) {
			throw new Error('planned_duration_minutes must be non-negative.');
		}
		if (
			['START_MILESTONE', 'FINISH_MILESTONE'].includes(activityType) &&
			duration !== 0
		) {
			throw new Error('Milestone duration must be zero.');
		}

		const { data, error } = await supabase.rpc('create_schedule_activity', {
			target_farm_id: farmId,
			target_project_id: projectId,
			target_wbs_id: requiredUuid(body.wbs_id, 'wbs_id'),
			activity_code: requiredText(body.activity_code, 'activity_code'),
			activity_name: requiredText(body.name, 'name'),
			activity_type: activityType,
			target_calendar_id: optionalUuid(body.calendar_id, 'calendar_id'),
			target_cycle_id: optionalUuid(body.cultivation_cycle_id, 'cultivation_cycle_id'),
			target_operation_type_code: optionalText(body.operation_type_code) ?? 'other',
			activity_description: optionalText(body.description),
			activity_percent_complete_type: percentType,
			activity_planned_start_at: optionalTimestamp(
				body.planned_start_at,
				'planned_start_at'
			),
			activity_planned_finish_at: optionalTimestamp(
				body.planned_finish_at,
				'planned_finish_at'
			),
			activity_planned_duration_minutes: duration,
			activity_constraint_type: constraintType,
			activity_constraint_at: constraintAt,
			target_work_area_ids: uuidArray(body.work_area_ids, 'work_area_ids'),
			target_task_id: optionalUuid(body.task_id, 'task_id'),
			task_link_type: optionalText(body.task_link_type) ?? 'REFERENCE'
		});

		if (error) {
			console.error('Schedule activity creation failed:', error);
			return json({ error: 'Unable to create schedule activity.' }, { status: 400 });
		}

		return json({ activity: data }, { status: 201 });
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid schedule activity request.' },
			{ status: 400 }
		);
	}
};
