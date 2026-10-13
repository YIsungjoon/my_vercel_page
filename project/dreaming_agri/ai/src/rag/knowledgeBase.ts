export interface KBManualDoc {
	id: string;
	title: string;
	crop: string;
	category: string;
	content: string;
	source: string;
}

export const AGRI_KNOWLEDGE_BASE: KBManualDoc[] = [
	{
		id: 'doc-1',
		title: '토마토 생식생장기 흰가루병 방제 및 습도 관리 지침',
		crop: '토마토',
		category: '병해충',
		content: '토마토 3화방 착과기 및 생식생장기에는 야간 습도가 80%를 초과할 경우 흰가루병(Oidium neolycopersici)이 급격히 발병합니다. 발병 초기 하부 노화 엽을 적엽하여 온실 내부 통풍을 확보하고, 탄산수소칼륨계 또는 미생물 제제를 5일 간격으로 2회 엽면 살포하십시오.',
		source: '농촌진흥청 스마트팜 영농기술 매뉴얼 v2.4'
	},
	{
		id: 'doc-2',
		title: '참외 수확기 덩굴쪼김병 및 관수 밸브 이상 조치',
		crop: '참외',
		category: '시설/병해',
		content: '참외 수확기 뿌리 세력 저하 및 덩굴쪼김병 증상 발생 시 관수량을 회당 10분 이내로 분할 공급하고 토양 유기물 함량을 점검하십시오. 양액 펌프 수압 저하 발생 시 토출측 필터 막힘 및 솔레노이드 밸브 다이어프램 상태를 우선 점검해야 합니다.',
		source: '성주 참외 과채류 연구소 재배 가이드'
	},
	{
		id: 'doc-3',
		title: '파프리카 영양생장기 초세 유지 및 양액 EC 관리',
		crop: '파프리카',
		category: '양액/생육',
		content: '파프리카 영양생장기 1차 유인 시 주경 줄기가 손상되지 않도록 유인 끈 고정 고리를 줄기 마디 하단 2cm 지점에 채웁니다. 양액 EC는 2.0~2.2, pH는 5.8로 정밀 제어하여 잎의 칼슘 결핍(팁번) 현상을 예방하십시오.',
		source: '원예특작과학원 파프리카 표준 재배 지침'
	}
];

export interface RAGQueryInput {
	query: string;
	crop: string;
	farm_logs_summary?: string;
}

export interface RAGQueryResult {
	retrieved_docs: KBManualDoc[];
	rag_answer: string;
	confidence_score: number;
}

/**
 * Searches agricultural technical documentation and synthesizes evidence-based answers.
 */
export function queryAgriRAG(input: RAGQueryInput): RAGQueryResult {
	const lowerQuery = input.query.toLowerCase();
	const cropDocs = AGRI_KNOWLEDGE_BASE.filter(
		(doc) => doc.crop === input.crop || lowerQuery.includes(doc.crop) || input.query.includes(doc.category)
	);

	const matchedDocs = cropDocs.length > 0 ? cropDocs : AGRI_KNOWLEDGE_BASE;

	const docExcerpts = matchedDocs
		.map((d, i) => `[근거문서 ${i + 1}] "${d.title}" (${d.source}): ${d.content}`)
		.join('\n\n');

	const rag_answer = `📚 <strong>농업 표준 지침 문서 근거 답변</strong>:\n\n${docExcerpts}\n\n💡 <strong>농가 적용 권고사항</strong>:\n- 현재 농가 기록(${input.farm_logs_summary || '최근 작업 내역'})과 결합하여, 위 매뉴얼의 지침에 따라 5일 간격 점검 및 환경 설정을 이행하는 것을 권장합니다.`;

	return {
		retrieved_docs: matchedDocs,
		rag_answer,
		confidence_score: 0.94
	};
}
