export type GrowthStage = '육묘기' | '영양생장기' | '생식생장기' | '수확기' | '수확후정리';

export type TaskCategory = '관수/시비' | '환경관리' | '병해충방제' | '수확/정리' | '후속작업' | '기타';

export type TaskStatus = 'pending' | 'completed' | 'skipped' | 'issue';

export type TaskPriority = 'high' | 'medium' | 'low';

export type IssueCategory = '병해충' | '시설/장비 고장' | '기상/생육 이상' | '자재 부족' | '기타';

export type AgriOperationTypeCode =
	| 'irrigation_fertigation'
	| 'environment_control'
	| 'pest_disease_control'
	| 'harvest_postharvest'
	| 'follow_up'
	| 'other';

export type WorkAreaType =
	| 'farm'
	| 'field'
	| 'block'
	| 'greenhouse'
	| 'house'
	| 'bay'
	| 'bed'
	| 'zone'
	| 'facility';

export interface Farm {
	id: string;
	name: string;
	region: string;
	cultivation_cycle_id?: string;
	crop: string;
	variety: string;
	planted_at: string; // YYYY-MM-DD
	growth_stage: GrowthStage;
	notes?: string;
	created_at?: string;
}

export interface Task {
	id: string;
	farm_id: string;
	cultivation_cycle_id?: string;
	operation_type_code?: AgriOperationTypeCode;
	work_area_ids?: string[];
	title: string;
	description?: string;
	scheduled_date: string; // YYYY-MM-DD
	category: TaskCategory;
	status: TaskStatus;
	priority: TaskPriority;
	is_followup: boolean;
	parent_task_id?: string;
	created_at?: string;
}

export interface TaskLog {
	id: string;
	task_id: string;
	farm_id: string;
	actor_id?: string;
	action: 'completed' | 'skipped' | 'issue';
	note: string;
	photo_url?: string;
	issue_category?: IssueCategory;
	created_at: string;
}

export interface AgriOperationType {
	code: AgriOperationTypeCode;
	name_ko: string;
	description?: string;
	sort_order: number;
	is_active: boolean;
}

export interface FarmWorkArea {
	id: string;
	farm_id: string;
	parent_area_id?: string;
	code: string;
	name: string;
	area_type: WorkAreaType;
	area_m2?: number;
	is_active: boolean;
	created_at?: string;
	updated_at?: string;
}

export type ScheduleProjectStatus =
	| 'PLANNED'
	| 'ACTIVE'
	| 'COMPLETED'
	| 'ON_HOLD'
	| 'CANCELLED';

export type PercentCompleteType = 'DURATION' | 'UNITS' | 'PHYSICAL';

export type ScheduleActivityType =
	| 'TASK_DEPENDENT'
	| 'RESOURCE_DEPENDENT'
	| 'LEVEL_OF_EFFORT'
	| 'START_MILESTONE'
	| 'FINISH_MILESTONE'
	| 'WBS_SUMMARY';

export type ScheduleActivityStatus = 'NOT_STARTED' | 'IN_PROGRESS' | 'COMPLETED';

export type ActivityRelationshipType = 'FS' | 'SS' | 'FF' | 'SF';

export interface ScheduleProject {
	id: string;
	farm_id: string;
	cultivation_cycle_id?: string;
	project_code: string;
	name: string;
	description?: string;
	status: ScheduleProjectStatus;
	planned_start_at?: string;
	planned_finish_at?: string;
	data_date?: string;
	timezone: string;
	default_percent_complete_type: PercentCompleteType;
	default_calendar_id?: string;
	version: number;
	created_at: string;
	updated_at: string;
}

export interface ScheduleCalendar {
	id: string;
	farm_id: string;
	project_id: string;
	base_calendar_id?: string;
	calendar_code: string;
	name: string;
	calendar_scope: 'PROJECT';
	timezone: string;
	minutes_per_day: number;
	minutes_per_week: number;
}

export interface ScheduleCalendarWorkingPeriod {
	id: string;
	farm_id: string;
	project_id: string;
	calendar_id: string;
	weekday: number;
	start_time: string;
	end_time: string;
}

export interface ScheduleWbsNode {
	id: string;
	farm_id: string;
	project_id: string;
	parent_id?: string;
	wbs_code: string;
	name: string;
	description?: string;
	sequence_no: number;
}

