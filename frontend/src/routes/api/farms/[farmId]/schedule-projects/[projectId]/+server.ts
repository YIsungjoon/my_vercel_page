import { json } from '@sveltejs/kit';
import { isUuid } from '$lib/server/apiValidation';
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

	const { data: project, error: projectError } = await supabase
		.from('schedule_projects')
		.select(
			'id, farm_id, cultivation_cycle_id, project_code, name, description, status, planned_start_at, planned_finish_at, data_date, timezone, default_percent_complete_type, default_calendar_id, created_by, updated_by, version, created_at, updated_at'
		)
		.eq('farm_id', farmId)
		.eq('id', projectId)
		.maybeSingle();

	if (projectError) {
		console.error('Schedule project query failed:', projectError);
		return json({ error: 'Unable to load schedule project.' }, { status: 500 });
	}
	if (!project) {
		return json({ error: 'Schedule project was not found.' }, { status: 404 });
	}

	const [
		calendarsResult,
		wbsResult,
		activitiesResult,
		relationshipsResult,
		recurrenceRulesResult,
		triggerRulesResult,
		ruleRunsResult,
		activityProposalsResult
	] =
		await Promise.all([
			supabase
				.from('schedule_calendars')
				.select(
					'id, farm_id, project_id, base_calendar_id, calendar_code, name, calendar_scope, timezone, minutes_per_day, minutes_per_week, created_by, created_at, updated_at, schedule_calendar_working_periods(id, weekday, start_time, end_time), schedule_calendar_exceptions(id, exception_date, exception_type, reason_code, reason, start_time, end_time, created_by, created_at)'
				)
				.eq('farm_id', farmId)
				.eq('project_id', projectId)
				.order('calendar_code', { ascending: true }),
			supabase
				.from('schedule_wbs_nodes')
				.select(
					'id, farm_id, project_id, parent_id, wbs_code, name, description, sequence_no, created_by, created_at, updated_at'
				)
				.eq('farm_id', farmId)
				.eq('project_id', projectId)
				.order('sequence_no', { ascending: true })
				.order('wbs_code', { ascending: true }),
			supabase
				.from('schedule_activities')
				.select(
					'id, farm_id, project_id, wbs_id, calendar_id, cultivation_cycle_id, operation_type_code, activity_code, name, description, activity_type, status, percent_complete_type, planned_start_at, planned_finish_at, planned_duration_minutes, actual_start_at, actual_finish_at, remaining_duration_minutes, primary_constraint_type, primary_constraint_at, created_by, updated_by, version, created_at, updated_at, schedule_activity_work_areas(work_area_id, is_primary), task_activity_links(task_id, link_type, is_primary)'
				)
				.eq('farm_id', farmId)
				.eq('project_id', projectId)
				.order('activity_code', { ascending: true }),
			supabase
				.from('schedule_activity_relationships')
				.select(
					'id, farm_id, project_id, predecessor_activity_id, successor_activity_id, relationship_type, lag_minutes, created_by, created_at, updated_at'
				)
				.eq('farm_id', farmId)
				.eq('project_id', projectId)
				.order('created_at', { ascending: true }),
			supabase
				.from('activity_recurrence_rules')
				.select(
					'id, farm_id, project_id, template_id, wbs_id, calendar_id, cultivation_cycle_id, rule_code, name, status, frequency, interval_count, day_of_month, starts_on, ends_on, occurrence_time, timezone, generation_horizon_days, created_by, updated_by, version, created_at, updated_at, activity_recurrence_weekdays(weekday)'
				)
				.eq('farm_id', farmId)
				.eq('project_id', projectId)
				.order('rule_code', { ascending: true }),
			supabase
				.from('activity_trigger_rules')
				.select(
					'id, farm_id, project_id, template_id, wbs_id, calendar_id, cultivation_cycle_id, rule_code, name, status, event_type, predicate_match_mode, cooldown_minutes, valid_from, valid_until, created_by, updated_by, version, created_at, updated_at, activity_trigger_predicates(id, sequence_no, source_field_code, comparison_operator, numeric_value, text_value, boolean_value, unit_code, observation_window_minutes), activity_trigger_rule_work_areas(work_area_id, is_primary)'
				)
				.eq('farm_id', farmId)
				.eq('project_id', projectId)
				.order('rule_code', { ascending: true }),
			supabase
				.from('activity_rule_runs')
				.select(
					'id, farm_id, project_id, run_kind, recurrence_rule_id, trigger_rule_id, source_rule_version, source_template_version, idempotency_key, window_start_date, window_end_date, status, outcome_code, started_at, finished_at, created_by, execution_worker_id, created_at'
				)
				.eq('farm_id', farmId)
				.eq('project_id', projectId)
				.order('created_at', { ascending: false }),
			supabase
				.from('activity_proposals')
				.select(
					'id, farm_id, project_id, rule_run_id, proposal_key, template_id, template_version, wbs_id, calendar_id, cultivation_cycle_id, operation_type_code, activity_code, name, description, activity_type, percent_complete_type, planned_start_at, planned_finish_at, planned_duration_minutes, status, version, created_by, updated_by, created_by_worker_id, updated_by_worker_id, created_at, updated_at, activity_proposal_decisions(id, decision, reason_code, note, decided_by, decided_at), activity_proposal_applications(id, activity_id, idempotency_key, applied_by, applied_at)'
				)
				.eq('farm_id', farmId)
				.eq('project_id', projectId)
				.order('planned_start_at', { ascending: true })
		]);

	const queryError =
		calendarsResult.error ??
		wbsResult.error ??
		activitiesResult.error ??
		relationshipsResult.error ??
		recurrenceRulesResult.error ??
		triggerRulesResult.error ??
		ruleRunsResult.error ??
		activityProposalsResult.error;

	if (queryError) {
		console.error('Schedule project workspace query failed:', queryError);
		return json({ error: 'Unable to load schedule project workspace.' }, { status: 500 });
	}

	return json({
		project,
		calendars: calendarsResult.data ?? [],
		wbs_nodes: wbsResult.data ?? [],
		activities: activitiesResult.data ?? [],
		relationships: relationshipsResult.data ?? [],
		recurrence_rules: recurrenceRulesResult.data ?? [],
		trigger_rules: triggerRulesResult.data ?? [],
		rule_runs: ruleRunsResult.data ?? [],
		activity_proposals: activityProposalsResult.data ?? []
	});
};
