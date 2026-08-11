import { json } from '@sveltejs/kit';
import {
	isUuid,
	optionalText,
	requiredText
} from '$lib/server/apiValidation';
import {
	optionalIsoTimestamp,
	requiredTimestamp
} from '$lib/server/observationValidation';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ params, locals }) => {
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

	const { data, error } = await supabase
		.from('observation_calibrations')
		.select(
			'id, farm_id, stream_id, calibration_code, valid_from, valid_until, status, reference_standard, certificate_reference, performed_by, recorded_by, created_at'
		)
		.eq('farm_id', farmId)
		.eq('stream_id', streamId)
		.order('valid_from', { ascending: false });

	if (error) {
		console.error('Observation calibration list query failed:', error);
		return json({ error: 'Unable to load observation calibrations.' }, { status: 500 });
	}

	return json({ observation_calibrations: data ?? [] });
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
		const validFrom = requiredTimestamp(body.valid_from, 'valid_from');
		const validUntil = optionalIsoTimestamp(body.valid_until, 'valid_until');
		if (validUntil && Date.parse(validUntil) <= Date.parse(validFrom)) {
			throw new Error('valid_until must be later than valid_from.');
		}

		const { data, error } = await supabase.rpc('record_observation_calibration', {
			target_farm_id: farmId,
			target_stream_id: streamId,
			calibration_code: requiredText(body.calibration_code, 'calibration_code'),
			valid_from: validFrom,
			valid_until: validUntil,
			reference_standard: optionalText(body.reference_standard),
			certificate_reference: optionalText(body.certificate_reference),
			performed_by: optionalText(body.performed_by)
		});

		if (error) {
			console.error('Observation calibration creation failed:', error);
			return json({ error: 'Unable to record observation calibration.' }, { status: 400 });
		}

		return json({ observation_calibration: data }, { status: 201 });
	} catch (error) {
		return json(
			{
				error:
					error instanceof Error ? error.message : 'Invalid calibration request.'
			},
			{ status: 400 }
		);
	}
};
