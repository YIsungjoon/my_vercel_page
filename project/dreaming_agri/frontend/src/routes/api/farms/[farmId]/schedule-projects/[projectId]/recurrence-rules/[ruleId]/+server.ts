import { json } from '@sveltejs/kit';
import {
	integerOrDefault,
	isUuid,
	optionalUuid,
	requiredText,
	requiredUuid
} from '$agri/server/apiValidation';
import {
	FREQUENCIES,
	RULE_STATUSES,
	dateValue,
	expectedVersion,
	isVersionConflict,
	timeValue,
	weekdayValues
} from '$agri/server/activityRuleValidation';
import type { RequestHandler } from './$types';

const RECURRENCE_FIELDS =
	'id, farm_id, project_id, template_id, wbs_id, calendar_id, cultivation_cycle_id, rule_code, name, status, frequency, interval_count, day_of_month, starts_on, ends_on, occurrence_time, timezone, generation_horizon_days, version, activity_recurrence_weekdays(weekday)';

export const PATCH: RequestHandler = async ({ params, request, locals }) => {
	const farmId = params.farmId ?? '';
	const projectId = params.projectId ?? '';
	const ruleId = params.ruleId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) {
		return json({ error: 'Supabase is not configured.' }, { status: 503 });
	}
	if (!user) {
		return json({ error: 'Authentication is required.' }, { status: 401 });
	}
	if (!isUuid(farmId) || !isUuid(projectId) || !isUuid(ruleId)) {
		return json({ error: 'Invalid farm, project, or rule id.' }, { status: 400 });
	}

	try {
		const body = await request.json();
		const { data: current, error: currentError } = await supabase
			.from('activity_recurrence_rules')
			.select(RECURRENCE_FIELDS)
			.eq('farm_id', farmId)
			.eq('project_id', projectId)
			.eq('id', ruleId)
			.maybeSingle();

		if (currentError) {
			console.error('Recurrence rule lookup failed:', currentError);
			return json({ error: 'Unable to load recurrence rule.' }, { status: 500 });
		}
		if (!current) {
			return json({ error: 'Recurrence rule was not found.' }, { status: 404 });
		}

		const status =
			body.status === undefined ? current.status : requiredText(body.status, 'status');
		const frequency =
			body.frequency === undefined
				? current.frequency
				: requiredText(body.frequency, 'frequency');
		const intervalCount =
			body.interval_count === undefined
				? current.interval_count
				: integerOrDefault(body.interval_count, 1, 'interval_count');
		const horizon =
			body.generation_horizon_days === undefined
				? current.generation_horizon_days
				: integerOrDefault(
						body.generation_horizon_days,
						30,
						'generation_horizon_days'
					);
		const dayOfMonth =
			body.day_of_month === undefined
				? current.day_of_month
				: body.day_of_month === null
					? null
					: integerOrDefault(body.day_of_month, 0, 'day_of_month');
		const weekdays =
			body.weekdays === undefined
				? (current.activity_recurrence_weekdays ?? []).map(
						(row: { weekday: number }) => row.weekday
					)
				: weekdayValues(body.weekdays);

		if (!RULE_STATUSES.includes(status)) {
			throw new Error('status is not supported.');
		}
		if (!FREQUENCIES.includes(frequency)) {
			throw new Error('frequency is not supported.');
		}
		if (intervalCount < 1) {
			throw new Error('interval_count must be at least 1.');
		}
		if (horizon < 1 || horizon > 366) {
			throw new Error('generation_horizon_days must be between 1 and 366.');
		}
		if (frequency === 'WEEKLY' && weekdays.length === 0) {
			throw new Error('A weekly recurrence rule requires at least one weekday.');
		}
		if (frequency !== 'WEEKLY' && weekdays.length > 0) {
			throw new Error('weekdays are only accepted for weekly recurrence rules.');
		}
		if (
			frequency === 'MONTHLY' &&
			(dayOfMonth === null || dayOfMonth < 1 || dayOfMonth > 31)
		) {
			throw new Error('A monthly recurrence rule requires day_of_month from 1 to 31.');
		}
		if (frequency !== 'MONTHLY' && dayOfMonth !== null) {
			throw new Error('day_of_month is only accepted for monthly recurrence rules.');
		}

		const { data, error } = await supabase.rpc('update_activity_recurrence_rule', {
			target_farm_id: farmId,
			target_project_id: projectId,
			target_rule_id: ruleId,
			expected_version: expectedVersion(body.expected_version),
			target_template_id:
				body.template_id === undefined
					? current.template_id
					: requiredUuid(body.template_id, 'template_id'),
			target_wbs_id:
				body.wbs_id === undefined
					? current.wbs_id
					: requiredUuid(body.wbs_id, 'wbs_id'),
			rule_code:
				body.rule_code === undefined
					? current.rule_code
					: requiredText(body.rule_code, 'rule_code'),
			rule_name:
				body.name === undefined ? current.name : requiredText(body.name, 'name'),
			recurrence_frequency: frequency,
			recurrence_starts_on: dateValue(
				body.starts_on === undefined ? current.starts_on : body.starts_on,
				'starts_on',
				true
			),
			recurrence_occurrence_time: timeValue(
				body.occurrence_time === undefined
					? current.occurrence_time
					: body.occurrence_time
			),
			target_calendar_id:
				body.calendar_id === undefined
					? current.calendar_id
					: requiredUuid(body.calendar_id, 'calendar_id'),
			target_cycle_id:
				body.cultivation_cycle_id === undefined
					? current.cultivation_cycle_id
					: optionalUuid(body.cultivation_cycle_id, 'cultivation_cycle_id'),
			rule_status: status,
			recurrence_interval_count: intervalCount,
			recurrence_day_of_month: dayOfMonth,
			recurrence_ends_on: dateValue(
				body.ends_on === undefined ? current.ends_on : body.ends_on,
				'ends_on'
			),
			recurrence_timezone:
				body.timezone === undefined
					? current.timezone
					: requiredText(body.timezone, 'timezone'),
			recurrence_weekdays: weekdays,
			generation_horizon_days: horizon
		});

		if (error) {
			console.error('Recurrence rule update failed:', error);
			if (isVersionConflict(error)) {
				return json({ error: 'Recurrence rule version conflict.' }, { status: 409 });
			}
			return json({ error: 'Unable to update recurrence rule.' }, { status: 400 });
		}

		return json({ recurrence_rule: data });
	} catch (error) {
		return json(
			{
				error:
					error instanceof Error ? error.message : 'Invalid recurrence rule request.'
			},
			{ status: 400 }
		);
	}
};

