import { json } from '@sveltejs/kit';
import {
	isUuid,
	optionalText,
	requiredText
} from '$agri/server/apiValidation';
import { OBSERVATION_SOURCE_KINDS } from '$agri/server/observationValidation';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ params, locals }) => {
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

	const { data, error } = await supabase
		.from('observation_sources')
		.select(
			'id, farm_id, source_code, name, source_kind, provider_code, external_reference, is_active, created_by, created_at, updated_at'
		)
		.eq('farm_id', farmId)
		.order('source_code', { ascending: true });

	if (error) {
		console.error('Observation source list query failed:', error);
		return json({ error: 'Unable to load observation sources.' }, { status: 500 });
	}

	return json({ observation_sources: data ?? [] });
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
		const sourceKind = requiredText(body.source_kind, 'source_kind');
		if (!OBSERVATION_SOURCE_KINDS.includes(sourceKind)) {
			throw new Error('source_kind is not supported.');
		}

		const { data, error } = await supabase.rpc('create_observation_source', {
			target_farm_id: farmId,
			source_code: requiredText(body.source_code, 'source_code'),
			source_name: requiredText(body.name, 'name'),
			source_kind: sourceKind,
			provider_code: optionalText(body.provider_code),
			external_reference: optionalText(body.external_reference)
		});

		if (error) {
			console.error('Observation source creation failed:', error);
			return json({ error: 'Unable to create observation source.' }, { status: 400 });
		}

		return json({ observation_source: data }, { status: 201 });
	} catch (error) {
		return json(
			{
				error:
					error instanceof Error ? error.message : 'Invalid observation source request.'
			},
			{ status: 400 }
		);
	}
};
