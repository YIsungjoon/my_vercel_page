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

class NemotronLLMProvider(BaseLLMProvider):
    """
    NVIDIA Nemotron LLM Provider for General Chat / Q&A.
    Model: nvidia/nemotron-3.5-nano-30b-a3b
    Parameters: temperature=1, top_p=0.95, max_tokens=16384, reasoning_budget=16384,
                chat_template_kwargs={"enable_thinking": True}
    """

    def __init__(
        self,
        model: str = "nvidia/nemotron-3.5-nano-30b-a3b",
        api_key: Optional[str] = None,
        temperature: float = 1.0,
        top_p: float = 0.95,
        max_tokens: int = 16384,
        reasoning_budget: int = 16384,
        enable_thinking: bool = True,
    ):
        self.model_name = model
        self.api_key = api_key or config.nvidia_api_key or os.getenv("NVIDIA_API_KEY", "")
        self.temperature = temperature
        self.top_p = top_p
        self.max_tokens = max_tokens
        self.reasoning_budget = reasoning_budget
        self.enable_thinking = enable_thinking

    def get_chat_model(self, **kwargs) -> BaseChatModel:
        if not HAS_NVIDIA_ENDPOINT:
            raise ImportError(
                "langchain_nvidia_ai_endpoints package is required for NemotronLLMProvider. "
                "Install via: pip install langchain-nvidia-ai-endpoints"
            )

        model = kwargs.get("model", self.model_name)
        api_key = kwargs.get("api_key", self.api_key)
        temperature = kwargs.get("temperature", self.temperature)
        top_p = kwargs.get("top_p", self.top_p)
        max_tokens = kwargs.get("max_tokens", self.max_tokens)
        reasoning_budget = kwargs.get("reasoning_budget", self.reasoning_budget)
        enable_thinking = kwargs.get("enable_thinking", self.enable_thinking)

        return ChatNVIDIA(
            model=model,
            api_key=api_key,
            temperature=temperature,
            top_p=top_p,
            max_tokens=max_tokens,
            reasoning_budget=reasoning_budget,
            chat_template_kwargs={"enable_thinking": enable_thinking},
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
            # Extract reasoning_content if present in additional_kwargs
            if hasattr(chunk, "additional_kwargs") and chunk.additional_kwargs and "reasoning_content" in chunk.additional_kwargs:
                reasoning = chunk.additional_kwargs["reasoning_content"]
                if reasoning:
                    yield str(reasoning)

            if hasattr(chunk, "content") and chunk.content:
                yield str(chunk.content)
