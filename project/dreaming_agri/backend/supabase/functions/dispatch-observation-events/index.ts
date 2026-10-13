import { createClient } from 'npm:@supabase/supabase-js@2.110.5';

const TOPIC = 'observation.recorded.v1';
const WORKER_ID = Deno.env.get('OBSERVATION_DISPATCH_WORKER_ID') ?? 'observation-trigger-dispatcher';

type OutboxMessage = {
	id: string;
	farm_id: string;
	event_id: string;
	attempt_count: number;
};

type ClaimResponse = {
	claimed_count: number;
	messages: OutboxMessage[];
};

function boundedEnvironmentInteger(name: string, fallback: number, minimum: number, maximum: number) {
	const raw = Deno.env.get(name);
	if (!raw) return fallback;

	const parsed = Number(raw);
	if (!Number.isInteger(parsed) || parsed < minimum || parsed > maximum) {
		throw new Error(`${name} must be an integer between ${minimum} and ${maximum}.`);
	}

	return parsed;
}

function getAdminKey() {
	const secretKeys = Deno.env.get('SUPABASE_SECRET_KEYS');

	if (secretKeys) {
		const keys = JSON.parse(secretKeys) as Record<string, string>;
		const key = keys.default ?? Object.values(keys)[0];
		if (key) return key;
	}

	return Deno.env.get('SUPABASE_SECRET_KEY') ?? Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
}

function hasValidDispatchSecret(request: Request) {
	const expected = Deno.env.get('OBSERVATION_DISPATCH_SECRET');
	const supplied = request.headers.get('x-observation-dispatch-secret');

	if (!expected || !supplied || expected.length !== supplied.length) return false;

	let difference = 0;
	for (let index = 0; index < expected.length; index += 1) {
		difference |= expected.charCodeAt(index) ^ supplied.charCodeAt(index);
	}

	return difference === 0;
}

Deno.serve(async (request) => {
	if (request.method !== 'POST') {
		return Response.json({ error: 'Method not allowed' }, { status: 405 });
	}

	if (!hasValidDispatchSecret(request)) {
		return Response.json({ error: 'Unauthorized' }, { status: 401 });
	}

	try {
		const supabaseUrl = Deno.env.get('SUPABASE_URL');
		const adminKey = getAdminKey();
		if (!supabaseUrl || !adminKey) {
			throw new Error('Supabase function environment is not configured.');
		}

		const claimLimit = boundedEnvironmentInteger('OBSERVATION_DISPATCH_LIMIT', 20, 1, 100);
		const leaseSeconds = boundedEnvironmentInteger(
			'OBSERVATION_DISPATCH_LEASE_SECONDS',
			300,
			30,
			3600
		);
		const retryDelaySeconds = boundedEnvironmentInteger(
			'OBSERVATION_DISPATCH_RETRY_SECONDS',
			60,
			0,
			86400
		);
		const supabase = createClient(supabaseUrl, adminKey, {
			auth: { autoRefreshToken: false, persistSession: false }
		});
		const { data: claimData, error: claimError } = await supabase.rpc(
			'claim_outbox_topic_messages',
			{
				target_topic: TOPIC,
				worker_id: WORKER_ID,
				claim_limit: claimLimit,
				lease_seconds: leaseSeconds
			}
		);

		if (claimError) throw new Error(claimError.message);
		const claim = claimData as ClaimResponse;
		const processed: Array<{ message_id: string; event_id: string; consumption_id: string }> = [];
		const failed: Array<{ message_id: string; event_id: string; error: string }> = [];

		for (const message of claim.messages ?? []) {
			const { data: consumptionData, error: consumptionError } = await supabase.rpc(
				'consume_observation_outbox_message',
				{
					target_farm_id: message.farm_id,
					target_message_id: message.id,
					worker_id: WORKER_ID,
					attempt_no: message.attempt_count
				}
			);

			if (consumptionError) {
				const errorMessage = consumptionError.message;
				const { error: failureReceiptError } = await supabase.rpc('complete_outbox_delivery', {
					target_farm_id: message.farm_id,
					target_message_id: message.id,
					worker_id: WORKER_ID,
					attempt_no: message.attempt_count,
					delivery_succeeded: false,
					delivery_error_code: 'CONSUMER_FAILED',
					delivery_error_message: errorMessage,
					retry_delay_seconds: retryDelaySeconds
				});

				failed.push({
					message_id: message.id,
					event_id: message.event_id,
					error: failureReceiptError?.message ?? errorMessage
				});
				continue;
			}

			const { error: successReceiptError } = await supabase.rpc('complete_outbox_delivery', {
				target_farm_id: message.farm_id,
				target_message_id: message.id,
				worker_id: WORKER_ID,
				attempt_no: message.attempt_count,
				delivery_succeeded: true
			});

			if (successReceiptError) {
				failed.push({
					message_id: message.id,
					event_id: message.event_id,
					error: successReceiptError.message
				});
				continue;
			}

			processed.push({
				message_id: message.id,
				event_id: message.event_id,
				consumption_id: String(
					(consumptionData as { consumption?: { id?: string } } | null)?.consumption?.id ?? ''
				)
			});
		}

		return Response.json({
			topic: TOPIC,
			claimed_count: claim.claimed_count ?? 0,
			processed_count: processed.length,
			failed_count: failed.length,
			processed,
			failed
		});
	} catch (error) {
		console.error(error);
		return Response.json(
			{ error: error instanceof Error ? error.message : 'Unknown observation dispatch error.' },
			{ status: 500 }
		);
	}
});
