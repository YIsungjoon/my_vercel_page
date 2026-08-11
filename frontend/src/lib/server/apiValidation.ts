export function requiredText(value: unknown, field: string) {
	if (typeof value !== 'string' || !value.trim()) {
		throw new Error(field + ' is required.');
	}

	return value.trim();
}

export function optionalText(value: unknown) {
	return typeof value === 'string' && value.trim() ? value.trim() : null;
}

export function isUuid(value: string) {
	return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
		value
	);
}

export function requiredUuid(value: unknown, field: string) {
	const parsed = requiredText(value, field);
	if (!isUuid(parsed)) {
		throw new Error(field + ' must be a valid UUID.');
	}

	return parsed;
}

export function optionalUuid(value: unknown, field: string) {
	const parsed = optionalText(value);
	if (parsed && !isUuid(parsed)) {
		throw new Error(field + ' must be a valid UUID.');
	}

	return parsed;
}

export function uuidArray(value: unknown, field: string) {
	if (value === undefined || value === null) {
		return [];
	}
	if (!Array.isArray(value)) {
		throw new Error(field + ' must be an array of UUIDs.');
	}

	return [
		...new Set(value.map((item) => requiredUuid(item, field)))
	];
}

export function integerOrDefault(value: unknown, fallback: number, field: string) {
	if (value === undefined || value === null || value === '') {
		return fallback;
	}

	const parsed = Number(value);
	if (!Number.isInteger(parsed)) {
		throw new Error(field + ' must be an integer.');
	}

	return parsed;
}

export function optionalTimestamp(value: unknown, field: string) {
	const parsed = optionalText(value);
	if (parsed && Number.isNaN(Date.parse(parsed))) {
		throw new Error(field + ' must be an ISO timestamp.');
	}

	return parsed;
}
