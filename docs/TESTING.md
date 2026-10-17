# Test notes

## Observed game behavior

Game build: 25996926. PC: RTX 3060 12 GB, Ryzen 7 PRO 3700, 32 GB RAM. Russian NPC calls.

- With Steam's cache environment reproduced in a standalone official worker, first audio took 28.568 seconds; a second request in that same worker took 1.021 seconds.
- With the normal cache prepared and four NVIDIA cache overrides removed, first audio took about 1.0–1.2 seconds.
- Disabling only Steam's Vulkan layers did not fix the in-game timeout.
- After applying the combined fix, in-game first-audio timings included 1.116, 1.107 and 1.093 seconds. Qwen replies completed and the player reported fast, smooth speech.

These are observations on one PC. They do not prove that every five-second timeout has the same cause. First-audio timings cover synthesis, not speech recognition, LLM generation, or the full conversation.

## Installer and GUI

The [original installer validation](../Scam-Voice-Fix/files/engine/EN/files/VALIDATION.txt) lists isolated install, repeat install, undo, corrupt/unsupported inputs, settings-write rollback, Unicode paths, Steam discovery, hardware checks and official-worker warmup tests.

The [GUI validation](../Scam-Voice-Fix/files/GUI-VALIDATION.txt) covers source compilation, English/Russian layouts, read-only compatibility checks through its process controller, and error recovery. Layout images were rendered from controls; native desktop automation was unavailable, so this was not a live mouse/keyboard walkthrough.

`tests/Test-Installer.ps1` is the portable version of the isolated installer tests. Supply your own supported original DLL. The test creates fixtures under `.local` and uses a unique temporary registry key, removed afterward. It does not write to the game installation or its real preference key.

Publication checks passed on 17 October 2026: the portable two-stage source rebuild produced the exact patched DLL SHA-256; all eight isolated installer test groups passed; all public PowerShell scripts parsed and the GUI C# source compiled. All 26 files in the previously shared GUI ZIP matched the repository. Repackaging also reproduced the original archive SHA-256 on this machine. The original shareable ZIP is retained so existing downloads can be compared.

## Limits

- No other PC, AMD/Intel GPU, multiplayer session or future game build has been validated.
- The packaged warmup helper was measured with an already warm cache; first-ever cold-cache preparation on a friend's PC remains unmeasured. Loading and generation each allow up to three minutes.
- No high-DPI UI walkthrough has been performed.
- Driver updates or cache clearing can require another warmup.
- The 60 FPS cap remains part of the successful setup, but setting it alone did not resolve the observed timeout.