export const DELETE: RequestHandler = async ({ params, url, locals }) => {
	const farmId = params.farmId ?? '';
	const projectId = params.projectId ?? '';
	const ruleId = params.ruleId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) {
		return json({ error: 'Supabase is not configured.' }, { status: 503 });
	}
	if (!user) {
		return json({ error: 'Authentication is required.' }, { status: 401 });
	}
	if (!isUuid(farmId) || !isUuid(projectId) || !isUuid(ruleId)) {
		return json({ error: 'Invalid farm, project, or rule id.' }, { status: 400 });
	}

	try {
		const { error } = await supabase.rpc('delete_activity_recurrence_rule', {
			target_farm_id: farmId,
			target_project_id: projectId,
			target_rule_id: ruleId,
			expected_version: expectedVersion(url.searchParams.get('expected_version'))
		});

		if (error) {
			console.error('Recurrence rule deletion failed:', error);
			if (isVersionConflict(error)) {
				return json({ error: 'Recurrence rule version conflict.' }, { status: 409 });
			}
			return json({ error: 'Unable to delete recurrence rule.' }, { status: 400 });
		}

		return new Response(null, { status: 204 });
	} catch (error) {
		return json(
			{
				error:
					error instanceof Error ? error.message : 'Invalid recurrence rule request.'
			},
			{ status: 400 }
		);
	}
};
