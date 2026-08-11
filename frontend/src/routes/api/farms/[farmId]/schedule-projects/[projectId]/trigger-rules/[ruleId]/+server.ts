import { json } from '@sveltejs/kit';
import {
	integerOrDefault,
	isUuid,
	optionalTimestamp,
	optionalUuid,
	requiredText,
	requiredUuid,
	uuidArray
} from '$lib/server/apiValidation';
import {
	EVENT_TYPES,
	MATCH_MODES,
	RULE_STATUSES,
	expectedVersion,
	isVersionConflict,
	predicateValues
} from '$lib/server/activityRuleValidation';
import type { RequestHandler } from './$types';

const TRIGGER_FIELDS =
	'id, farm_id, project_id, template_id, wbs_id, calendar_id, cultivation_cycle_id, rule_code, name, status, event_type, predicate_match_mode, cooldown_minutes, valid_from, valid_until, version, activity_trigger_predicates(id, sequence_no, source_field_code, comparison_operator, numeric_value, text_value, boolean_value, unit_code, observation_window_minutes), activity_trigger_rule_work_areas(work_area_id, is_primary)';

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
			.from('activity_trigger_rules')
			.select(TRIGGER_FIELDS)
			.eq('farm_id', farmId)
			.eq('project_id', projectId)
			.eq('id', ruleId)
			.maybeSingle();

		if (currentError) {
			console.error('Trigger rule lookup failed:', currentError);
			return json({ error: 'Unable to load trigger rule.' }, { status: 500 });
		}
		if (!current) {
			return json({ error: 'Trigger rule was not found.' }, { status: 404 });
		}

		const status =
			body.status === undefined ? current.status : requiredText(body.status, 'status');
		const eventType =
			body.event_type === undefined
				? current.event_type
				: requiredText(body.event_type, 'event_type');
		const matchMode =
			body.predicate_match_mode === undefined
				? current.predicate_match_mode
				: requiredText(body.predicate_match_mode, 'predicate_match_mode');
		const cooldown =
			body.cooldown_minutes === undefined
				? current.cooldown_minutes
				: integerOrDefault(body.cooldown_minutes, 0, 'cooldown_minutes');
		const predicates =
			body.predicates === undefined
				? (current.activity_trigger_predicates ?? [])
						.slice()
						.sort(
							(left: { sequence_no: number }, right: { sequence_no: number }) =>
								left.sequence_no - right.sequence_no
						)
						.map(
							(predicate: {
								source_field_code: string;
								comparison_operator: string;
								numeric_value: number | string | null;
								text_value: string | null;
								boolean_value: boolean | null;
								unit_code: string | null;
								observation_window_minutes: number | null;
							}) => ({
								source_field_code: predicate.source_field_code,
								comparison_operator: predicate.comparison_operator,
								numeric_value:
									predicate.numeric_value === null
										? null
										: Number(predicate.numeric_value),
								text_value: predicate.text_value,
								boolean_value: predicate.boolean_value,
								unit_code: predicate.unit_code,
								observation_window_minutes:
									predicate.observation_window_minutes
							})
						)
				: predicateValues(body.predicates);
		const workAreaIds =
			body.work_area_ids === undefined
				? (current.activity_trigger_rule_work_areas ?? [])
						.slice()
						.sort(
							(
								left: { is_primary: boolean },
								right: { is_primary: boolean }
							) => Number(right.is_primary) - Number(left.is_primary)
						)
						.map((link: { work_area_id: string }) => link.work_area_id)
				: uuidArray(body.work_area_ids, 'work_area_ids');

		if (!RULE_STATUSES.includes(status)) {
			throw new Error('status is not supported.');
		}
		if (!EVENT_TYPES.includes(eventType)) {
			throw new Error('event_type is not supported.');
		}
		if (!MATCH_MODES.includes(matchMode)) {
			throw new Error('predicate_match_mode is not supported.');
		}
		if (cooldown < 0) {
			throw new Error('cooldown_minutes must be non-negative.');
		}
		if (status === 'ACTIVE' && eventType !== 'MANUAL' && predicates.length === 0) {
			throw new Error('An active non-manual trigger rule requires a predicate.');
		}

		const { data, error } = await supabase.rpc('update_activity_trigger_rule', {
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
			trigger_event_type: eventType,
			target_calendar_id:
				body.calendar_id === undefined
					? current.calendar_id
					: requiredUuid(body.calendar_id, 'calendar_id'),
			target_cycle_id:
				body.cultivation_cycle_id === undefined
					? current.cultivation_cycle_id
					: optionalUuid(body.cultivation_cycle_id, 'cultivation_cycle_id'),
			rule_status: status,
			predicate_match_mode: matchMode,
			cooldown_minutes: cooldown,
			valid_from:
				body.valid_from === undefined
					? current.valid_from
					: optionalTimestamp(body.valid_from, 'valid_from'),
			valid_until:
				body.valid_until === undefined
					? current.valid_until
					: optionalTimestamp(body.valid_until, 'valid_until'),
			predicate_field_codes: predicates.map((predicate) => predicate.source_field_code),
			predicate_operators: predicates.map((predicate) => predicate.comparison_operator),
			predicate_numeric_values: predicates.map((predicate) => predicate.numeric_value),
			predicate_text_values: predicates.map((predicate) => predicate.text_value),
			predicate_boolean_values: predicates.map((predicate) => predicate.boolean_value),
			predicate_unit_codes: predicates.map((predicate) => predicate.unit_code),
			predicate_window_minutes: predicates.map(
				(predicate) => predicate.observation_window_minutes
			),
			target_work_area_ids: workAreaIds
		});

		if (error) {
			console.error('Trigger rule update failed:', error);
			if (isVersionConflict(error)) {
				return json({ error: 'Trigger rule version conflict.' }, { status: 409 });
			}
			return json({ error: 'Unable to update trigger rule.' }, { status: 400 });
		}

		return json({ trigger_rule: data });
	} catch (error) {
		return json(
			{
				error:
					error instanceof Error ? error.message : 'Invalid trigger rule request.'
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
		const { error } = await supabase.rpc('delete_activity_trigger_rule', {
			target_farm_id: farmId,
			target_project_id: projectId,
			target_rule_id: ruleId,
			expected_version: expectedVersion(url.searchParams.get('expected_version'))
		});

		if (error) {
			console.error('Trigger rule deletion failed:', error);
			if (isVersionConflict(error)) {
				return json({ error: 'Trigger rule version conflict.' }, { status: 409 });
			}
			return json({ error: 'Unable to delete trigger rule.' }, { status: 400 });
		}

		return new Response(null, { status: 204 });
	} catch (error) {
		return json(
			{
				error:
					error instanceof Error ? error.message : 'Invalid trigger rule request.'
			},
			{ status: 400 }
		);
	}
};
