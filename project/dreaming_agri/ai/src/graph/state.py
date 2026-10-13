from typing import Annotated, Dict, List, Optional, Sequence, TypedDict
from langchain_core.messages import BaseMessage
import operator

class FarmAgentState(TypedDict):
    """
    LangGraph TypedDict State schema for Dreaming Agri AI Agent
    """
    messages: Annotated[Sequence[BaseMessage], operator.add]
    farm_id: str
    crop: str
    growth_stage: str
    environmental_data: Optional[Dict]
    retrieved_docs: Optional[List[Dict]]
    forecast_result: Optional[Dict]
    final_response: Optional[str]
