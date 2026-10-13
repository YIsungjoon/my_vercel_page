import { json } from '@sveltejs/kit';
import {
	isUuid,
	optionalUuid,
	requiredText,
	requiredUuid
} from '$lib/server/apiValidation';
import { boundedInteger } from '$lib/server/observationValidation';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ params, url, locals }) => {
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

	const fieldCode = url.searchParams.get('field_code')?.trim();
	let query = supabase
		.from('observation_streams')
		.select(
			'id, farm_id, source_id, work_area_id, field_code, stream_code, name, unit_code, max_latency_minutes, quality_policy_version, sequence_policy, clock_drift_tolerance_seconds, quality_policy_updated_by, requires_calibration, is_active, created_by, created_at, updated_at'
		)
		.eq('farm_id', farmId);

	if (fieldCode) {
		query = query.eq('field_code', fieldCode);
	}

	const { data, error } = await query.order('stream_code', { ascending: true });
	if (error) {
		console.error('Observation stream list query failed:', error);
		return json({ error: 'Unable to load observation streams.' }, { status: 500 });
	}

	return json({ observation_streams: data ?? [] });
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
		const body = (await request.json()) as Record<string, unknown>;
		if (
			body.requires_calibration !== undefined &&
			typeof body.requires_calibration !== 'boolean'
		) {
			throw new Error('requires_calibration must be boolean.');
		}

		const { data, error } = await supabase.rpc('create_observation_stream', {
			target_farm_id: farmId,
			target_source_id: requiredUuid(body.source_id, 'source_id'),
			target_field_code: requiredText(body.field_code, 'field_code'),
			stream_code: requiredText(body.stream_code, 'stream_code'),
			stream_name: requiredText(body.name, 'name'),
			target_work_area_id: optionalUuid(body.work_area_id, 'work_area_id'),
			max_latency_minutes: boundedInteger(
				body.max_latency_minutes,
				15,
				'max_latency_minutes',
				0,
				10080
			),
			requires_calibration: body.requires_calibration === true
		});

		if (error) {
			console.error('Observation stream creation failed:', error);
			return json({ error: 'Unable to create observation stream.' }, { status: 400 });
		}

		return json({ observation_stream: data }, { status: 201 });
	} catch (error) {
		return json(
			{
				error:
					error instanceof Error ? error.message : 'Invalid observation stream request.'
			},
			{ status: 400 }
		);
	}
};
