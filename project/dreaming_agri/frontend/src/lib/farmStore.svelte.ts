import type { Farm, Task, TaskLog, AIConsultation, FarmAdminSummary, TaskStatus, IssueCategory, GrowthStage, TaskCategory, TaskPriority } from './types';

// Initial Mock Seed Data
const initialFarms: Farm[] = [
	{
		id: 'farm-1',
		name: '김제 스마트 토마토 농장',
		region: '전북특별자치도 김제시',
		crop: '토마토',
		variety: '마이노르',
		planted_at: '2026-03-15',
		growth_stage: '생식생장기',
		notes: '스마트온실 A동 (1,200평). 3화방 착과 중.'
	},
	{
		id: 'farm-2',
		name: '성주 꿀 참외 농장',
		region: '경상북도 성주군',
		crop: '참외',
		variety: '꿀봉',
		planted_at: '2026-02-10',
		growth_stage: '수확기',
		notes: '비닐하우스 4동. 2차 수확 진행 중.'
	},
	{
		id: 'farm-3',
		name: '부여 유리온실 파프리카',
		region: '충청남도 부여군',
		crop: '파프리카',
		variety: '볼란테',
		planted_at: '2026-04-01',
		growth_stage: '영양생장기',
		notes: '양액 재배. 초세 관리 집중 구간.'
	}
];

const todayStr = new Date().toISOString().slice(0, 10);
const yesterdayStr = new Date(Date.now() - 86400000).toISOString().slice(0, 10);
const tomorrowStr = new Date(Date.now() + 86400000).toISOString().slice(0, 10);
const in3DaysStr = new Date(Date.now() + 86400000 * 3).toISOString().slice(0, 10);
const in5DaysStr = new Date(Date.now() + 86400000 * 5).toISOString().slice(0, 10);

const initialTasks: Task[] = [
	{
		id: 'task-101',
		farm_id: 'farm-1',
		title: '아침 영양 양액 2차 공급',
		description: 'EC 2.2, pH 5.8 설정으로 15분간 관수',
		scheduled_date: todayStr,
		category: '관수/시비' as TaskCategory,
		status: 'completed' as TaskStatus,
		priority: 'high' as TaskPriority,
		is_followup: false
	},
	{
		id: 'task-102',
		farm_id: 'farm-1',
		title: '3화방 곁순 제거 및 적엽',
		description: '하부 노화엽 2장 제거 및 통풍 확보',
		scheduled_date: todayStr,
		category: '환경관리' as TaskCategory,
		status: 'issue' as TaskStatus,
		priority: 'medium' as TaskPriority,
		is_followup: false
	},
	{
		id: 'task-103',
		farm_id: 'farm-1',
		title: '[후속작업] 흰가루병 의심 구역 2차 방제 및 격리 점검',
		description: '3화방 하부 잎 점박이 발견으로 친환경 방제제 점검 후 살포',
		scheduled_date: tomorrowStr,
		category: '후속작업' as TaskCategory,
		status: 'pending' as TaskStatus,
		priority: 'high' as TaskPriority,
		is_followup: true,
		parent_task_id: 'task-102'
	},
	{
		id: 'task-104',
		farm_id: 'farm-1',
		title: '온실 측창 자동 환기 센서 점검',
		description: '30도 이상 상승 시 환기창 정상 작동 확인',
		scheduled_date: todayStr,
		category: '환경관리' as TaskCategory,
		status: 'pending' as TaskStatus,
		priority: 'low' as TaskPriority,
		is_followup: false
	},
	{
		id: 'task-105',
		farm_id: 'farm-1',
		title: '토마토 적색과 1차 수확 및 선별',
		description: '착색률 80% 이상 수확 후 규격 상자 포장',
		scheduled_date: in3DaysStr,
		category: '수확/정리' as TaskCategory,
		status: 'pending' as TaskStatus,
		priority: 'high' as TaskPriority,
		is_followup: false
	},
	{
		id: 'task-201',
		farm_id: 'farm-2',
		title: '참외 당도 측정 및 수확 작업',
		description: '14브릭스 이상 수확선별',
		scheduled_date: todayStr,
		category: '수확/정리' as TaskCategory,
		status: 'issue' as TaskStatus,
		priority: 'high' as TaskPriority,
		is_followup: false
	},
	{
		id: 'task-202',
		farm_id: 'farm-2',
		title: '양액 펌프 모터 소음 긴급 점검',
		description: '3동 수압 저하 현상 지속 발생',
		scheduled_date: todayStr,
		category: '환경관리' as TaskCategory,
		status: 'issue' as TaskStatus,
		priority: 'high' as TaskPriority,
		is_followup: false
	},
	{
		id: 'task-203',
		farm_id: 'farm-2',
		title: '[후속작업] 3동 수압 밸브 부품 교체',
		description: '펌프 압력 모듈 교체 후 시운전',
		scheduled_date: tomorrowStr,
		category: '후속작업' as TaskCategory,
		status: 'pending' as TaskStatus,
		priority: 'high' as TaskPriority,
		is_followup: true,
		parent_task_id: 'task-202'
	},
	{
		id: 'task-301',
		farm_id: 'farm-3',
		title: '파프리카 1차 가지 유인작업',
		description: '줄기 세력 균형을 위해 유인끈 고정',
		scheduled_date: todayStr,
		category: '환경관리' as TaskCategory,
		status: 'pending' as TaskStatus,
		priority: 'medium' as TaskPriority,
		is_followup: false
	},
	{
		id: 'task-302',
		farm_id: 'farm-3',
		title: '야간 차광막 스케줄 설정 확인',
		description: '야간 온실 내부 온도 18도 유지 설정',
		scheduled_date: in5DaysStr,
		category: '환경관리' as TaskCategory,
		status: 'pending' as TaskStatus,
		priority: 'low' as TaskPriority,
		is_followup: false
	}
];