export interface ScheduleActivity {
	id: string;
	farm_id: string;
	project_id: string;
	wbs_id: string;
	calendar_id: string;
	cultivation_cycle_id?: string;
	operation_type_code: AgriOperationTypeCode;
	activity_code: string;
	name: string;
	description?: string;
	activity_type: ScheduleActivityType;
	status: ScheduleActivityStatus;
	percent_complete_type: PercentCompleteType;
	planned_start_at?: string;
	planned_finish_at?: string;
	planned_duration_minutes: number;
	actual_start_at?: string;
	actual_finish_at?: string;
	remaining_duration_minutes?: number;
	primary_constraint_type?: string;
	primary_constraint_at?: string;
	work_area_ids?: string[];
	version: number;
}

export interface ScheduleActivityRelationship {
	id: string;
	farm_id: string;
	project_id: string;
	predecessor_activity_id: string;
	successor_activity_id: string;
	relationship_type: ActivityRelationshipType;
	lag_minutes: number;
}

export type ActivityRuleStatus = 'DRAFT' | 'ACTIVE' | 'PAUSED' | 'ARCHIVED';

export interface ActivityTemplate {
	id: string;
	farm_id: string;
	template_code: string;
	name: string;
	description?: string;
	operation_type_code: AgriOperationTypeCode;
	activity_type: ScheduleActivityType;
	percent_complete_type: PercentCompleteType;
	default_duration_minutes: number;
	is_active: boolean;
	version: number;
	created_at: string;
	updated_at: string;
}

export interface ActivityRecurrenceWeekday {
	farm_id: string;
	project_id: string;
	recurrence_rule_id: string;
	weekday: number;
	created_at?: string;
}

export interface ActivityRecurrenceRule {
	id: string;
	farm_id: string;
	project_id: string;
	template_id: string;
	wbs_id: string;
	calendar_id: string;
	cultivation_cycle_id?: string;
	rule_code: string;
	name: string;
	status: ActivityRuleStatus;
	frequency: 'DAILY' | 'WEEKLY' | 'MONTHLY';
	interval_count: number;
	day_of_month?: number;
	starts_on: string;
	ends_on?: string;
	occurrence_time: string;
	timezone: string;
	generation_horizon_days: number;
	activity_recurrence_weekdays?: Pick<ActivityRecurrenceWeekday, 'weekday'>[];
	version: number;
	created_at: string;
	updated_at: string;
}

export type ActivityTriggerEventType =
	| 'WEATHER_OBSERVATION'
	| 'SENSOR_OBSERVATION'
	| 'TASK_ACTION'
	| 'GROWTH_STAGE_CHANGE'
	| 'MANUAL';

export interface ActivityTriggerPredicate {
	id: string;
	farm_id: string;
	project_id: string;
	trigger_rule_id: string;
	sequence_no: number;
	source_field_code: string;
	comparison_operator: 'GT' | 'GTE' | 'LT' | 'LTE' | 'EQ' | 'NEQ';
	numeric_value?: number;
	text_value?: string;
	boolean_value?: boolean;
	unit_code?: string;
	observation_window_minutes?: number;
	created_at?: string;
}

export interface ActivityTriggerRuleWorkArea {
	farm_id: string;
	project_id: string;
	trigger_rule_id: string;
	work_area_id: string;
	is_primary: boolean;
	created_at?: string;
}

export interface ActivityTriggerRule {
	id: string;
	farm_id: string;
	project_id: string;
	template_id: string;
	wbs_id: string;
	calendar_id: string;
	cultivation_cycle_id?: string;
	rule_code: string;
	name: string;
	status: ActivityRuleStatus;
	event_type: ActivityTriggerEventType;
	predicate_match_mode: 'ALL' | 'ANY';
	cooldown_minutes: number;
	valid_from?: string;
	valid_until?: string;
	activity_trigger_predicates?: ActivityTriggerPredicate[];
	activity_trigger_rule_work_areas?: ActivityTriggerRuleWorkArea[];
	version: number;
	created_at: string;
	updated_at: string;
}

export interface ActivityRuleRun {
	id: string;
	farm_id: string;
	project_id: string;
	run_kind: 'RECURRENCE_MATERIALIZATION' | 'TRIGGER_EVALUATION';
	recurrence_rule_id?: string;
	trigger_rule_id?: string;
	source_rule_version: number;
	source_template_version: number;
	idempotency_key: string;
	window_start_date?: string;
	window_end_date?: string;
	status: 'RUNNING' | 'SUCCEEDED' | 'FAILED' | 'SKIPPED';
	outcome_code?: string;
	started_at: string;
	finished_at?: string;
	created_by?: string;
	execution_worker_id?: string;
	created_at: string;
}

