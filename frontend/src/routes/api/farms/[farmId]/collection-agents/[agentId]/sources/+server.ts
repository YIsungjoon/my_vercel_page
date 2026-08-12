import { json } from '@sveltejs/kit';
import { isUuid, optionalText, uuidArray } from '$lib/server/apiValidation';
import { expectedVersion, isVersionConflict } from '$lib/server/activityRuleValidation';
import { normalizedReasonCode } from '$lib/server/observationValidation';
import type { RequestHandler } from './$types';

export const PUT: RequestHandler = async ({ params, request, locals }) => {
	const farmId = params.farmId ?? '';
	const agentId = params.agentId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) return json({ error: 'Supabase is not configured.' }, { status: 503 });
	if (!user) return json({ error: 'Authentication is required.' }, { status: 401 });
	if (!isUuid(farmId) || !isUuid(agentId)) {
		return json({ error: 'Invalid farm or collection agent id.' }, { status: 400 });
	}

	try {
		const body = (await request.json()) as Record<string, unknown>;
		const { data, error } = await supabase.rpc('set_collection_agent_sources', {
			target_farm_id: farmId,
			target_agent_id: agentId,
			expected_version: expectedVersion(body.expected_version),
			authorized_source_ids: uuidArray(body.authorized_source_ids, 'authorized_source_ids'),
			reason_code: normalizedReasonCode(body.reason_code),
			change_note: optionalText(body.note)
		});

		if (error) {
			console.error('Collection agent source grant replacement failed:', error);
			return json(
				{ error: isVersionConflict(error) ? 'Collection agent version conflict.' : error.message },
				{ status: isVersionConflict(error) ? 409 : 400 }
			);
		}

		return json(data);
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid collection agent source request.' },
			{ status: 400 }
		);
	}
};
