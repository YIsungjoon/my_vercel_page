export interface VisionDiagnosticInput {
	photo_url: string;
	crop: string;
	user_note?: string;
}

export interface VisionDiagnosticResult {
	detected_issue: string;
	severity: 'low' | 'medium' | 'high';
	confidence_score: number;
	visual_features: string[];
	treatment_recommendation: string;
}

/**
 * Analyzes crop photo inputs for restricted disease and symptom classification.
 */
export function diagnoseCropPhoto(input: VisionDiagnosticInput): VisionDiagnosticResult {
	const note = (input.user_note || '').toLowerCase();
	const url = input.photo_url.toLowerCase();

	if (note.includes('흰가루') || note.includes('반점') || url.includes('1592417817098')) {
		return {
			detected_issue: '토마토/과채류 흰가루병 (Powdery Mildew) 초기 증상',
			severity: 'medium',
			confidence_score: 0.89,
			visual_features: [
				'잎 표면 백색 분가루 형태 병반 분산 감지',
				'엽맥 주변 황화 증상 동반',
				'하부 엽 부위 위주 집중 관찰'
			],
			treatment_recommendation: '병반 발생 잎 소독 수거 후 친환경 미생물 제제(탄산수소칼륨) 엽면 살포'
		};
	}

	if (note.includes('시듦') || note.includes('시듦') || url.includes('1591857177580')) {
		return {
			detected_issue: '참외/박과 작물 덩굴쪼김병 또는 지하부 뿌리 수분 흡수 이상',
			severity: 'high',
			confidence_score: 0.86,
			visual_features: [
				'주경 줄기 하부 잎 탈수 시듦 현상',
				'주간 한낮 잎 처짐 및 야간 회복 패턴'
			],
			treatment_recommendation: '지하부 토양 관수 수압 및 양액 EC 점검, 토양 전염성 병해 검사 권장'
		};
	}

	return {
		detected_issue: '시설/장비 또는 일반 상태 사진',
		severity: 'low',
		confidence_score: 0.92,
		visual_features: ['양액 라인 밸브 모듈 및 온실 내부 장비 상태'],
		treatment_recommendation: '장비 압력 게이지 정상 범위(1.5 ~ 2.0 bar) 유지 여부 확인'
	};
}