export interface ActivityProposalWorkArea {
	farm_id: string;
	project_id: string;
	proposal_id: string;
	work_area_id: string;
	is_primary: boolean;
	created_at?: string;
}

export interface ActivityProposalDecision {
	id: string;
	farm_id: string;
	project_id: string;
	proposal_id: string;
	decision: 'APPROVED' | 'REJECTED';
	reason_code?: string;
	note?: string;
	decided_by: string;
	decided_at: string;
}

export interface ActivityProposalApplication {
	id: string;
	farm_id: string;
	project_id: string;
	proposal_id: string;
	activity_id: string;
	idempotency_key: string;
	applied_by: string;
	applied_at: string;
}

export interface ActivityProposal {
	id: string;
	farm_id: string;
	project_id: string;
	rule_run_id: string;
	proposal_key: string;
	template_id: string;
	template_version: number;
	wbs_id: string;
	calendar_id: string;
	cultivation_cycle_id?: string;
	operation_type_code: AgriOperationTypeCode;
	activity_code: string;
	name: string;
	description?: string;
	activity_type: ScheduleActivityType;
	percent_complete_type: PercentCompleteType;
	planned_start_at: string;
	planned_finish_at: string;
	planned_duration_minutes: number;
	status: 'PROPOSED' | 'APPROVED' | 'REJECTED' | 'APPLIED';
	version: number;
	activity_proposal_work_areas?: ActivityProposalWorkArea[];
	activity_proposal_decisions?: ActivityProposalDecision[];
	activity_proposal_applications?: ActivityProposalApplication[];
	created_by?: string;
	updated_by?: string;
	created_by_worker_id?: string;
	updated_by_worker_id?: string;
	created_at: string;
	updated_at: string;
}

export interface MeasurementUnit {
	code: string;
	name: string;
	symbol: string;
	quantity_kind: string;
	is_active: boolean;
}

export interface ObservationField {
	code: string;
	name: string;
	event_type: 'WEATHER_OBSERVATION' | 'SENSOR_OBSERVATION';
	value_type: 'NUMERIC' | 'TEXT' | 'BOOLEAN';
	canonical_unit_code?: string;
	is_active: boolean;
}

export interface ObservationSource {
	id: string;
	farm_id: string;
	source_code: string;
	name: string;
	source_kind:
		| 'WEATHER_API'
		| 'SENSOR_DEVICE'
		| 'SENSOR_GATEWAY'
		| 'MANUAL'
		| 'SYSTEM';
	provider_code?: string;
	external_reference?: string;
	is_active: boolean;
	created_by: string;
	created_at: string;
	updated_at: string;
}

export interface ObservationStream {
	id: string;
	farm_id: string;
	source_id: string;
	work_area_id?: string;
	field_code: string;
	stream_code: string;
	name: string;
	unit_code?: string;
	max_latency_minutes: number;
	quality_policy_version: number;
	sequence_policy: 'NONE' | 'MONOTONIC_INTEGER';
	clock_drift_tolerance_seconds: number;
	quality_policy_updated_by: string;
	requires_calibration: boolean;
	is_active: boolean;
	created_by: string;
	created_at: string;
	updated_at: string;
}

export interface ObservationQualityFinding {
	id: string;
	finding_code: string;
	severity: 'WARNING' | 'ERROR';
	detail?: string;
	detected_at: string;
}

export interface ObservationTransportQualityReceipt {
	observation_id: string;
	farm_id: string;
	stream_id: string;
	policy_version: number;
	sequence_policy: 'NONE' | 'MONOTONIC_INTEGER';
	source_sequence_value?: number | string;
	previous_high_watermark?: number | string;
	sequence_status:
		| 'NOT_TRACKED'
		| 'FIRST'
		| 'CONTIGUOUS'
		| 'GAP'
		| 'OUT_OF_ORDER'
		| 'DUPLICATE';
	missing_sequence_count: number | string;
	sequence_state_advanced: boolean;
	clock_drift_seconds: number;
	clock_drift_tolerance_seconds: number;
	clock_status: 'WITHIN_TOLERANCE' | 'CLOCK_AHEAD';
	evaluated_at: string;
}

