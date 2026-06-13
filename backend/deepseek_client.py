"""DeepSeek API 客户端（使用 OpenAI SDK 兼容调用）。"""
import os
from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()

DEEPSEEK_KEY_ERROR = (
    "DeepSeek API Key 未配置，请在 backend/.env 中填写 DEEPSEEK_API_KEY。"
)


def is_deepseek_configured() -> bool:
    api_key = os.getenv("DEEPSEEK_API_KEY", "").strip()
    if not api_key:
        return False
    placeholders = ("你的_deepseek_api_key", "your_deepseek_api_key", "sk-placeholder")
    if api_key in placeholders or "你的" in api_key or api_key.startswith("your_"):
        return False
    # DeepSeek keys are typically sk-... and longer than a placeholder
    return len(api_key) >= 20


class DeepSeekClient:
    def __init__(self):
        api_key = os.getenv("DEEPSEEK_API_KEY", "").strip()
        base_url = os.getenv("DEEPSEEK_BASE_URL", "https://api.deepseek.com")

        if not api_key or not is_deepseek_configured():
            raise RuntimeError(DEEPSEEK_KEY_ERROR)

        self.client = OpenAI(api_key=api_key, base_url=base_url)

    def chat(
        self,
        prompt: str,
        system: str = "你是专业都市长篇小说策划、网文作者和长视频文案写手。",
        model: str = "deepseek-chat",
        temperature: float = 0.85,
    ) -> str:
        response = self.client.chat.completions.create(
            model=model,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": prompt},
            ],
            temperature=temperature,
            stream=False,
        )
        return response.choices[0].message.content
