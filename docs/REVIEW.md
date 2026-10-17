# Review guide

## Entry points

All links below point to source files you can read before running anything.

| File | Purpose |
| --- | --- |
| [START.cmd](../Scam-Voice-Fix/START.cmd) | Checks that the package was extracted, selects Windows PowerShell, starts the launcher. |
| [Launch.ps1](../Scam-Voice-Fix/files/Launch.ps1) | Launches the GUI with a hidden console and process-scoped execution-policy bypass. |
| [App.ps1](../Scam-Voice-Fix/files/App.ps1) | Compiles the included C# WinForms source with `Add-Type`. |
| [VoiceFix.cs](../Scam-Voice-Fix/files/VoiceFix.cs) | English/Russian interface; starts the selected backend and displays its results. |
| [Fix.ps1](../Scam-Voice-Fix/files/engine/EN/files/Fix.ps1) | Compatibility checks, official-worker warmup, speed gate, install/undo orchestration. |
| [Fix-Core.ps1](../Scam-Voice-Fix/files/engine/EN/files/Fix-Core.ps1) | Steam discovery, hash checks, delta reconstruction, atomic replacement, backup/restore, two registry preferences. |
| [Warmup.cs](../Scam-Voice-Fix/files/engine/EN/files/Warmup.cs) | Binary-pipe communication with the installed official Qwen worker. |
| [Russian backend](../Scam-Voice-Fix/files/engine/RU/files/) | Localized messages with the same patch and behavior. |
| [Add-Diagnostics.ps1](../patch-source/Add-Diagnostics.ps1) | Adds the diagnostic logging to the original DLL. |
| [Set-WorkerEnvironment.ps1](../patch-source/Set-WorkerEnvironment.ps1) | Adds the worker-only cache and Vulkan-layer environment changes. |

## What the DLL patch does

The two Mono.Cecil scripts modify `Kolkata.QwenTts.QwenWorkerClient`:

1. Add `LocalDiagnosticLog`, forwarding previously ignored worker stderr and logging model/synthesis request boundaries with UTC timestamps.
2. Immediately before the constructor starts the worker, remove these four entries from **that child process's** `ProcessStartInfo.EnvironmentVariables`:
   - `__GL_SHADER_DISK_CACHE_PATH`
   - `__GL_SHADER_DISK_CACHE_APP_NAME`
   - `__GL_SHADER_DISK_CACHE_READ_ONLY_APP_NAME`
   - `__GL_SHADER_DISK_CACHE_SKIP_CLEANUP`
3. Set `DISABLE_VK_LAYER_VALVE_steam_fossilize_1=1` and `DISABLE_VK_LAYER_VALVE_steam_overlay_1=1` in the same child environment.

The patch leaves the five-second timeout, models, speech protocol and multiplayer routing unchanged. Disabling the Steam Vulkan layers alone did not fix the tested PC; the normal-cache warmup and NVIDIA environment cleanup were necessary parts of the successful setup.

`voice-fix.patch` is a binary delta, not executable source. `New-PatchedFile` reconstructs a DLL from the exact supported original and checks the full output hash before writing it. A checksum detects differences; by itself it is not proof of trust. The source rebuild below lets reviewers independently compare the result.

## Rebuild the DLL from source

Use **Windows PowerShell 5.1 / .NET Framework**, your own original DLL from supported build 25996926, and its installed `Managed` folder for assembly resolution. If the fix is installed, use your saved original backup as the input. These scripts write to a new output directory and do not install anything.

The developer-only dependency is [Mono.Cecil 0.11.6](https://www.nuget.org/packages/Mono.Cecil/0.11.6). Download its official NuGet package, extract it as a ZIP, and use `lib/net40/Mono.Cecil.dll`. The end-user helper does not download or require Cecil.

```powershell
.\tools\Build-Patch.ps1 `
  -OriginalDll 'C:\path\to\original\Assembly-CSharp.dll' `
  -ManagedDirectory 'C:\path\to\game\Scam With Your Friends_Data\Managed' `
  -CecilPath 'C:\path\to\cecil\lib\net40\Mono.Cecil.dll' `
  -OutputDirectory '.\.local\rebuild'
```

SHA-256 values:

```text
Original game DLL:
53BD673F796EA21F8B1512C3F113E6BB1997CE62665AB3EF2C1A72B4BED490EC
Patched game DLL:
27C1332662B862A2DED30370D36294C20AEAAA9847260FDA4FF4DEA82B06312D
Mono.Cecil 0.11.6 NuGet package:
D2A23832AAA948BA9A01ACC42B5726E34C5F995958F1B30D45C0E7C70B3A72D5
Mono.Cecil lib/net40/Mono.Cecil.dll:
C41BDB9FFD3C5F6E17D2382C1012D73703E035E3F1100245FDD4E08C8DC6EB5B
Previously shared GUI ZIP:
3E909AB435EAA26D420A55A926120F0D6D80EDA8C8AF5DB21F3FEFB5A82C95BB
```

The rebuild must match the patched DLL hash above exactly. The installer checks the same hash after reconstructing the binary delta. You can also inspect or decompile your own original/rebuilt DLLs to compare changes. No full game DLLs are distributed here.

## Package and tests

`tools/Package.ps1` creates a ZIP from the checked-in `Scam-Voice-Fix` folder. ZIP timestamps can change the archive hash; extracted file bytes are the relevant source comparison. `.gitattributes` disables automatic newline conversion because the installer verifies byte hashes.

`tests/Test-Installer.ps1 -OriginalDll <path>` exercises installation and rollback against isolated DLL copies and a unique temporary registry key. It does not install into the live game. See [TESTING.md](TESTING.md).

## Writes and processes

- Game write: only `Scam With Your Friends_Data/Managed/Assembly-CSharp.dll`, guarded by exact input/output hashes.
- Preferences: only `Kolkata.Qwen3Tts_h1324939569` and `Max FPS_h1315227636` under `HKCU/Software/Jatater Worldwide/Scam With Your Friends`.
- Backups, state and warmup/installer logs: `%LOCALAPPDATA%/ScamVoiceFix`; GUI result files use temporary local storage.
- Processes: Windows PowerShell for the interface/backend, `nvidia-smi` for GPU information, and the already installed `QwenTtsWorker.exe` for preparation/verification.
- Normal NVIDIA cache files may be created or updated by the official worker/driver. Undo restores the DLL and preferences; it does not delete shader cache files.

The warmup uses a fixed Russian phrase and the game's standard reference voice, with no microphone or audio playback. Its worker is assigned a 4 GiB job memory limit and terminated on job close. It runs twice, requiring the second fresh worker to produce first audio in under 4.5 seconds and generate faster than real-time before installation proceeds.

Public bug reports should include relevant error lines and hardware, not entire private game logs or backup folders: those can include local paths and conversation data.
