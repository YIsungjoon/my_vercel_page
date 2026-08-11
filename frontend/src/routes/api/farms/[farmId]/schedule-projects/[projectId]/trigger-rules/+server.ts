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
} from '$lib/server/apiValidation';
import {
	CREATE_RULE_STATUSES,
	EVENT_TYPES,
	MATCH_MODES,
	predicateValues
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
		.from('activity_trigger_rules')
		.select(
			'id, farm_id, project_id, template_id, wbs_id, calendar_id, cultivation_cycle_id, rule_code, name, status, event_type, predicate_match_mode, cooldown_minutes, valid_from, valid_until, created_by, updated_by, version, created_at, updated_at, activity_trigger_predicates(id, sequence_no, source_field_code, comparison_operator, numeric_value, text_value, boolean_value, unit_code, observation_window_minutes), activity_trigger_rule_work_areas(work_area_id, is_primary)'
		)
		.eq('farm_id', farmId)
		.eq('project_id', projectId)
		.order('rule_code', { ascending: true });

	if (error) {
		console.error('Activity trigger rule list query failed:', error);
		return json({ error: 'Unable to load trigger rules.' }, { status: 500 });
	}

	return json({ trigger_rules: data ?? [] });
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
		const eventType = requiredText(body.event_type, 'event_type');
		const matchMode = optionalText(body.predicate_match_mode) ?? 'ALL';
		const cooldown = integerOrDefault(body.cooldown_minutes, 0, 'cooldown_minutes');
		const predicates = predicateValues(body.predicates);

		if (!CREATE_RULE_STATUSES.includes(status)) {
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

		const { data, error } = await supabase.rpc('create_activity_trigger_rule', {
			target_farm_id: farmId,
			target_project_id: projectId,
			target_template_id: requiredUuid(body.template_id, 'template_id'),
			target_wbs_id: requiredUuid(body.wbs_id, 'wbs_id'),
			rule_code: requiredText(body.rule_code, 'rule_code'),
			rule_name: requiredText(body.name, 'name'),
			trigger_event_type: eventType,
			target_calendar_id: optionalUuid(body.calendar_id, 'calendar_id'),
			target_cycle_id: optionalUuid(body.cultivation_cycle_id, 'cultivation_cycle_id'),
			rule_status: status,
			predicate_match_mode: matchMode,
			cooldown_minutes: cooldown,
			valid_from: optionalTimestamp(body.valid_from, 'valid_from'),
			valid_until: optionalTimestamp(body.valid_until, 'valid_until'),
			predicate_field_codes: predicates.map((predicate) => predicate.source_field_code),
			predicate_operators: predicates.map((predicate) => predicate.comparison_operator),
			predicate_numeric_values: predicates.map((predicate) => predicate.numeric_value),
			predicate_text_values: predicates.map((predicate) => predicate.text_value),
			predicate_boolean_values: predicates.map((predicate) => predicate.boolean_value),
			predicate_unit_codes: predicates.map((predicate) => predicate.unit_code),
			predicate_window_minutes: predicates.map(
				(predicate) => predicate.observation_window_minutes
			),
			target_work_area_ids: uuidArray(body.work_area_ids, 'work_area_ids')
		});

		if (error) {
			console.error('Activity trigger rule creation failed:', error);
			return json({ error: 'Unable to create trigger rule.' }, { status: 400 });
		}

		return json({ trigger_rule: data }, { status: 201 });
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
