import asyncio, json, os, edge_tts
cfg = json.load(open("media/lines.json"))
os.makedirs("out", exist_ok=True)
async def main():
    for voice in cfg["voices"]:
        tag = "sardor" if "Sardor" in voice else "madina"
        for key, text in cfg["lines"].items():
            await edge_tts.Communicate(text, voice, rate=cfg["rate"]).save(f"out/{key}_{tag}.mp3")
            print(key, tag, "ok")
asyncio.run(main())
