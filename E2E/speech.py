"""Prints what the device's speech recognition would hear for each line given as an argument:
Piper speaks it, ffmpeg converts it to 16 kHz mono, Vosk transcribes it."""

import json
import os
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

from piper import PiperVoice
from vosk import KaldiRecognizer, Model, SetLogLevel

cache = Path(os.environ.get("VOICE_E2E_CACHE", Path.home() / ".cache/voice-e2e"))
SetLogLevel(-1)
voice = PiperVoice.load(cache / "en_US-lessac-low.onnx")
model = Model(str(cache / "vosk-model-small-en-us-0.15"))


def transcribe(line, folder):
    spoken, converted = f"{folder}/spoken.wav", f"{folder}/16k.wav"
    with wave.open(spoken, "wb") as file:
        voice.synthesize_wav(line, file)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-i", spoken, "-ar", "16000", "-ac", "1", converted],
        check=True,
    )
    recognizer = KaldiRecognizer(model, 16000)
    with wave.open(converted, "rb") as file:
        while data := file.readframes(4000):
            recognizer.AcceptWaveform(data)
    return json.loads(recognizer.FinalResult())["text"]


with tempfile.TemporaryDirectory() as folder:
    print(json.dumps([transcribe(line, folder) for line in sys.argv[1:]]))
