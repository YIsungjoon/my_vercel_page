from typing import Any
from .state import FarmAgentState
from .nodes.forecast_node import forecast_node
from .nodes.rag_node import rag_node
from .nodes.reasoning_node import reasoning_node

try:
    from langgraph.graph import StateGraph, END
    HAS_LANGGRAPH = True
except ImportError:
    HAS_LANGGRAPH = False
    StateGraph = None
    END = None

def build_farm_agent_graph():
    """
    Builds and compiles the LangGraph StateGraph pipeline:
    START -> Forecast -> RAG -> Reasoning -> END
    """
    if not HAS_LANGGRAPH:
        raise ImportError(
            "langgraph package is required to build the LangGraph workflow. "
            "Install via: pip install langgraph"
        )

    workflow = StateGraph(FarmAgentState)

    # Add Nodes
    workflow.add_node("forecast", forecast_node)
    workflow.add_node("rag", rag_node)
    workflow.add_node("reasoning", reasoning_node)

    # Define Edges
    workflow.set_entry_point("forecast")
    workflow.add_edge("forecast", "rag")
    workflow.add_edge("rag", "reasoning")
    workflow.add_edge("reasoning", END)

    return workflow.compile()
