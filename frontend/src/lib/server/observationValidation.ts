import {
	integerOrDefault,
	optionalText,
	requiredText
} from '$lib/server/apiValidation';

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