export interface ObservationStreamQualityPolicyVersion {
	id: string;
	farm_id: string;
	stream_id: string;
	policy_version: number;
	sequence_policy: 'NONE' | 'MONOTONIC_INTEGER';
	clock_drift_tolerance_seconds: number;
	reason_code: string;
	note?: string;
	changed_by: string;
	changed_at: string;
}

export interface ObservationStreamSequenceState {
	stream_id: string;
	farm_id: string;
	policy_version: number;
	last_sequence_value?: number | string;
	last_observation_id?: string;
	last_observed_at?: string;
	receipt_count: number | string;
	anomaly_count: number | string;
	version: number | string;
	updated_at: string;
}

export interface StreamObservation {
	id: string;
	farm_id: string;
	source_id: string;
	stream_id: string;
	calibration_id?: string;
	observed_at: string;
	received_at: string;
	numeric_value?: number;
	text_value?: string;
	boolean_value?: boolean;
	source_quality_status: 'VALID' | 'SUSPECT' | 'INVALID';
	quality_status: 'VALID' | 'SUSPECT' | 'INVALID' | 'LATE' | 'UNCALIBRATED';
	source_sequence?: string;
	idempotency_key: string;
	recorded_by?: string;
	collector_agent_id?: string;
	ingest_batch_id?: string;
	observation_quality_findings?: ObservationQualityFinding[];
	observation_transport_quality_receipts?: ObservationTransportQualityReceipt;
	created_at: string;
}

export type CollectionAgentKind =
	| 'WEATHER_COLLECTOR'
	| 'SENSOR_GATEWAY'
	| 'DATA_IMPORTER'
	| 'SYSTEM_INTEGRATION';

export type CollectionAgentStatus = 'ACTIVE' | 'PAUSED' | 'REVOKED';
export type CollectionAgentCredentialStatus = 'ACTIVE' | 'RETIRED' | 'REVOKED';

export interface CollectionAgentSourceGrant {
	farm_id: string;
	agent_id: string;
	source_id: string;
	status: 'ACTIVE' | 'REVOKED';
	version: number;
	grant_reason_code: string;
	grant_note?: string;
	granted_by: string;
	granted_at: string;
	revoked_by?: string;
	revoked_at?: string;
	revocation_reason_code?: string;
	revocation_note?: string;
	updated_at: string;
}

export interface CollectionAgentStatusTransition {
	id: string;
	farm_id: string;
	agent_id: string;
	agent_version: number;
	from_status?: CollectionAgentStatus;
	to_status: CollectionAgentStatus;
	reason_code: string;
	note?: string;
	changed_by: string;
	changed_at: string;
}

export interface CollectionAgentSourceGrantEvent {
	id: string;
	farm_id: string;
	agent_id: string;
	source_id: string;
	grant_version: number;
	event_type: 'GRANTED' | 'REVOKED';
	reason_code: string;
	note?: string;
	changed_by: string;
	changed_at: string;
}

export interface CollectionAgentCredentialEvent {
	id: string;
	farm_id: string;
	agent_id: string;
	credential_id: string;
	credential_version: number;
	event_type: 'REGISTERED' | 'ROTATED' | 'RETIRED' | 'REVOKED';
	reason_code: string;
	note?: string;
	changed_by: string;
	changed_at: string;
}

export interface CollectionAgentCredential {
	id: string;
	farm_id: string;
	agent_id: string;
	credential_version: number;
	secret_reference: string;
	secret_fingerprint_sha256: string;
	status: CollectionAgentCredentialStatus;
	valid_from: string;
	expires_at?: string;
	rotated_from_credential_id?: string;
	change_reason_code: string;
	change_note?: string;
	created_by: string;
	created_at: string;
	retired_by?: string;
	retired_at?: string;
	revoked_by?: string;
	revoked_at?: string;
	collection_agent_credential_events?: CollectionAgentCredentialEvent[];
}

export interface CollectionAgent {
	id: string;
	farm_id: string;
	agent_code: string;
	name: string;
	agent_kind: CollectionAgentKind;
	status: CollectionAgentStatus;
	authentication_mode: 'PLATFORM_SERVICE_ROLE';
	last_seen_at?: string;
	version: number;
	status_reason_code: string;
	status_note?: string;
	status_changed_at: string;
	created_by: string;
	updated_by: string;
	created_at: string;
	updated_at: string;
	collection_agent_sources?: CollectionAgentSourceGrant[];
}

