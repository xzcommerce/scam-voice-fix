# Scam Voice Fix

[Русский](docs/README.ru.md) · [Download the English/Russian ZIP](../../releases/latest) · [Review the code](docs/REVIEW.md)

This is the fix that made Russian NPC voices fast and smooth on my PC in **Scam With Your Friends**. I'm sharing the scripts and patch-generation code so people can inspect the changes themselves.

It addresses one specific Qwen/NVIDIA cache startup problem. It is an unofficial community fix, not a general fix for every slow voice or AI reply.

## What happened

Qwen took too long to produce its first audio when launched with Steam's NVIDIA shader-cache environment. After five seconds the game disabled Qwen and switched Russian speech to MOSS, which sounded slow and choppy on this PC.

The relevant log message was:

```text
First audio took more than five seconds; Qwen3 TTS disabled in settings.
```

That message can have other causes too. On the tested PC, preparing the normal GPU cache and changing the Qwen worker's environment brought the first audio down to about **1.1 seconds in-game**, with smooth speech. This measures the speech-generation stage, not the entire conversation response time.

## Try it

1. Download **Scam-Voice-Fix-GUI-25996926.zip** from [Releases](../../releases/latest).
2. Extract the entire ZIP and open the extracted folder.
3. Close the game, run **START.cmd**, choose English or Русский, then click **Fix voice**.
4. Wait for completion, start the game through Steam, and try two Russian NPC replies.

**Undo changes** restores the original game DLL and previous Qwen/FPS preferences. **Check compatibility only** checks without changing game files or settings.

Requirements: the exact supported Steam build **25996926**, Windows x64, a supported NVIDIA GPU with at least **8 GB VRAM**, about **16 GB system RAM**, at least **6 GB free RAM**, and the game's Qwen models already downloaded. Unknown DLL versions and conflicting modifications are rejected. Each affected player needs the fix locally; installing it on the host does not fix other clients.

## What it changes

- Checks the game, runtime, model and voice hashes.
- Runs the game's own Qwen worker to prepare the cache, then measures a second fresh worker before installing.
- Patches the Qwen child process's environment: removes four NVIDIA cache overrides and disables Steam's Vulkan overlay/Fossilize layers for that worker.
- Adds Qwen diagnostic messages to the game's log.
- Enables Qwen for non-English voices and caps the game at **60 FPS**.
- Backs up the DLL and those two preferences under `%LOCALAPPDATA%\ScamVoiceFix`.

The helper works offline, uses the already installed game runtime, and needs no account or API key. Its interface is compiled from the included C# source using Windows PowerShell/.NET. It does not alter the five-second timeout, speech models, multiplayer routing, or global environment variables. The launch scripts use a process-scoped PowerShell execution-policy bypass; they do not change the machine's saved policy.

## Review or rebuild

Start with the [review guide](docs/REVIEW.md). The complete launch chain, installer, warmup helper, and **both scripts that generate the patched DLL** are available here. Reviewers can rebuild from their own supported original DLL and verify the output SHA-256 against the shipped patch.

The source under [`Scam-Voice-Fix/`](Scam-Voice-Fix/) matches the previously shared GUI ZIP, file for file. No original/patched game DLLs, models, audio, personal logs, or account credentials are checked in. The version-specific binary delta is included; its generating changes are documented and rebuildable.

## Testing and limits

Tested in-game on **RTX 3060 12 GB / Ryzen 7 PRO 3700 / 32 GB RAM**, using Russian calls. See the [test notes](docs/TESTING.md) for timings and installer checks.

Other PCs, multiplayer, high-DPI UI layouts and future game builds have not been validated. Steam updates may replace the patch; a driver update or cache cleanup may require preparing the cache again. A Qwen timeout on different hardware needs its own diagnosis.
