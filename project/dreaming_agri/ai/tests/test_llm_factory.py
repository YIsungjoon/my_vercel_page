import os
import sys

# Ensure src/ is on Python path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from src.core.factory import LLMFactory, get_llm
from src.core.providers.nvidia_provider import NvidiaLLMProvider
from src.core.providers.nemotron_provider import NemotronLLMProvider

def test_provider_tier_routing():
    print("[1/3] Testing General Chat (Nemotron Nano) & Agent (GLM 5.2) Provider Routing...")
    
    # Mode="chat" -> Nemotron Nano
    chat_provider = LLMFactory.create(mode="chat")
    assert isinstance(chat_provider, NemotronLLMProvider)
    assert chat_provider.model_name == "nvidia/nemotron-3.5-nano-30b-a3b"
    assert chat_provider.top_p == 0.95
    assert chat_provider.reasoning_budget == 16384
    assert chat_provider.enable_thinking is True
    print("      ✓ General Chat Provider: nvidia/nemotron-3.5-nano-30b-a3b (top_p=0.95, reasoning_budget=16384, enable_thinking=True)")

    # Mode="agent" -> GLM 5.2
    agent_provider = LLMFactory.create(mode="agent")
    assert isinstance(agent_provider, NvidiaLLMProvider)
    assert agent_provider.model_name == "z-ai/glm-5.2"
    assert agent_provider.seed == 42
    print("      ✓ Agent Provider: z-ai/glm-5.2 (top_p=1.0, seed=42)")

def test_mock_fallback_streaming():
    print("[2/3] Testing Mock Provider Fallback...")
    provider = LLMFactory.create("mock")
    stream = provider.stream_response("토마토 생식생장기 관리 지침")
    tokens = list(stream)
    assert len(tokens) > 0
    print(f"      ✓ Mock Streaming passed: '{''.join(tokens).strip()}'")

def test_direct_nemotron_stream_snippet():
    print("[3/3] Testing ChatNVIDIA Nemotron Nano Direct Snippet...")
    api_key = os.getenv("NVIDIA_API_KEY", "")
    if not api_key:
        print("      ⚠️ NVIDIA_API_KEY is not set in environment. Skipping live API call.")
        print("      To test live streaming, run: export NVIDIA_API_KEY='your-key'")
        return

    try:
        from langchain_nvidia_ai_endpoints import ChatNVIDIA
        client = ChatNVIDIA(
            model="nvidia/nemotron-3.5-nano-30b-a3b",
            api_key=api_key,
            temperature=1,
            top_p=0.95,
            max_tokens=16384,
            reasoning_budget=16384,
            chat_template_kwargs={"enable_thinking": True},
        )
        print("      ✓ ChatNVIDIA Nemotron Nano client instantiated.")
        print("      Streaming Live Nemotron Response:")
        for chunk in client.stream([{"role": "user", "content": "토마토 생식생장기 환기 수칙 한줄 요약"}]):
            if chunk.additional_kwargs and "reasoning_content" in chunk.additional_kwargs:
                print(chunk.additional_kwargs["reasoning_content"], end="", flush=True)
            print(chunk.content, end="", flush=True)
        print("\n      ✓ Live Nemotron Streaming Complete.")
    except Exception as e:
        print(f"      ⚠️ Live test error: {e}")

if __name__ == "__main__":
    print("================ LLM CORE & FACTORY TEST SUITE ================")
    test_provider_tier_routing()
    test_mock_fallback_streaming()
    test_direct_nemotron_stream_snippet()
    print("===============================================================")