export interface CollectionAgentManagementDetail {
	agent: CollectionAgent;
	status_transitions: CollectionAgentStatusTransition[];
	source_grant_events: CollectionAgentSourceGrantEvent[];
	credentials: CollectionAgentCredential[];
}

export interface ObservationIngestBatch {
	id: string;
	farm_id: string;
	agent_id: string;
	source_id: string;
	external_batch_key: string;
	status: 'OPEN' | 'COMPLETED' | 'PARTIAL' | 'FAILED';
	expected_count?: number;
	accepted_count: number;
	rejected_count: number;
	failure_code?: string;
	failure_message?: string;
	started_at: string;
	finished_at?: string;
	created_at: string;
	updated_at: string;
}

export interface DomainEvent {
	id: string;
	farm_id: string;
	source_id: string;
	stream_id: string;
	observation_id: string;
	collector_agent_id?: string;
	ingest_batch_id?: string;
	event_name: 'OBSERVATION_RECORDED';
	observation_event_type: 'WEATHER_OBSERVATION' | 'SENSOR_OBSERVATION';
	occurred_at: string;
	recorded_at: string;
}

export interface OutboxMessage {
	id: string;
	farm_id: string;
	event_id: string;
	topic: string;
	status: 'PENDING' | 'CLAIMED' | 'PUBLISHED' | 'RETRY' | 'DEAD_LETTER';
	attempt_count: number;
	max_attempts: number;
	available_at: string;
	locked_at?: string;
	locked_by?: string;
	published_at?: string;
	last_error_code?: string;
	last_error_message?: string;
	created_at: string;
	updated_at: string;
}

export interface ObservationEventConsumption {
	id: string;
	farm_id: string;
	event_id: string;
	outbox_message_id: string;
	worker_id: string;
	status: 'PROCESSING' | 'COMPLETED';
	matching_rule_count: number;
	evaluated_rule_count: number;
	reused_rule_count: number;
	started_at: string;
	finished_at?: string;
	observation_event_rule_consumptions?: ObservationEventRuleConsumption[];
	created_at: string;
}

export interface ObservationEventRuleConsumption {
	id: string;
	farm_id: string;
	event_id: string;
	consumption_id: string;
	project_id: string;
	trigger_rule_id: string;
	source_rule_version: number;
	rule_run_id: string;
	dispatch_status: 'EVALUATED' | 'REUSED';
	created_at: string;
}

export interface ActivityTriggerEvaluation {
	rule_run_id: string;
	farm_id: string;
	project_id: string;
	trigger_rule_id: string;
	source_rule_version: number;
	evaluated_at: string;
	event_type: 'WEATHER_OBSERVATION' | 'SENSOR_OBSERVATION';
	match_mode: 'ALL' | 'ANY';
	predicate_count: number;
	matched_count: number;
	insufficient_count: number;
	created_at: string;
}

export interface ActivityTriggerPredicateEvaluation {
	id: string;
	farm_id: string;
	project_id: string;
	rule_run_id: string;
	trigger_predicate_id: string;
	predicate_sequence_no: number;
	source_field_code: string;
	comparison_operator: 'GT' | 'GTE' | 'LT' | 'LTE' | 'EQ' | 'NEQ';
	expected_numeric_value?: number;
	expected_text_value?: string;
	expected_boolean_value?: boolean;
	expected_unit_code?: string;
	observation_id?: string;
	observation_stream_id?: string;
	observed_numeric_value?: number;
	observed_text_value?: string;
	observed_boolean_value?: boolean;
	observed_unit_code?: string;
	observed_at?: string;
	observation_quality_status?: StreamObservation['quality_status'];
	result_status: 'MATCHED' | 'NOT_MATCHED' | 'INSUFFICIENT';
	reason_code?: string;
	created_at: string;
}

export interface TaskActivityLink {
	farm_id: string;
	project_id: string;
	task_id: string;
	activity_id: string;
	link_type: 'MIGRATED' | 'EXECUTION' | 'FOLLOW_UP' | 'REFERENCE';
	is_primary: boolean;
	created_at: string;
}

export interface AIConsultation {
	id: string;
	farm_id: string;
	question: string;
	answer: string;
	summary_report?: string;
	created_at: string;
}

export interface FarmAdminSummary {
	farm: Farm;
	pending_count: number;
	completed_count: number;
	issue_count: number;
	recurring_issues: { category: IssueCategory; count: number }[];
	recent_logs: TaskLog[];
	risk_level: 'normal' | 'warning' | 'danger';
}
