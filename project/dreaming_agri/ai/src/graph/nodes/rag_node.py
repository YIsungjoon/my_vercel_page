from typing import Dict
from ..state import FarmAgentState
from ...rag.knowledgeBase import queryAgriRAG

def rag_node(state: FarmAgentState) -> Dict:
    """
    RAG Retrieval Node in LangGraph workflow.
    Retrieves agricultural guidance documents.
    """
    messages = state.get("messages", [])
    last_query = messages[-1].content if messages else "작물 관리 지침"
    crop = state.get("crop", "토마토")

    rag_res = queryAgriRAG({
        "query": str(last_query),
        "crop": crop
    })

    return {
        "retrieved_docs": [
            {"title": d.title, "content": d.content, "source": d.source}
            for d in rag_res["retrieved_docs"]
        ]
    }
