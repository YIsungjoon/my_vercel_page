import { json } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { env } from '$env/dynamic/private';


export const POST: RequestHandler = async ({ request, locals }) => {
	const startTime = Date.now();
	try {
		const body = await request.json();
		const { question, farm_name, crop, growth_stage, system_prompt, mode = 'chat', farm_id, session_id } = body;

		const rawApiKey = env.NVIDIA_API_KEY;
		const nvidiaApiKey = rawApiKey ? rawApiKey.trim() : '';

		const isAgentMode = mode === 'agent';
		// Models: General Chat uses Nemotron Nano; Agent uses GLM 5.2.
		const primaryModel = isAgentMode ? 'z-ai/glm-5.2' : 'nvidia/nemotron-3.5-nano-30b-a3b';
		const fallbackModel = isAgentMode ? 'nvidia/nemotron-3.5-nano-30b-a3b' : 'z-ai/glm-5.2';

		if (!nvidiaApiKey) {
			const latencyMs = Date.now() - startTime;
			const answer = `💡 <strong>${farm_name ?? '농장'} AI 분석 결과 (${primaryModel})</strong>:<br/>
Vercel 환경변수에 <code>NVIDIA_API_KEY</code>가 등록되어 있습니다. 로컬 개발 환경에서도 동기화하려면 <code>cd frontend && npx vercel env pull .env.development.local</code>을 실행하세요.<br/><br/>
• <strong>대상 작물/단계</strong>: ${crop ?? '토마토'} (${growth_stage ?? '생식생장기'})<br/>
• <strong>권장 수칙</strong>: 3화방 착과기 고습도 지속 시 5일 간격 방제제 살포 및 온실 하부 통풍 적엽 조치를 권장합니다.`;

			return json({
				success: true,
				answer,
				source: 'fallback_no_key',
				metrics: {
					latency_ms: latencyMs,
					model: primaryModel,
					mode
				}
			});
		}

		const defaultSystemPrompt = system_prompt || `당신은 예측형 농장 운영관리 플랫폼 Dreaming Agri의 AI 수석 컨설턴트입니다.
현재 대상 농가: ${farm_name ?? '스마트농장'}, 작물: ${crop ?? '토마토'}, 생육단계: ${growth_stage ?? '생식생장기'}.
사용자의 질문과 농가 환경/작업 기록을 바탕으로 명확하고 실용적인 농업 생육 및 수확 지침을 답변하십시오.
반드시 추가 점검 가이드와 주의사항을 포함하고, 답변 끝에는 '⚠️ 본 AI 제안은 농업 전문가의 실제 현장 진단을 대체하지 않습니다.' 문구를 명시하십시오.`;

		// Standard OpenAI-compatible fetch payload for NVIDIA AI Endpoints
		async function fetchNvidiaModel(modelName: string) {
			const payload: Record<string, any> = {
				model: modelName,
				messages: [
					{ role: 'system', content: defaultSystemPrompt },
					{ role: 'user', content: question }
				],
				temperature: 1,
				top_p: modelName.includes('nemotron') ? 0.95 : 1,
				max_tokens: 4096,
				stream: false
			};

			if (modelName.includes('nemotron')) {
				payload.chat_template_kwargs = { enable_thinking: true };
			}

			return await fetch('https://integrate.api.nvidia.com/v1/chat/completions', {
				method: 'POST',
				headers: {
					'Authorization': `Bearer ${nvidiaApiKey}`,
					'Content-Type': 'application/json'
				},
				body: JSON.stringify(payload)
			});
		}

		// 1. Try primary model
		let response = await fetchNvidiaModel(primaryModel);
		let usedModel = primaryModel;

		// 2. If primary model returns 404/400/422, try fallback model
		if (!response.ok && (response.status === 404 || response.status === 400 || response.status === 422)) {
			console.warn(`Primary model ${primaryModel} failed with status ${response.status}. Retrying fallback ${fallbackModel}...`);
			response = await fetchNvidiaModel(fallbackModel);
			usedModel = fallbackModel;
		}

		const latencyMs = Date.now() - startTime;

		if (!response.ok) {
			const errorText = await response.text();
			console.error(`NVIDIA API Error (${response.status}):`, errorText);
			
			return json({
				success: false,
				answer: `⚠️ <strong>NVIDIA API 연결 상태 점검 (${response.status})</strong><br/>불러오기 응답: ${errorText}<br/><br/>💡 <em>(Vercel의 NVIDIA_API_KEY 값이 유효한지 확인해 주세요.)</em>`,
				status: response.status,
				error: true,
				metrics: {
					latency_ms: latencyMs,
					model: usedModel,
					mode,
					http_status: response.status
				}
			});
		}

		const data = await response.json();
		const choice = data.choices?.[0];
		let aiContent = choice?.message?.content || '답변 내용을 수신하지 못했습니다.';
		let reasoningContent = choice?.message?.reasoning_content || null;

		if (reasoningContent) {
			aiContent = `💭 <em>[생각 과정]: ${reasoningContent.slice(0, 300)}...</em><br/><br/>${aiContent}`;
		}

		// Extract Token Consumption Metrics
		const usage = data.usage || {};
		const promptTokens = usage.prompt_tokens ?? null;
		const completionTokens = usage.completion_tokens ?? null;
		const totalTokens = usage.total_tokens ?? null;

		// Persist Chat Log to Supabase DB
		if (locals.supabase) {
			try {
				const { error } = await locals.supabase
					.from('chat_logs')
					.insert([
						{
							farm_id,
							role: 'user',
							content: question,
							crop: crop ?? '토마토',
							growth_stage: growth_stage ?? '생식생장기',
							model: usedModel,
							mode,
							http_status: response.status
						},
						{
							farm_id,
							role: 'assistant',
							content: aiContent,
							crop: crop ?? '토마토',
							growth_stage: growth_stage ?? '생식생장기',
							model: usedModel,
							mode,
							latency_ms: latencyMs,
							prompt_tokens: promptTokens,
							completion_tokens: completionTokens,
							total_tokens: totalTokens,
							reasoning_content: reasoningContent,
							http_status: response.status
						}
					]);
				if (error) console.warn('Supabase chat_logs insert error:', error.message);
			} catch (e: any) {
				console.warn('Supabase chat_logs insert exception:', e?.message || e);
			}
		}

		return json({
			success: true,
			answer: aiContent.replace(/\n/g, '<br/>'),
			model: usedModel,
			mode,
			source: 'nvidia',
			metrics: {
				latency_ms: latencyMs,
				prompt_tokens: promptTokens,
				completion_tokens: completionTokens,
				total_tokens: totalTokens,
				http_status: response.status
			},
			context_snapshot: {
				farm_id,
				session_id,
				crop: crop ?? '토마토',
				growth_stage: growth_stage ?? '생식생장기'
			}
		});
	} catch (err: any) {
		const latencyMs = Date.now() - startTime;
		console.error('Server endpoint exception:', err);
		return json({
			success: false,
			answer: `⚠️ 서버 처리 중 예외가 발생했습니다: ${err?.message || err}`,
			error: true,
			metrics: {
				latency_ms: latencyMs,
				http_status: 500
			}
		});
	}
};
