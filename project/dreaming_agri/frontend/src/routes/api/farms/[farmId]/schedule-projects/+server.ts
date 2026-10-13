import { json } from '@sveltejs/kit';
import {
	integerOrDefault,
	isUuid,
	optionalText,
	optionalTimestamp,
	optionalUuid,
	requiredText
} from '$agri/server/apiValidation';
import type { RequestHandler } from './$types';

const PROJECT_FIELDS =
	'id, farm_id, cultivation_cycle_id, project_code, name, description, status, planned_start_at, planned_finish_at, data_date, timezone, default_percent_complete_type, default_calendar_id, created_by, updated_by, version, created_at, updated_at';

function workingPeriods(value: unknown) {
	if (!Array.isArray(value) || value.length === 0) {
		throw new Error('working_periods must contain at least one period.');
	}

	return value.map((raw) => {
		if (!raw || typeof raw !== 'object') {
			throw new Error('Each working period must be an object.');
		}

		const period = raw as Record<string, unknown>;
		const weekday = integerOrDefault(period.weekday, -1, 'weekday');
		const startTime = requiredText(period.start_time, 'start_time');
		const endTime = requiredText(period.end_time, 'end_time');
		const timePattern = /^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/;

		if (weekday < 0 || weekday > 6) {
			throw new Error('weekday must be between 0 and 6.');
		}
		if (!timePattern.test(startTime) || !timePattern.test(endTime)) {
			throw new Error('Working period times must use HH:MM or HH:MM:SS.');
		}

		return {
			weekday,
			start_time: startTime,
			end_time: endTime
		};
	});
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
		.from('schedule_projects')
		.select(PROJECT_FIELDS)
		.eq('farm_id', farmId)
		.order('created_at', { ascending: false });

	if (error) {
		console.error('Schedule project list query failed:', error);
		return json({ error: 'Unable to load schedule projects.' }, { status: 500 });
	}

	return json({ projects: data ?? [] });
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
		const projectCode = requiredText(body.project_code, 'project_code');
		const projectName = requiredText(body.name, 'name');
		const status = optionalText(body.status) ?? 'PLANNED';
		const percentType =
			optionalText(body.default_percent_complete_type) ?? 'DURATION';
		const periods = workingPeriods(body.working_periods);
		let timezone = optionalText(body.timezone);

		if (!timezone) {
			const { data: farm, error: farmError } = await supabase
				.from('farms')
				.select('timezone')
				.eq('id', farmId)
				.single();
			if (farmError || !farm) {
				throw new Error('Unable to resolve the farm timezone.');
			}
			timezone = farm.timezone;
		}

		if (!['PLANNED', 'ACTIVE', 'COMPLETED', 'ON_HOLD', 'CANCELLED'].includes(status)) {
			throw new Error('status is not supported.');
		}
		if (!['DURATION', 'UNITS', 'PHYSICAL'].includes(percentType)) {
			throw new Error('default_percent_complete_type is not supported.');
		}

		const { data, error } = await supabase.rpc('create_schedule_project', {
			target_farm_id: farmId,
			target_cycle_id: optionalUuid(body.cultivation_cycle_id, 'cultivation_cycle_id'),
			project_code: projectCode,
			project_name: projectName,
			project_timezone: timezone,
			root_wbs_code: optionalText(body.root_wbs_code) ?? 'ROOT',
			root_wbs_name: optionalText(body.root_wbs_name) ?? projectName,
			calendar_code: optionalText(body.calendar_code) ?? 'DEFAULT',
			calendar_name: optionalText(body.calendar_name) ?? 'Project Calendar',
			calendar_working_periods: periods,
			project_description: optionalText(body.description),
			project_status: status,
			project_planned_start_at: optionalTimestamp(
				body.planned_start_at,
				'planned_start_at'
			),
			project_planned_finish_at: optionalTimestamp(
				body.planned_finish_at,
				'planned_finish_at'
			),
			project_data_date: optionalTimestamp(body.data_date, 'data_date'),
			project_percent_complete_type: percentType,
			calendar_minutes_per_day: integerOrDefault(
				body.minutes_per_day,
				480,
				'minutes_per_day'
			),
			calendar_minutes_per_week: integerOrDefault(
				body.minutes_per_week,
				2400,
				'minutes_per_week'
			)
		});

		if (error) {
			console.error('Schedule project creation failed:', error);
			return json({ error: 'Unable to create schedule project.' }, { status: 400 });
		}

		return json(data, { status: 201 });
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid schedule project request.' },
			{ status: 400 }
		);
	}
};
