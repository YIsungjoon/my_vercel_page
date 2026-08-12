import { json } from '@sveltejs/kit';
import { isUuid, optionalText, requiredText } from '$lib/server/apiValidation';
import { expectedVersion, isVersionConflict } from '$lib/server/activityRuleValidation';
import {
	boundedInteger,
	normalizedReasonCode,
	OBSERVATION_SEQUENCE_POLICIES
} from '$lib/server/observationValidation';
import type { RequestHandler } from './$types';

const STREAM_POLICY_FIELDS =
	'id, farm_id, source_id, stream_code, name, quality_policy_version, sequence_policy, clock_drift_tolerance_seconds, quality_policy_updated_by, updated_at';

export const GET: RequestHandler = async ({ params, locals }) => {
	const farmId = params.farmId ?? '';
	const streamId = params.streamId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) return json({ error: 'Supabase is not configured.' }, { status: 503 });
	if (!user) return json({ error: 'Authentication is required.' }, { status: 401 });
	if (!isUuid(farmId) || !isUuid(streamId)) {
		return json({ error: 'Invalid farm or stream id.' }, { status: 400 });
	}

	const [streamResult, historyResult, stateResult] = await Promise.all([
		supabase
			.from('observation_streams')
			.select(STREAM_POLICY_FIELDS)
			.eq('farm_id', farmId)
			.eq('id', streamId)
			.maybeSingle(),
		supabase
			.from('observation_stream_quality_policy_versions')
			.select(
				'id, farm_id, stream_id, policy_version, sequence_policy, clock_drift_tolerance_seconds, reason_code, note, changed_by, changed_at'
			)
			.eq('farm_id', farmId)
			.eq('stream_id', streamId)
			.order('policy_version', { ascending: false }),
		supabase
			.from('observation_stream_sequence_states')
			.select(
				'stream_id, farm_id, policy_version, last_sequence_value, last_observation_id, last_observed_at, receipt_count, anomaly_count, version, updated_at'
			)
			.eq('farm_id', farmId)
			.eq('stream_id', streamId)
			.maybeSingle()
	]);

	const queryError = streamResult.error ?? historyResult.error ?? stateResult.error;
	if (queryError) {
		console.error('Observation stream quality policy query failed:', queryError);
		return json({ error: 'Unable to load observation stream quality policy.' }, { status: 500 });
	}
	if (!streamResult.data) {
		return json({ error: 'Observation stream was not found.' }, { status: 404 });
	}

	return json({
		observation_stream: streamResult.data,
		policy_versions: historyResult.data ?? [],
		sequence_state: stateResult.data
	});
};

export const PATCH: RequestHandler = async ({ params, request, locals }) => {
	const farmId = params.farmId ?? '';
	const streamId = params.streamId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) return json({ error: 'Supabase is not configured.' }, { status: 503 });
	if (!user) return json({ error: 'Authentication is required.' }, { status: 401 });
	if (!isUuid(farmId) || !isUuid(streamId)) {
		return json({ error: 'Invalid farm or stream id.' }, { status: 400 });
	}

	try {
		const body = (await request.json()) as Record<string, unknown>;
		const sequencePolicy = requiredText(body.sequence_policy, 'sequence_policy');
		if (!OBSERVATION_SEQUENCE_POLICIES.includes(sequencePolicy)) {
			throw new Error('sequence_policy is not supported.');
		}

		const { data, error } = await supabase.rpc(
			'update_observation_stream_quality_policy',
			{
				target_farm_id: farmId,
				target_stream_id: streamId,
				expected_policy_version: expectedVersion(body.expected_version),
				target_sequence_policy: sequencePolicy,
				target_clock_drift_tolerance_seconds: boundedInteger(
					body.clock_drift_tolerance_seconds,
					300,
					'clock_drift_tolerance_seconds',
					0,
					300
				),
				reason_code: normalizedReasonCode(body.reason_code),
				policy_note: optionalText(body.note)
			}
		);

		if (error) {
			console.error('Observation stream quality policy update failed:', error);
			return json(
				{
					error: isVersionConflict(error)
						? 'Observation quality policy version conflict.'
						: error.message
				},
				{ status: isVersionConflict(error) ? 409 : 400 }
			);
		}

		return json({ observation_stream: data });
	} catch (error) {
		return json(
			{
				error:
					error instanceof Error ? error.message : 'Invalid observation quality policy request.'
			},
			{ status: 400 }
		);
	}
};
