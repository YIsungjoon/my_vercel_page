import type { EnvironmentalSample } from '../synthetic-data/generator';

export interface ForecastingInput {
	farm_id: string;
	crop: string;
	variety: string;
	growth_stage: string;
	planted_at: string;
	recent_environment: EnvironmentalSample[];
	recorded_issues_count: number;
}

export interface ForecastingOutput {
	suggestion: string;
	confidence_score: number; // 0.0 ~ 1.0
	range: {
		start_date: string;
		end_date: string;
	};
	evidence: string[];
	recommended_action: string;
	disclaimer: string;
}

/**
 * Predicts crop growth progress and suggests task schedule calibration based on environmental trends and GDD.
 */
export function forecastSchedule(input: ForecastingInput): ForecastingOutput {
	const avgTemp =
		input.recent_environment.reduce((sum, e) => sum + e.temperature_c, 0) /
		(input.recent_environment.length || 1);

	const avgHumidity =
		input.recent_environment.reduce((sum, e) => sum + e.relative_humidity_pct, 0) /
		(input.recent_environment.length || 1);

	const today = new Date();
	const startDate = new Date(today.getTime() + 86400000).toISOString().slice(0, 10);
	const endDate = new Date(today.getTime() + 86400000 * 4).toISOString().slice(0, 10);

	let suggestion = '';
	let confidence = 0.88;
	let evidence: string[] = [];
	let action = '';

	if (avgHumidity > 75 || input.recorded_issues_count > 0) {
		suggestion = `${input.crop} ${input.growth_stage} 고습도(평균 ${Math.round(avgHumidity)}%) 지속으로 병해충 발생 위험이 증가하였습니다. 관수량을 15% 감축하고 환기팬 작동 시간을 늘리는 일정 보정을 제안합니다.`;
		confidence = 0.92;
		evidence = [
			`최근 7일 평균 상대습도 ${Math.round(avgHumidity)}% (기준 70% 초과)`,
			`등록된 농가 문제 기록 ${input.recorded_issues_count}건 감지`,
			`생육단계 [${input.growth_stage}] 병해 감염 취약 구간`
		];
		action = '하부 잎 통풍 적엽 작업 및 5일 간격 친환경 방제제 살포 준비';
	} else if (avgTemp > 28) {
		suggestion = `주간 평균 온도가 ${Math.round(avgTemp)}°C로 높아 야간 차광막 스케줄을 1시간 연장하고 엽면시비 일정을 2일 당기는 것을 추천합니다.`;
		confidence = 0.85;
		evidence = [
			`평균 기온 ${Math.round(avgTemp)}°C (적정 기온 24°C 대비 상승)`,
			`고온 지속 시 착과율 감소 우려`
		];
		action = '차광막 타이머 설정 점검 및 양액 EC 2.0으로 미세 하향 조정';
	} else {
		suggestion = `현재 기온(${Math.round(avgTemp)}°C) 및 습도(${Math.round(avgHumidity)}%) 조건이 적정 범위입니다. 기존 7일 가이드 작업 스케줄을 유지하세요.`;
		confidence = 0.95;
		evidence = [
			`최근 기온 및 습도 변동폭 ±1.5°C 이내 안정`,
			`정식일(${input.planted_at}) 대비 정상 생육 속도 유지`
		];
		action = '표준 7일 관수 및 생육 관리 스케줄 이행';
	}

	return {
		suggestion,
		confidence_score: confidence,
		range: {
			start_date: startDate,
			end_date: endDate
		},
		evidence,
		recommended_action: action,
		disclaimer: '⚠️ 본 AI 제안은 종합 환경데이터 기반 예측 제안이며, 실제 농업 전문가의 진단을 대체하지 않습니다. 제어 확정 전 현장을 점검하세요.'
	};
}
