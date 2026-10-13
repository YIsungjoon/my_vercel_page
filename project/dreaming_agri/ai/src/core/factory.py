from typing import Dict, Type, Optional
from langchain_core.language_models.chat_models import BaseChatModel
from .base import BaseLLMProvider
from .providers.nvidia_provider import NvidiaLLMProvider
from .providers.nemotron_provider import NemotronLLMProvider
from .providers.mock_provider import MockLLMProvider
from ..config import config

class LLMFactory:
    """
    Registry & Factory pattern for managing multiple LLM providers.
    - General Chat / Q&A: nvidia/nemotron-3.5-nano-30b-a3b (NemotronLLMProvider)
    - Agent Reasoning: z-ai/glm-5.2 (NvidiaLLMProvider)
    """
    
    _providers: Dict[str, Type[BaseLLMProvider]] = {
        "nvidia": NvidiaLLMProvider,
        "nemotron": NemotronLLMProvider,
        "mock": MockLLMProvider,
    }

    @classmethod
    def register_provider(cls, name: str, provider_cls: Type[BaseLLMProvider]):
        """Register a new LLM provider class"""
        cls._providers[name.lower()] = provider_cls

    @classmethod
    def create(
        cls,
        provider: Optional[str] = None,
        model: Optional[str] = None,
        mode: str = "chat", # 'chat' or 'agent'
        **kwargs
    ) -> BaseLLMProvider:
        """Instantiates and returns a BaseLLMProvider instance"""
        if mode == "agent":
            provider_name = provider or "nvidia"
            model_name = model or config.default_agent_model
        else:
            provider_name = provider or "nemotron"
            model_name = model or config.default_chat_model

        provider_cls = cls._providers.get(provider_name.lower())
        if not provider_cls:
            raise ValueError(
                f"Unknown LLM Provider '{provider_name}'. Available providers: {list(cls._providers.keys())}"
            )

        return provider_cls(model=model_name, **kwargs)

    @classmethod
    def get_chat_model(
        cls,
        provider: Optional[str] = None,
        model: Optional[str] = None,
        mode: str = "chat",
        **kwargs
    ) -> BaseChatModel:
        """Convenience method to directly retrieve a LangChain BaseChatModel"""
        llm_provider = cls.create(provider=provider, model=model, mode=mode, **kwargs)
        return llm_provider.get_chat_model(**kwargs)

def get_llm(
    provider: Optional[str] = None,
    model: Optional[str] = None,
    mode: str = "chat",
    **kwargs
) -> BaseChatModel:
    """Utility function to retrieve an initialized LangChain ChatModel"""
    return LLMFactory.get_chat_model(provider=provider, model=model, mode=mode, **kwargs)
