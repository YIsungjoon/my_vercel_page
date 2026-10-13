import { json } from '@sveltejs/kit';
import { isUuid, optionalText, requiredText } from '$agri/server/apiValidation';
import { expectedVersion, isVersionConflict } from '$agri/server/activityRuleValidation';
import {
	COLLECTION_AGENT_STATUSES,
	normalizedReasonCode
} from '$agri/server/observationValidation';
import type { RequestHandler } from './$types';

const AGENT_FIELDS =
	'id, farm_id, agent_code, name, agent_kind, status, authentication_mode, last_seen_at, version, status_reason_code, status_note, status_changed_at, created_by, updated_by, created_at, updated_at, collection_agent_sources(source_id, status, version, grant_reason_code, grant_note, granted_by, granted_at, revoked_by, revoked_at, revocation_reason_code, revocation_note, updated_at)';

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

	const [agentResult, statusResult, sourceResult, credentialResult] = await Promise.all([
		supabase
			.from('collection_agents')
			.select(AGENT_FIELDS)
			.eq('farm_id', farmId)
			.eq('id', agentId)
			.maybeSingle(),
		supabase
			.from('collection_agent_status_transitions')
			.select(
				'id, farm_id, agent_id, agent_version, from_status, to_status, reason_code, note, changed_by, changed_at'
			)
			.eq('farm_id', farmId)
			.eq('agent_id', agentId)
			.order('changed_at', { ascending: false }),
		supabase
			.from('collection_agent_source_grant_events')
			.select(
				'id, farm_id, agent_id, source_id, grant_version, event_type, reason_code, note, changed_by, changed_at'
			)
			.eq('farm_id', farmId)
			.eq('agent_id', agentId)
			.order('changed_at', { ascending: false }),
		supabase
			.from('collection_agent_credentials')
			.select(
				'id, farm_id, agent_id, credential_version, secret_reference, secret_fingerprint_sha256, status, valid_from, expires_at, rotated_from_credential_id, change_reason_code, change_note, created_by, created_at, retired_by, retired_at, revoked_by, revoked_at, collection_agent_credential_events(id, credential_version, event_type, reason_code, note, changed_by, changed_at)'
			)
			.eq('farm_id', farmId)
			.eq('agent_id', agentId)
			.order('credential_version', { ascending: false })
	]);

	const queryError =
		agentResult.error ?? statusResult.error ?? sourceResult.error ?? credentialResult.error;
	if (queryError) {
		console.error('Collection agent management detail query failed:', queryError);
		return json({ error: 'Unable to load collection agent management detail.' }, { status: 500 });
	}
	if (!agentResult.data) {
		return json({ error: 'Collection agent was not found.' }, { status: 404 });
	}

	return json({
		agent: agentResult.data,
		status_transitions: statusResult.data ?? [],
		source_grant_events: sourceResult.data ?? [],
		credentials: credentialResult.data ?? []
	});
};

export const PATCH: RequestHandler = async ({ params, request, locals }) => {
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
		const status = requiredText(body.status, 'status');
		if (!COLLECTION_AGENT_STATUSES.includes(status)) {
			throw new Error('status is not supported.');
		}

		const { data, error } = await supabase.rpc('transition_collection_agent_status', {
			target_farm_id: farmId,
			target_agent_id: agentId,
			expected_version: expectedVersion(body.expected_version),
			target_status: status,
			reason_code: normalizedReasonCode(body.reason_code),
			status_note: optionalText(body.note)
		});

		if (error) {
			console.error('Collection agent status transition failed:', error);
			return json(
				{ error: isVersionConflict(error) ? 'Collection agent version conflict.' : error.message },
				{ status: isVersionConflict(error) ? 409 : 400 }
			);
		}

		return json(data);
	} catch (error) {
		return json(
			{ error: error instanceof Error ? error.message : 'Invalid collection agent status request.' },
			{ status: 400 }
		);
	}
};
