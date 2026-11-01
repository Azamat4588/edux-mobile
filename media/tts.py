import asyncio, json, os, sys, edge_tts
cfg = json.load(open("media/lines.json"))
os.makedirs("out", exist_ok=True)
async def one(text, voice, path):
    for attempt in range(6):
        try:
            await edge_tts.Communicate(text, voice, rate=cfg["rate"]).save(path)
            if os.path.getsize(path) > 1000: return True
        except Exception as e:
            print("retry", path, attempt, repr(e), flush=True)
        await asyncio.sleep(3 + attempt * 4)
    return False
async def main():
    bad = 0
    for voice in cfg["voices"]:
        tag = "sardor" if "Sardor" in voice else "madina"
        for key, text in cfg["lines"].items():
            ok = await one(text, voice, f"out/{key}_{tag}.mp3")
            print(key, tag, "ok" if ok else "FAIL", flush=True)
            bad += not ok
    sys.exit(1 if bad else 0)
asyncio.run(main())
