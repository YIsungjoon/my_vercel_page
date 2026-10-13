import {
	integerOrDefault,
	optionalText,
	requiredText
} from '$agri/server/apiValidation';

export const OBSERVATION_SOURCE_KINDS = [
	'WEATHER_API',
	'SENSOR_DEVICE',
	'SENSOR_GATEWAY',
	'MANUAL',
	'SYSTEM'
];

export const SOURCE_QUALITY_STATUSES = ['VALID', 'SUSPECT', 'INVALID'];
export const DERIVED_QUALITY_STATUSES = [
	'VALID',
	'SUSPECT',
	'INVALID',
	'LATE',
	'UNCALIBRATED'
];
export const OBSERVATION_SEQUENCE_POLICIES = ['NONE', 'MONOTONIC_INTEGER'];

export const COLLECTION_AGENT_KINDS = [
	'WEATHER_COLLECTOR',
	'SENSOR_GATEWAY',
	'DATA_IMPORTER',
	'SYSTEM_INTEGRATION'
];
export const COLLECTION_AGENT_STATUSES = ['ACTIVE', 'PAUSED', 'REVOKED'];
export const COLLECTION_AGENT_CREDENTIAL_STATUSES = ['ACTIVE', 'RETIRED', 'REVOKED'];

export const INGEST_BATCH_STATUSES = ['OPEN', 'COMPLETED', 'PARTIAL', 'FAILED'];
export const OUTBOX_MESSAGE_STATUSES = [
	'PENDING',
	'CLAIMED',
	'PUBLISHED',
	'RETRY',
	'DEAD_LETTER'
];

export function normalizedReasonCode(value: unknown, field = 'reason_code') {
	const parsed = requiredText(value, field);
	if (!/^[A-Z][A-Z0-9_]*$/.test(parsed)) {
		throw new Error(field + ' must use uppercase letters, digits, and underscores.');
	}

	return parsed;
}

export function vaultSecretReference(value: unknown) {
	const parsed = requiredText(value, 'secret_reference');
	if (
		parsed.length > 255 ||
		!/^vault:\/\/[A-Za-z0-9][A-Za-z0-9_./:-]*$/.test(parsed)
	) {
		throw new Error('secret_reference must be a valid vault:// reference.');
	}

	return parsed;
}

export function credentialFingerprint(value: unknown) {
	const parsed = requiredText(value, 'secret_fingerprint_sha256').toLowerCase();
	if (!/^[0-9a-f]{64}$/.test(parsed)) {
		throw new Error('secret_fingerprint_sha256 must be a SHA-256 fingerprint.');
	}

	return parsed;
}

export function requiredTimestamp(value: unknown, field: string) {
	const parsed = requiredText(value, field);
	if (Number.isNaN(Date.parse(parsed))) {
		throw new Error(field + ' must be an ISO timestamp.');
	}

	return new Date(parsed).toISOString();
}

export function optionalIsoTimestamp(value: unknown, field: string) {
	const parsed = optionalText(value);
	if (!parsed) {
		return null;
	}
	if (Number.isNaN(Date.parse(parsed))) {
		throw new Error(field + ' must be an ISO timestamp.');
	}

	return new Date(parsed).toISOString();
}

export function boundedInteger(
	value: unknown,
	fallback: number,
	field: string,
	minimum: number,
	maximum: number
) {
	const parsed = integerOrDefault(value, fallback, field);
	if (parsed < minimum || parsed > maximum) {
		throw new Error(
			field + ' must be between ' + minimum + ' and ' + maximum + '.'
		);
	}

	return parsed;
}

export function observationValues(body: Record<string, unknown>) {
	const hasNumeric = body.numeric_value !== undefined && body.numeric_value !== null;
	const text = optionalText(body.text_value);
	const hasText = text !== null;
	const hasBoolean = typeof body.boolean_value === 'boolean';

	if (Number(hasNumeric) + Number(hasText) + Number(hasBoolean) !== 1) {
		throw new Error('Exactly one typed observation value is required.');
	}

	const numeric = hasNumeric ? Number(body.numeric_value) : null;
	if (numeric !== null && !Number.isFinite(numeric)) {
		throw new Error('numeric_value must be finite.');
	}

	return {
		numeric_value: numeric,
		text_value: text,
		boolean_value: hasBoolean ? (body.boolean_value as boolean) : null
	};
}
