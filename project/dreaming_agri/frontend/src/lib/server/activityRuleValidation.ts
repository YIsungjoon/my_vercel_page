import {
	integerOrDefault,
	optionalText,
	requiredText
} from '$agri/server/apiValidation';

export const ACTIVITY_TYPES = [
	'TASK_DEPENDENT',
	'RESOURCE_DEPENDENT',
	'LEVEL_OF_EFFORT',
	'START_MILESTONE',
	'FINISH_MILESTONE',
	'WBS_SUMMARY'
];
export const PERCENT_TYPES = ['DURATION', 'UNITS', 'PHYSICAL'];
export const RULE_STATUSES = ['DRAFT', 'ACTIVE', 'PAUSED', 'ARCHIVED'];
export const CREATE_RULE_STATUSES = ['DRAFT', 'ACTIVE'];
export const FREQUENCIES = ['DAILY', 'WEEKLY', 'MONTHLY'];
export const EVENT_TYPES = [
	'WEATHER_OBSERVATION',
	'SENSOR_OBSERVATION',
	'TASK_ACTION',
	'GROWTH_STAGE_CHANGE',
	'MANUAL'
];
export const MATCH_MODES = ['ALL', 'ANY'];
export const COMPARISON_OPERATORS = ['GT', 'GTE', 'LT', 'LTE', 'EQ', 'NEQ'];

export interface ParsedPredicate {
	source_field_code: string;
	comparison_operator: string;
	numeric_value: number | null;
	text_value: string | null;
	boolean_value: boolean | null;
	unit_code: string | null;
	observation_window_minutes: number | null;
}

export function expectedVersion(value: unknown) {
	const version = integerOrDefault(value, 0, 'expected_version');
	if (version < 1) {
		throw new Error('expected_version must be at least 1.');
	}

	return version;
}

export function dateValue(value: unknown, field: string, required = false) {
	const parsed = required ? requiredText(value, field) : optionalText(value);
	if (!parsed) {
		return null;
	}

	const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(parsed);
	if (!match) {
		throw new Error(field + ' must use YYYY-MM-DD.');
	}

	const year = Number(match[1]);
	const month = Number(match[2]);
	const day = Number(match[3]);
	const date = new Date(Date.UTC(year, month - 1, day));
	if (
		date.getUTCFullYear() !== year ||
		date.getUTCMonth() !== month - 1 ||
		date.getUTCDate() !== day
	) {
		throw new Error(field + ' must be a valid date.');
	}

	return parsed;
}

export function timeValue(value: unknown) {
	const parsed = requiredText(value, 'occurrence_time');
	if (!/^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$/.test(parsed)) {
		throw new Error('occurrence_time must use HH:MM or HH:MM:SS.');
	}

	return parsed;
}

export function weekdayValues(value: unknown) {
	if (value === undefined || value === null) {
		return [];
	}
	if (!Array.isArray(value)) {
		throw new Error('weekdays must be an array.');
	}

	const weekdays = value.map((item) => integerOrDefault(item, -1, 'weekday'));
	if (weekdays.some((weekday) => weekday < 0 || weekday > 6)) {
		throw new Error('Each weekday must be between 0 and 6.');
	}

	return [...new Set(weekdays)].sort((left, right) => left - right);
}

export function predicateValues(value: unknown): ParsedPredicate[] {
	if (value === undefined || value === null) {
		return [];
	}
	if (!Array.isArray(value)) {
		throw new Error('predicates must be an array.');
	}

	return value.map((raw, index) => {
		if (!raw || typeof raw !== 'object') {
			throw new Error('Predicate ' + (index + 1) + ' must be an object.');
		}

		const predicate = raw as Record<string, unknown>;
		const operator = requiredText(
			predicate.comparison_operator,
			'comparison_operator'
		);
		if (!COMPARISON_OPERATORS.includes(operator)) {
			throw new Error('Predicate ' + (index + 1) + ' comparison_operator is not supported.');
		}

		const hasNumeric =
			predicate.numeric_value !== undefined && predicate.numeric_value !== null;
		const text = optionalText(predicate.text_value);
		const hasText = text !== null;
		const hasBoolean = typeof predicate.boolean_value === 'boolean';

		if (Number(hasNumeric) + Number(hasText) + Number(hasBoolean) !== 1) {
			throw new Error(
				'Predicate ' + (index + 1) + ' requires exactly one typed comparison value.'
			);
		}

		const numeric = hasNumeric ? Number(predicate.numeric_value) : null;
		if (numeric !== null && !Number.isFinite(numeric)) {
			throw new Error('Predicate ' + (index + 1) + ' numeric_value must be finite.');
		}

		const unit = optionalText(predicate.unit_code);
		if (unit && numeric === null) {
			throw new Error('Predicate ' + (index + 1) + ' unit_code requires numeric_value.');
		}

		const windowMinutes =
			predicate.observation_window_minutes === undefined ||
			predicate.observation_window_minutes === null
				? null
				: integerOrDefault(
						predicate.observation_window_minutes,
						0,
						'observation_window_minutes'
					);
		if (windowMinutes !== null && windowMinutes < 0) {
			throw new Error(
				'Predicate ' + (index + 1) + ' observation_window_minutes must be non-negative.'
			);
		}

		return {
			source_field_code: requiredText(
				predicate.source_field_code,
				'source_field_code'
			),
			comparison_operator: operator,
			numeric_value: numeric,
			text_value: text,
			boolean_value: hasBoolean ? (predicate.boolean_value as boolean) : null,
			unit_code: unit,
			observation_window_minutes: windowMinutes
		};
	});
}

export function isVersionConflict(error: { code?: string } | null) {
	return error?.code === '40001';
}
