import { json } from '@sveltejs/kit';
import { isUuid, optionalText, optionalUuid } from '$agri/server/apiValidation';
import { expectedVersion, isVersionConflict } from '$agri/server/activityRuleValidation';
import {
	credentialFingerprint,
	normalizedReasonCode,
	optionalIsoTimestamp,
	vaultSecretReference
} from '$agri/server/observationValidation';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ params, locals }) => {
	const farmId = params.farmId ?? '';
	const agentId = params.agentId ?? '';
	const supabase = locals.supabase;
	const user = await locals.getUser();

	if (!supabase) return json({ error: 'Supabase is not configured.' }, { status: 503 });
	if (!user) return json({ error: 'Authentication is required.' }, { status: 401 });
	if (!isUuid(farmId) || !isUuid(agentId)) {
		return json({ error: 'Invalid farm or collection agent id.' }, { status: 400 });
	}

	const { data, error } = await supabase
		.from('collection_agent_credentials')
		.select(
			'id, farm_id, agent_id, credential_version, secret_reference, secret_fingerprint_sha256, status, valid_from, expires_at, rotated_from_credential_id, change_reason_code, change_note, created_by, created_at, retired_by, retired_at, revoked_by, revoked_at, collection_agent_credential_events(id, credential_version, event_type, reason_code, note, changed_by, changed_at)'
		)
		.eq('farm_id', farmId)
		.eq('agent_id', agentId)
		.order('credential_version', { ascending: false });

	if (error) {
		console.error('Collection agent credential list failed:', error);
		return json({ error: 'Unable to load collection agent credentials.' }, { status: 500 });
	}

	return json({ credentials: data ?? [] });
};

export const POST: RequestHandler = async ({ params, request, locals }) => {
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
		const { data, error } = await supabase.rpc('rotate_collection_agent_credential', {
			target_farm_id: farmId,
			target_agent_id: agentId,
			expected_agent_version: expectedVersion(body.expected_version),
			expected_current_credential_id: optionalUuid(
				body.expected_current_credential_id,
				'expected_current_credential_id'
			),
			credential_secret_reference: vaultSecretReference(body.secret_reference),
			credential_fingerprint_sha256: credentialFingerprint(
				body.secret_fingerprint_sha256
			),
			credential_expires_at: optionalIsoTimestamp(body.expires_at, 'expires_at'),
			reason_code: normalizedReasonCode(body.reason_code),
			change_note: optionalText(body.note)
		});

		if (error) {
			console.error('Collection agent credential rotation failed:', error);
			return json(
				{ error: isVersionConflict(error) ? 'Collection agent version conflict.' : error.message },
				{ status: isVersionConflict(error) ? 409 : 400 }
			);
		}

		return json(data, { status: 201 });
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid credential rotation request.' },
			{ status: 400 }
		);
	}
};
