from typing import Dict
from ..state import FarmAgentState
from ...forecasting.scheduleEngine import forecastSchedule

def forecast_node(state: FarmAgentState) -> Dict:
    """
    Forecasting Node in LangGraph workflow.
    Calculates schedule calibration based on farm growth stage and environmental trends.
    """
    farm_id = state.get("farm_id", "farm-1")
    crop = state.get("crop", "토마토")
    stage = state.get("growth_stage", "생식생장기")

    result = forecastSchedule({
        "farm_id": farm_id,
        "crop": crop,
        "variety": "마이노르",
        "growth_stage": stage,
        "planted_at": "2026-03-15",
        "recent_environment": [],
        "recorded_issues_count": 0
    })

    return {
        "forecast_result": {
            "suggestion": result["suggestion"],
            "confidence": result["confidence_score"],
            "action": result["recommended_action"]
        }
    }
