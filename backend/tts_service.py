"""edge-tts 免费配音实现：按章节生成 MP3。"""
import edge_tts

VOICE_MAP = {
    "zh_male": "zh-CN-YunxiNeural",
    "zh_female": "zh-CN-XiaoxiaoNeural",
    "en_male": "en-US-GuyNeural",
    "en_female": "en-US-JennyNeural",
    "es_male": "es-ES-AlvaroNeural",
    "es_female": "es-ES-ElviraNeural",
    "ja_male": "ja-JP-KeitaNeural",
    "ja_female": "ja-JP-NanamiNeural",
}

ALLOWED_RATES = ["-20%", "-10%", "+0%", "+10%", "+20%"]


async def generate_tts(text: str, output_path: str, voice_key: str = "zh_male", rate: str = "+0%") -> None:
    """为整章文本生成一个 MP3 文件。

    第一版不做整本合并、段落级合并，每章生成一个 MP3。
    """
    voice = VOICE_MAP.get(voice_key, VOICE_MAP["zh_male"])
    communicate = edge_tts.Communicate(
        text=text,
        voice=voice,
        rate=rate,
        volume="+0%",
    )
    await communicate.save(output_path)
