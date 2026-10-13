from typing import Dict
from langchain_core.messages import SystemMessage, AIMessage
from ..state import FarmAgentState
from ...core.factory import get_llm

def reasoning_node(state: FarmAgentState) -> Dict:
    """
    Reasoning Node in LangGraph workflow.
    Uses GLM 5.2 (z-ai/glm-5.2) Agent Model for complex reasoning workflows.
    """
    try:
        # Agent Workflows explicitly use GLM 5.2 (mode="agent")
        llm = get_llm(mode="agent")
    except Exception:
        # Fallback to mock provider if API key is not configured locally
        from ...core.factory import LLMFactory
        llm = LLMFactory.get_chat_model(provider="mock")

    crop = state.get("crop", "토마토")
    stage = state.get("growth_stage", "생식생장기")
    
    system_prompt = (
        f"당신은 예측형 농장 운영관리 플랫폼 Dreaming Agri의 AI 수석 컨설턴트입니다.\n"
        f"관리 작물: {crop}, 현재 생육 단계: {stage}.\n"
        f"농가의 근거(RAG) 및 예측(Forecast) 데이터를 바탕으로 친절하고 명확하게 생육 및 수확 가이드를 제공하십시오."
    )

    messages = [SystemMessage(content=system_prompt)] + list(state.get("messages", []))
    
    response = llm.invoke(messages)
    content = response.content if hasattr(response, "content") else str(response)

    return {
        "messages": [AIMessage(content=content)],
        "final_response": content
    }
