import os
from dataclasses import dataclass

@dataclass
class LLMConfig:
    nvidia_api_key: str = os.getenv("NVIDIA_API_KEY", "")
    default_provider: str = os.getenv("DEFAULT_LLM_PROVIDER", "nvidia")
    
    # Model tiers: General Chat (Nemotron Nano) vs Agent Reasoning (GLM 5.2)
    default_chat_model: str = os.getenv("DEFAULT_CHAT_MODEL", "nvidia/nemotron-3.5-nano-30b-a3b")
    default_agent_model: str = os.getenv("DEFAULT_AGENT_MODEL", "z-ai/glm-5.2")
    
    temperature: float = float(os.getenv("DEFAULT_TEMPERATURE", "1.0"))
    top_p: float = float(os.getenv("DEFAULT_TOP_P", "0.95"))
    max_tokens: int = int(os.getenv("DEFAULT_MAX_TOKENS", "16384"))
    reasoning_budget: int = int(os.getenv("DEFAULT_REASONING_BUDGET", "16384"))
    seed: int = int(os.getenv("DEFAULT_SEED", "42"))

config = LLMConfig()
