from typing import Any, Dict, Generator, Optional
from langchain_core.language_models.chat_models import BaseChatModel
from langchain_core.messages import BaseMessage
from langchain_core.outputs import ChatGeneration, ChatResult
from ..base import BaseLLMProvider

class MockChatModel(BaseChatModel):
    """Fallback Mock Chat Model for offline testing and CI/CD"""
    
    def _generate(
        self,
        messages: list[BaseMessage],
        stop: Optional[list[str]] = None,
        run_manager: Optional[Any] = None,
        **kwargs: Any,
    ) -> ChatResult:
        last_msg = messages[-1].content if messages else ""
        response_text = f"[Mock LLM Response] Dreaming Agri AI Agent initialized. (Input: '{last_msg}')"
        generation = ChatGeneration(text=response_text)
        return ChatResult(generations=[generation])

    @property
    def _llm_type(self) -> str:
        return "mock_chat_model"

class MockLLMProvider(BaseLLMProvider):
    """Mock Provider for unit testing and offline development"""
    
    def get_chat_model(self, **kwargs) -> BaseChatModel:
        return MockChatModel()

    def stream_response(
        self, prompt: str, system_prompt: Optional[str] = None, **kwargs
    ) -> Generator[str, None, None]:
        response = f"[Mock LLM Stream] Dreaming Agri AI Response to: {prompt}"
        for word in response.split():
            yield word + " "
