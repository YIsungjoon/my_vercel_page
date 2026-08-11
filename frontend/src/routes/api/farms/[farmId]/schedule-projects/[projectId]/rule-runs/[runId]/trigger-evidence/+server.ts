import { json } from '@sveltejs/kit';
import { isUuid } from '$lib/server/apiValidation';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ params, locals }) => {
	const farmId = params.farmId ?? '';
	const projectId = params.projectId ?? '';
	const runId = params.runId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) {
		return json({ error: 'Supabase is not configured.' }, { status: 503 });
	}
	if (!user) {
		return json({ error: 'Authentication is required.' }, { status: 401 });
	}
	if (!isUuid(farmId) || !isUuid(projectId) || !isUuid(runId)) {
		return json({ error: 'Invalid farm, project, or run id.' }, { status: 400 });
	}

	const runResult = await supabase
		.from('activity_rule_runs')
		.select(
			'id, farm_id, project_id, run_kind, trigger_rule_id, source_rule_version, source_template_version, idempotency_key, status, outcome_code, started_at, finished_at, created_by, created_at'
		)
		.eq('farm_id', farmId)
		.eq('project_id', projectId)
		.eq('id', runId)
		.eq('run_kind', 'TRIGGER_EVALUATION')
		.maybeSingle();

	if (runResult.error) {
		console.error('Trigger evaluation run query failed:', runResult.error);
		return json({ error: 'Unable to load trigger evaluation evidence.' }, { status: 500 });
	}
	if (!runResult.data) {
		return json({ error: 'Trigger evaluation run was not found.' }, { status: 404 });
	}

	const [evaluationResult, predicatesResult, areasResult, proposalsResult] =
		await Promise.all([
			supabase
				.from('activity_trigger_evaluations')
				.select(
					'rule_run_id, farm_id, project_id, trigger_rule_id, source_rule_version, evaluated_at, event_type, match_mode, predicate_count, matched_count, insufficient_count, created_at'
				)
				.eq('farm_id', farmId)
				.eq('project_id', projectId)
				.eq('rule_run_id', runId)
				.maybeSingle(),
			supabase
				.from('activity_trigger_predicate_evaluations')
				.select(
					'id, rule_run_id, trigger_predicate_id, predicate_sequence_no, source_field_code, comparison_operator, expected_numeric_value, expected_text_value, expected_boolean_value, expected_unit_code, observation_id, observation_stream_id, observed_numeric_value, observed_text_value, observed_boolean_value, observed_unit_code, observed_at, observation_quality_status, result_status, reason_code, created_at'
				)
				.eq('farm_id', farmId)
				.eq('project_id', projectId)
				.eq('rule_run_id', runId)
				.order('predicate_sequence_no', { ascending: true }),
			supabase
				.from('activity_trigger_evaluation_work_areas')
				.select('work_area_id, is_primary, created_at')
				.eq('farm_id', farmId)
				.eq('project_id', projectId)
				.eq('rule_run_id', runId)
				.order('is_primary', { ascending: false }),
			supabase
				.from('activity_proposals')
				.select(
					'id, proposal_key, activity_code, name, planned_start_at, planned_finish_at, planned_duration_minutes, status, version'
				)
				.eq('farm_id', farmId)
				.eq('project_id', projectId)
				.eq('rule_run_id', runId)
		]);

	if (
		evaluationResult.error ||
		predicatesResult.error ||
		areasResult.error ||
		proposalsResult.error
	) {
		console.error('Trigger evaluation evidence query failed:', {
			evaluation: evaluationResult.error,
			predicates: predicatesResult.error,
			areas: areasResult.error,
			proposals: proposalsResult.error
		});
		return json({ error: 'Unable to load trigger evaluation evidence.' }, { status: 500 });
	}

	return json({
		run: runResult.data,
		evaluation: evaluationResult.data,
		predicate_evaluations: predicatesResult.data ?? [],
		work_areas: areasResult.data ?? [],
		proposals: proposalsResult.data ?? []
	});
};