const initialLogs: TaskLog[] = [
	{
		id: 'log-1',
		task_id: 'task-101',
		farm_id: 'farm-1',
		action: 'completed',
		note: '오전 08:30 양액 정상 공급 완료. EC 2.2 유지.',
		created_at: `${todayStr}T08:35:00Z`
	},
	{
		id: 'log-2',
		task_id: 'task-102',
		farm_id: 'farm-1',
		action: 'issue',
		note: '3화방 하부 잎에 흰색 분가루 형태 반점 다수 발견. 흰가루병 초기 증상 의심됨.',
		issue_category: '병해충',
		photo_url: 'https://images.unsplash.com/photo-1592417817098-8f3d6eb12735?w=600&auto=format&fit=crop&q=80',
		created_at: `${todayStr}T09:40:00Z`
	},
	{
		id: 'log-3',
		task_id: 'task-201',
		farm_id: 'farm-2',
		action: 'issue',
		note: '2동 하우스 일부 참외 잎 시듦 현상 발생. 덩굴쪼김병 관련 전문가 확인 필요.',
		issue_category: '병해충',
		photo_url: 'https://images.unsplash.com/photo-1591857177580-dc82b9ac4e1e?w=600&auto=format&fit=crop&q=80',
		created_at: `${todayStr}T10:15:00Z`
	},
	{
		id: 'log-4',
		task_id: 'task-202',
		farm_id: 'farm-2',
		action: 'issue',
		note: '3동 관수 라인 수압 밸브 고장으로 양액 공급 중단됨.',
		issue_category: '시설/장비 고장',
		created_at: `${yesterdayStr}T14:20:00Z`
	}
];

const initialConsultations: AIConsultation[] = [
	{
		id: 'cons-1',
		farm_id: 'farm-1',
		question: '토마토 3화방 착과기 흰가루병 발생 시 긴급 조치 방법은?',
		answer: '토마토 생식생장기(3화방 착과기) 흰가루병 방제를 위해서는 습도를 60-70% 수준으로 조절하고, 감염된 노화 엽을 먼저 수거 태우기 조치하세요. 미생물 제제(유황/탄산수소칼륨계) 친환경 방제제를 5일 간격으로 2회 연속 엽면 살포하는 것을 권장합니다.',
		created_at: `${todayStr}T10:00:00Z`
	}
];

// Reactive Store State using Svelte 5 Runes
class FarmStoreState {
	farms = $state<Farm[]>(initialFarms);
	selectedFarmId = $state<string>('farm-1');
	tasks = $state<Task[]>(initialTasks);
	logs = $state<TaskLog[]>(initialLogs);
	consultations = $state<AIConsultation[]>(initialConsultations);

	// Derived state
	currentFarm = $derived(
		this.farms.find((f) => f.id === this.selectedFarmId) ?? this.farms[0]
	);

