# Grok Bot design reference

Frames taken from a screen recording of a text and voice chat in the Grok Bot iOS app.
They are the visual reference for the native app design (#9).

Use them to match layout, spacing, and feel. Build everything from native SwiftUI
system components (toolbar, `safeAreaInset` composer, SF Symbols, semantic colors).
Don't copy pixels or brand colors.

| File | What it shows |
| --- | --- |
| `01-chat-screen.png` | Chat screen: nav bar with back, title pill, and menu; user and assistant bubbles; composer at the bottom |
| `02-composer.png` | Composer: `+`, text field, mic for dictation, and a voice-call button |
| `03-call-banner-connecting.png` | Call banner as the call starts, with a level line before speech |
| `04-call-in-progress.png` | Full screen during a call: banner floats under the nav bar and the chat stays visible |
| `05-call-banner.png` | Call banner close-up: avatar, live waveform, settings, mute, and a red end button |
| `06-after-call.png` | Chat after the call ends |
| `07-voice-chat-marker.png` | After-call marker under the last message: "Voice chat · 00:15" |
