import { json } from '@sveltejs/kit';
import {
	isUuid,
	optionalText,
	requiredText
} from '$agri/server/apiValidation';
import {
	boundedInteger,
	DERIVED_QUALITY_STATUSES,
	observationValues,
	optionalIsoTimestamp,
	requiredTimestamp,
	SOURCE_QUALITY_STATUSES
} from '$agri/server/observationValidation';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ params, url, locals }) => {
	const farmId = params.farmId ?? '';
	const streamId = params.streamId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) {
		return json({ error: 'Supabase is not configured.' }, { status: 503 });
	}
	if (!user) {
		return json({ error: 'Authentication is required.' }, { status: 401 });
	}
	if (!isUuid(farmId) || !isUuid(streamId)) {
		return json({ error: 'Invalid farm or stream id.' }, { status: 400 });
	}

	try {
		const qualityStatus = optionalText(url.searchParams.get('quality_status'));
		if (qualityStatus && !DERIVED_QUALITY_STATUSES.includes(qualityStatus)) {
			throw new Error('quality_status is not supported.');
		}
		const limit = boundedInteger(url.searchParams.get('limit'), 100, 'limit', 1, 500);

		let query = supabase
			.from('stream_observations')
			.select(
				'id, farm_id, source_id, stream_id, calibration_id, observed_at, received_at, numeric_value, text_value, boolean_value, source_quality_status, quality_status, source_sequence, idempotency_key, recorded_by, collector_agent_id, ingest_batch_id, created_at, observation_quality_findings(id, finding_code, severity, detail, detected_at), observation_transport_quality_receipts(observation_id, policy_version, sequence_policy, source_sequence_value, previous_high_watermark, sequence_status, missing_sequence_count, sequence_state_advanced, clock_drift_seconds, clock_drift_tolerance_seconds, clock_status, evaluated_at)'
			)
			.eq('farm_id', farmId)
			.eq('stream_id', streamId);

		if (qualityStatus) {
			query = query.eq('quality_status', qualityStatus);
		}

		const { data, error } = await query
			.order('observed_at', { ascending: false })
			.limit(limit);

		if (error) {
			console.error('Stream observation list query failed:', error);
			return json({ error: 'Unable to load stream observations.' }, { status: 500 });
		}

		return json({ stream_observations: data ?? [] });
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid observation query.' },
			{ status: 400 }
		);
	}
};

export const POST: RequestHandler = async ({ params, request, locals }) => {
	const farmId = params.farmId ?? '';
	const streamId = params.streamId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) {
		return json({ error: 'Supabase is not configured.' }, { status: 503 });
	}
	if (!user) {
		return json({ error: 'Authentication is required.' }, { status: 401 });
	}
	if (!isUuid(farmId) || !isUuid(streamId)) {
		return json({ error: 'Invalid farm or stream id.' }, { status: 400 });
	}

	try {
		const body = (await request.json()) as Record<string, unknown>;
		const values = observationValues(body);
		const sourceQuality = optionalText(body.source_quality_status) ?? 'VALID';
		if (!SOURCE_QUALITY_STATUSES.includes(sourceQuality)) {
			throw new Error('source_quality_status is not supported.');
		}

		const { data, error } = await supabase.rpc('record_stream_observation', {
			target_farm_id: farmId,
			target_stream_id: streamId,
			observation_observed_at: requiredTimestamp(body.observed_at, 'observed_at'),
			observation_idempotency_key: requiredText(
				body.idempotency_key,
				'idempotency_key'
			),
			observation_numeric_value: values.numeric_value,
			observation_text_value: values.text_value,
			observation_boolean_value: values.boolean_value,
			observation_received_at: optionalIsoTimestamp(body.received_at, 'received_at'),
			source_quality_status: sourceQuality,
			source_sequence: optionalText(body.source_sequence)
		});

		if (error) {
			console.error('Stream observation creation failed:', error);
			return json({ error: 'Unable to record stream observation.' }, { status: 400 });
		}

		return json(data, { status: 201 });
	} catch (error) {
		return json(
			{
				error:
					error instanceof Error ? error.message : 'Invalid observation request.'
			},
			{ status: 400 }
		);
	}
};