	currentFarmTasks = $derived(
		this.tasks.filter((t) => t.farm_id === this.selectedFarmId)
	);

	todayTasks = $derived(
		this.currentFarmTasks.filter((t) => t.scheduled_date === todayStr)
	);

	weeklyTasks = $derived(
		this.currentFarmTasks.filter((t) => {
			const diffDays = (new Date(t.scheduled_date).getTime() - new Date(todayStr).getTime()) / 86400000;
			return diffDays >= -1 && diffDays <= 7;
		})
	);

	// Actions
	hydrateFromServer(farms: unknown[], tasks: unknown[]) {
		const text = (value: unknown, fallback = '') =>
			typeof value === 'string' && value.trim() ? value : fallback;

		const mappedFarms = farms
			.map((raw) => {
				if (!raw || typeof raw !== 'object') return null;
				const farm = raw as Record<string, unknown>;
				const cycles = Array.isArray(farm.cultivation_cycles)
					? (farm.cultivation_cycles as Record<string, unknown>[])
					: [];
				const cycle =
					cycles.find((item) => text(item.status) === 'active') ??
					cycles[0] ??
					({} as Record<string, unknown>);

				const id = text(farm.id);
				if (!id) return null;

				return {
					id,
					name: text(farm.name, 'Unnamed farm'),
					region: text(farm.region, 'Unknown region'),
					cultivation_cycle_id: text(cycle.id) || undefined,
					crop: text(cycle.crop, 'Unknown crop'),
					variety: text(cycle.variety, 'Unknown variety'),
					planted_at: text(cycle.planted_at, new Date().toISOString().slice(0, 10)),
					growth_stage: text(cycle.growth_stage) as GrowthStage,
					notes: text(cycle.notes) || undefined,
					created_at: text(farm.created_at) || undefined
				} satisfies Farm;
			})
			.filter(Boolean) as Farm[];

		const mappedTasks = tasks
			.map((raw) => {
				if (!raw || typeof raw !== 'object') return null;
				const task = raw as Record<string, unknown>;
				const id = text(task.id);
				const farmId = text(task.farm_id);
				if (!id || !farmId) return null;

				return {
					id,
					farm_id: farmId,
					cultivation_cycle_id: text(task.cultivation_cycle_id) || undefined,
					operation_type_code:
						(text(task.operation_type_code) as Task['operation_type_code']) || undefined,
					work_area_ids: Array.isArray(task.work_area_ids)
						? task.work_area_ids.filter((value): value is string => typeof value === 'string')
						: Array.isArray(task.task_work_areas)
							? (task.task_work_areas as Record<string, unknown>[])
									.map((link) => text(link.work_area_id))
									.filter(Boolean)
							: [],
					title: text(task.title, 'Untitled task'),
					description: text(task.description) || undefined,
					scheduled_date: text(task.scheduled_date),
					category: text(task.category) as TaskCategory,
					status: text(task.status, 'pending') as TaskStatus,
					priority: text(task.priority, 'medium') as TaskPriority,
					is_followup: task.is_followup === true,
					parent_task_id: text(task.parent_task_id) || undefined,
					created_at: text(task.created_at) || undefined
				} satisfies Task;
			})
			.filter(Boolean) as Task[];

		if (mappedFarms.length > 0) {
			this.farms = mappedFarms;
			if (!mappedFarms.some((farm) => farm.id === this.selectedFarmId)) {
				this.selectedFarmId = mappedFarms[0].id;
			}
		}

		if (mappedTasks.length > 0 || farms.length > 0) {
			this.tasks = mappedTasks;
		}

		this.logs = [];
		this.consultations = [];
	}
	selectFarm(farmId: string) {
		this.selectedFarmId = farmId;
	}

	addFarm(farmData: Omit<Farm, 'id' | 'created_at'>) {
		const newFarm: Farm = {
			...farmData,
			id: `farm-${Date.now()}`,
			created_at: new Date().toISOString()
		};
		this.farms = [newFarm, ...this.farms];
		this.selectedFarmId = newFarm.id;
		return newFarm;
	}

	addPersistedFarm(farm: Farm) {
		this.farms = [farm, ...this.farms.filter((existing) => existing.id !== farm.id)];
		this.selectedFarmId = farm.id;
		return farm;
	}
	updateFarm(id: string, updates: Partial<Farm>) {
		this.farms = this.farms.map((f) => (f.id === id ? { ...f, ...updates } : f));
	}

