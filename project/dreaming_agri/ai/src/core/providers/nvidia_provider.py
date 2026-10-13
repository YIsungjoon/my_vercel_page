import os
from typing import Any, Dict, Generator, List, Optional
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import BaseMessage, HumanMessage, SystemMessage
from ..base import BaseLLMProvider
from ...config import config

try:
    from langchain_nvidia_ai_endpoints import ChatNVIDIA
    HAS_NVIDIA_ENDPOINT = True
except ImportError:
    HAS_NVIDIA_ENDPOINT = False
    ChatNVIDIA = None

class NvidiaLLMProvider(BaseLLMProvider):
    """
    NVIDIA AI Endpoints Provider for LangChain & LangGraph.
    Default Model: z-ai/glm-5.2
    Parameters: temperature=1, top_p=1, max_tokens=16384, seed=42
    """

    def __init__(
        self,
        model: str = "z-ai/glm-5.2",
        api_key: Optional[str] = None,
        temperature: float = 1.0,
        top_p: float = 1.0,
        max_tokens: int = 16384,
        seed: int = 42,
    ):
        self.model_name = model
        self.api_key = api_key or config.nvidia_api_key or os.getenv("NVIDIA_API_KEY", "")
        self.temperature = temperature
        self.top_p = top_p
        self.max_tokens = max_tokens
        self.seed = seed

    def get_chat_model(self, **kwargs) -> BaseChatModel:
        if not HAS_NVIDIA_ENDPOINT:
            raise ImportError(
                "langchain_nvidia_ai_endpoints package is required for NvidiaLLMProvider. "
                "Install via: pip install langchain-nvidia-ai-endpoints"
            )

        model = kwargs.get("model", self.model_name)
        api_key = kwargs.get("api_key", self.api_key)
        temperature = kwargs.get("temperature", self.temperature)
        top_p = kwargs.get("top_p", self.top_p)
        max_tokens = kwargs.get("max_tokens", self.max_tokens)
        seed = kwargs.get("seed", self.seed)

        return ChatNVIDIA(
            model=model,
            api_key=api_key,
            temperature=temperature,
            top_p=top_p,
            max_tokens=max_tokens,
            seed=seed,
        )

    def stream_response(
        self, prompt: str, system_prompt: Optional[str] = None, **kwargs
    ) -> Generator[str, None, None]:
        client = self.get_chat_model(**kwargs)
        messages: List[BaseMessage] = []

        if system_prompt:
            messages.append(SystemMessage(content=system_prompt))
        messages.append(HumanMessage(content=prompt))

        for chunk in client.stream(messages):
            if hasattr(chunk, "content") and chunk.content:
                yield str(chunk.content)
