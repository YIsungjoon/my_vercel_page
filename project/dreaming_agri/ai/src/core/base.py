from abc import ABC, abstractmethod
from typing import Any, Dict, Generator, Optional
from langchain_core.language_models.chat_models import BaseChatModel

class BaseLLMProvider(ABC):
    """
    Abstract Base Class for LLM Providers adhering to Separation of Concerns (SoC)
    """

    @abstractmethod
    def get_chat_model(self, **kwargs) -> BaseChatModel:
        """Returns initialized LangChain BaseChatModel instance"""
        pass

    @abstractmethod
    def stream_response(self, prompt: str, system_prompt: Optional[str] = None, **kwargs) -> Generator[str, None, None]:
        """Streams response tokens from the model"""
        pass