	addPersistedTask(task: Task) {
		this.tasks = [task, ...this.tasks.filter((existing) => existing.id !== task.id)];
		return task;
	}
	addTask(taskData: Omit<Task, 'id' | 'created_at' | 'status'> & { status?: TaskStatus }) {
		const newTask: Task = {
			...taskData,
			id: `task-${Date.now()}`,
			status: taskData.status ?? 'pending',
			created_at: new Date().toISOString()
		};
		this.tasks = [newTask, ...this.tasks];
		return newTask;
	}

	addPersistedLog(log: TaskLog) {
		this.logs = [log, ...this.logs.filter((existing) => existing.id !== log.id)];
		return log;
	}
	logTaskAction(params: {
		task_id: string;
		action: 'completed' | 'skipped' | 'issue';
		note: string;
		photo_url?: string;
		issue_category?: IssueCategory;
		create_followup?: boolean;
		followup_title?: string;
		followup_date?: string;
	}) {
		const task = this.tasks.find((t) => t.id === params.task_id);
		if (!task) return;

		// 1. Update task status
		task.status = params.action;

		// 2. Add task log
		const newLog: TaskLog = {
			id: `log-${Date.now()}`,
			task_id: params.task_id,
			farm_id: task.farm_id,
			action: params.action,
			note: params.note,
			photo_url: params.photo_url,
			issue_category: params.issue_category,
			created_at: new Date().toISOString()
		};
		this.logs = [newLog, ...this.logs];

		// 3. Optional automatic follow-up task creation
		if (params.action === 'issue' || params.create_followup) {
			const followupTitle = params.followup_title || `[후속조치] ${task.title} 문제 대응 (${params.issue_category || '점검'})`;
			const followupDate = params.followup_date || tomorrowStr;

			const followupTask: Task = {
				id: `task-followup-${Date.now()}`,
				farm_id: task.farm_id,
				cultivation_cycle_id: task.cultivation_cycle_id,
				operation_type_code: 'follow_up',
				work_area_ids: task.work_area_ids,
				title: followupTitle,
				description: `원인/기록: ${params.note}`,
				scheduled_date: followupDate,
				category: '후속작업' as TaskCategory,
				status: 'pending' as TaskStatus,
				priority: 'high' as TaskPriority,
				is_followup: true,
				parent_task_id: task.id,
				created_at: new Date().toISOString()
			};

			this.tasks = [followupTask, ...this.tasks];
		}
	}

	addAIConsultation(farmId: string, question: string, answer: string, summary?: string) {
		const newCons: AIConsultation = {
			id: `cons-${Date.now()}`,
			farm_id: farmId,
			question,
			answer,
			summary_report: summary,
			created_at: new Date().toISOString()
		};
		this.consultations = [newCons, ...this.consultations];
		return newCons;
	}

	// Admin analytics for all farms
	getAdminSummaries(): FarmAdminSummary[] {
		return this.farms.map((farm) => {
			const farmTasks = this.tasks.filter((t) => t.farm_id === farm.id);
			const farmLogs = this.logs.filter((l) => l.farm_id === farm.id);

			const pending_count = farmTasks.filter((t) => t.status === 'pending').length;
			const completed_count = farmTasks.filter((t) => t.status === 'completed').length;
			const issue_count = farmTasks.filter((t) => t.status === 'issue').length;

			// Count issue categories
			const categoryCounts: Record<string, number> = {};
			for (const log of farmLogs) {
				if (log.action === 'issue' && log.issue_category) {
					categoryCounts[log.issue_category] = (categoryCounts[log.issue_category] || 0) + 1;
				}
			}

			const recurring_issues = Object.entries(categoryCounts).map(([cat, count]) => ({
				category: cat as IssueCategory,
				count
			}));

			let risk_level: 'normal' | 'warning' | 'danger' = 'normal';
			if (issue_count >= 2 || pending_count >= 3) {
				risk_level = 'danger';
			} else if (issue_count === 1 || pending_count >= 2) {
				risk_level = 'warning';
			}

			return {
				farm,
				pending_count,
				completed_count,
				issue_count,
				recurring_issues,
				recent_logs: farmLogs.slice(0, 5),
				risk_level
			};
		});
	}
}

export const farmStore = new FarmStoreState();
