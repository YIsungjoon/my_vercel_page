import { json } from '@sveltejs/kit';
import {
	integerOrDefault,
	isUuid,
	optionalText,
	optionalUuid,
	requiredText,
	requiredUuid
} from '$lib/server/apiValidation';
import {
	CREATE_RULE_STATUSES,
	FREQUENCIES,
	dateValue,
	timeValue,
	weekdayValues
} from '$lib/server/activityRuleValidation';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ params, locals }) => {
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

	const { data, error } = await supabase
		.from('activity_recurrence_rules')
		.select(
			'id, farm_id, project_id, template_id, wbs_id, calendar_id, cultivation_cycle_id, rule_code, name, status, frequency, interval_count, day_of_month, starts_on, ends_on, occurrence_time, timezone, generation_horizon_days, created_by, updated_by, version, created_at, updated_at, activity_recurrence_weekdays(weekday)'
		)
		.eq('farm_id', farmId)
		.eq('project_id', projectId)
		.order('rule_code', { ascending: true });

	if (error) {
		console.error('Activity recurrence rule list query failed:', error);
		return json({ error: 'Unable to load recurrence rules.' }, { status: 500 });
	}

	return json({ recurrence_rules: data ?? [] });
};

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
		const status = optionalText(body.status) ?? 'DRAFT';
		const frequency = requiredText(body.frequency, 'frequency');
		const intervalCount = integerOrDefault(body.interval_count, 1, 'interval_count');
		const horizon = integerOrDefault(
			body.generation_horizon_days,
			30,
			'generation_horizon_days'
		);
		const dayOfMonth =
			body.day_of_month === undefined || body.day_of_month === null
				? null
				: integerOrDefault(body.day_of_month, 0, 'day_of_month');
		const weekdays = weekdayValues(body.weekdays);

		if (!CREATE_RULE_STATUSES.includes(status)) {
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
		if (frequency === 'MONTHLY' && (dayOfMonth === null || dayOfMonth < 1 || dayOfMonth > 31)) {
			throw new Error('A monthly recurrence rule requires day_of_month from 1 to 31.');
		}
		if (frequency !== 'MONTHLY' && dayOfMonth !== null) {
			throw new Error('day_of_month is only accepted for monthly recurrence rules.');
		}

		const { data, error } = await supabase.rpc('create_activity_recurrence_rule', {
			target_farm_id: farmId,
			target_project_id: projectId,
			target_template_id: requiredUuid(body.template_id, 'template_id'),
			target_wbs_id: requiredUuid(body.wbs_id, 'wbs_id'),
			rule_code: requiredText(body.rule_code, 'rule_code'),
			rule_name: requiredText(body.name, 'name'),
			recurrence_frequency: frequency,
			recurrence_starts_on: dateValue(body.starts_on, 'starts_on', true),
			recurrence_occurrence_time: timeValue(body.occurrence_time),
			target_calendar_id: optionalUuid(body.calendar_id, 'calendar_id'),
			target_cycle_id: optionalUuid(body.cultivation_cycle_id, 'cultivation_cycle_id'),
			rule_status: status,
			recurrence_interval_count: intervalCount,
			recurrence_day_of_month: dayOfMonth,
			recurrence_ends_on: dateValue(body.ends_on, 'ends_on'),
			recurrence_timezone: optionalText(body.timezone),
			recurrence_weekdays: weekdays,
			generation_horizon_days: horizon
		});

		if (error) {
			console.error('Activity recurrence rule creation failed:', error);
			return json({ error: 'Unable to create recurrence rule.' }, { status: 400 });
		}

		return json({ recurrence_rule: data }, { status: 201 });
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
