import { json } from '@sveltejs/kit';
import { isUuid, optionalText } from '$lib/server/apiValidation';
import { expectedVersion, isVersionConflict } from '$lib/server/activityRuleValidation';
import { normalizedReasonCode } from '$lib/server/observationValidation';
import type { RequestHandler } from './$types';

export const POST: RequestHandler = async ({ params, request, locals }) => {
	const farmId = params.farmId ?? '';
	const agentId = params.agentId ?? '';
	const credentialId = params.credentialId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) return json({ error: 'Supabase is not configured.' }, { status: 503 });
	if (!user) return json({ error: 'Authentication is required.' }, { status: 401 });
	if (!isUuid(farmId) || !isUuid(agentId) || !isUuid(credentialId)) {
		return json(
			{ error: 'Invalid farm, collection agent, or credential id.' },
			{ status: 400 }
		);
	}

	try {
		const body = (await request.json()) as Record<string, unknown>;
		const { data, error } = await supabase.rpc('revoke_collection_agent_credential', {
			target_farm_id: farmId,
			target_agent_id: agentId,
			target_credential_id: credentialId,
			expected_agent_version: expectedVersion(body.expected_version),
			reason_code: normalizedReasonCode(body.reason_code),
			change_note: optionalText(body.note)
		});

		if (error) {
			console.error('Collection agent credential revocation failed:', error);
			return json(
				{ error: isVersionConflict(error) ? 'Collection agent version conflict.' : error.message },
				{ status: isVersionConflict(error) ? 409 : 400 }
			);
		}

		return json(data);
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid credential revocation request.' },
			{ status: 400 }
		);
	}
};
