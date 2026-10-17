param([ValidateSet('Install','Undo','Check')][string]$Action='Install',[string]$ResultPath='')
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$transcript=$false
$uiOutcome='Error'
$uiMessage=''
$game=$null
$backup=$null
function Send-UiStage([string]$Stage){ if($ResultPath){Write-Host ('@@VOICEFIX:'+ $Stage)} }
Send-UiStage 'Checking'
try {
    Write-Host ''
    Write-Host 'SCAM WITH YOUR FRIENDS - QWEN VOICE FIX' -ForegroundColor Cyan
    Write-Host 'For Steam build 26003210 / Windows x64 / NVIDIA graphics'
    Write-Host ''
    # Checksums detect an incomplete extraction or accidental file corruption.
    $checks=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'checksums.json') -Raw | ConvertFrom-Json
    foreach($check in $checks) {
        if($check.Name -notin @('Fix-Core.ps1','Warmup.cs','voice-fix.patch','runtime-manifest.json')){throw 'Invalid package manifest.'}
        $path=Join-Path $PSScriptRoot $check.Name
        if(-not(Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $check.SHA256){throw 'The ZIP was not fully extracted or a file is damaged. Extract the whole ZIP again.'}
    }
    if(@($checks.Name | Select-Object -Unique).Count -ne 4){throw 'Incomplete package manifest.'}
    . (Join-Path $PSScriptRoot 'Fix-Core.ps1')
    if(-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'){throw 'This kit requires 64-bit Windows on an Intel or AMD processor.'}
    $game=Find-Game
    $current=Assert-Compatible $game
    Write-Host ('Game found: '+$game)
    if($Action -ne 'Check'){Assert-GameClosed}
    $backup=Get-BackupDirectory $game
    if($Action -eq 'Undo') {
        if(-not(Test-Path -LiteralPath (Join-Path $backup 'state.json'))){throw 'No active backup from this installer was found. Nothing changed.'}
        Send-UiStage 'Restoring'
        Undo-Fix $game $backup
        $uiOutcome='Restored'
        Write-Host 'UNDONE. Original game file and your previous settings restored.' -ForegroundColor Green
        Write-Host 'Start the game normally through Steam.'
        exit 0
    }
    if($Action -ne 'Check' -and $current -eq $script:PatchedHash -and -not(Test-Path -LiteralPath (Join-Path $backup 'state.json'))) {
        $uiOutcome='AlreadyFixed'
        Write-Host 'This PC already has the tested fix. No changes made.' -ForegroundColor Green
        Write-Host 'Keep using its existing backup and undo instructions.'
        exit 0
    }
    if($Action -ne 'Check' -and $current -eq $script:OriginalHash -and (Test-Path -LiteralPath (Join-Path $backup 'state.json'))) {
        throw 'Steam appears to have restored the original game file. Run Undo first, then Install again.'
    }
    $system=Get-CimInstance Win32_ComputerSystem
    $os=Get-CimInstance Win32_OperatingSystem
    if(($system.TotalPhysicalMemory/1MB) -lt 16000 -or $system.NumberOfLogicalProcessors -lt 4){throw 'This game build requires about 16 GB of system RAM and at least four CPU threads for Qwen. This cache fix cannot remove that hardware limit.'}
    if(($os.FreePhysicalMemory/1024) -lt 6144){throw 'Qwen needs at least 6 GB of free system RAM. Close other large apps and run Install again.'}
    $smi=Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if(-not $smi){
        $candidate=Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
        if(Test-Path -LiteralPath $candidate){$smi=Get-Item -LiteralPath $candidate}
    }
    if(-not $smi){throw 'This kit is for the NVIDIA cache problem. No NVIDIA driver tool was found. Send a screenshot of this message for help; no game files were changed.'}
    if($smi -is [IO.FileInfo]){$smiPath=$smi.FullName}else{$smiPath=$smi.Source}
    $gpuLines=@(& $smiPath '--query-gpu=name,memory.total,pci.device_id' '--format=csv,noheader,nounits' 2>$null)
    if($LASTEXITCODE -ne 0 -or $gpuLines.Count -eq 0){throw 'Could not read NVIDIA GPU information. No game files were changed.'}
    $eligible=$false
    foreach($line in $gpuLines){
        $parts=$line.Split(',')
        if($parts.Length -ne 3){continue}
        $memory=0
        if(-not [int]::TryParse($parts[1].Trim(),[ref]$memory)){continue}
        $device=[Convert]::ToUInt32($parts[2].Trim().Replace('0x',''),16) -shr 16
        Write-Host ('GPU: '+$parts[0].Trim()+' / '+$memory+' MB')
        if($memory -ge 8192 -and $device -ne 11141){$eligible=$true}
    }
    if(-not $eligible){throw 'This game build requires a supported GPU with at least 8 GB of graphics memory for Qwen. This cache fix cannot remove that hardware limit.'}
    $assets=Join-Path $game 'Scam With Your Friends_Data\StreamingAssets'
    $runtime=Join-Path $assets 'kolkata-qwen-runtime'
    $runtimeManifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime-manifest.json') -Raw | ConvertFrom-Json
    Write-Host 'Checking the installed speech engine...'
    foreach($file in $runtimeManifest.files){
        if($file.path -match '(^[\\/]|\.\.|:)'){throw 'Invalid runtime manifest path.'}
        $path=Join-Path $runtime $file.path
        if(-not(Test-Path -LiteralPath $path) -or (Get-Hash $path) -ne $file.sha256){throw 'The installed speech engine differs from the tested version. Use Steam Verify Integrity, then try again.'}
    }
    $models=Join-Path (Split-Path -Parent $env:LOCALAPPDATA) 'LocalLow\Jatater Worldwide\Scam With Your Friends\qwen3-tts\b7ee2e8c7459c3bea99da23e3d178125a7d1713c'
    $modelHashes=@{
        'qwen-talker-0.6b-base-Q8_0.gguf'='D54DBAF10591421FA764ED630D764EFA717AE40CD959BD48C66D4EB1AF226426'
        'qwen-tokenizer-12hz-Q8_0.gguf'='1883BEEED99348FC35E23DD225E9082F93F6F8C109330A33D935BAA8ACDBFD94'
    }
    Write-Host 'Checking the downloaded voice models...'
    foreach($name in $modelHashes.Keys){
        $path=Join-Path $models $name
        if(-not(Test-Path -LiteralPath $path)){throw 'The game has not downloaded its Qwen voice models yet. Open the game, enable Qwen speech for non-English languages, let its download finish, close the game, then run Install again.'}
        if((Get-Hash $path) -ne $modelHashes[$name]){throw 'A downloaded voice model is incomplete or different from the tested version. Let the game repair/download its Qwen models, then try again.'}
    }
    $voice=Join-Path $assets 'Callers\Defaults\b442c2193a1cee91e2572255fc73b8e62cee8d20e99d98152b04813e8e6b1b02\voice.wav'
    if(-not(Test-Path -LiteralPath $voice) -or (Get-Hash $voice) -ne '581F54F43F7E118B8E921A941792D5B35160F6ECE796F59D63BD2C3AE0A9EE14'){throw 'The standard game voice used for preparation is missing or different. Use Steam Verify Integrity, then try again.'}
    if($Action -eq 'Check') {
        $uiOutcome='Checked'
        Write-Host 'Package, game version, hardware, speech engine, models and voice checks passed.' -ForegroundColor Green
        Write-Host 'No changes made.'
        exit 0
    }
    $null=New-Item -ItemType Directory -Path $backup -Force
    Start-Transcript -LiteralPath (Join-Path $backup 'last-install.txt') -Force | Out-Null
    $transcript=$true
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Warmup.cs')))
    Write-Host 'Preparing the voice cache. Keep the game closed. This can take a few minutes...'
    Send-UiStage 'Preparing'
    $warm=[VoiceWarmup]::Run($runtime,$models,$voice,(Join-Path $backup 'warmup.log'))
    Write-Host ('Preparation complete. First audio: {0:F2} s.' -f $warm.FirstAudioSeconds)
    Write-Host 'Checking a fresh speech worker...'
    Send-UiStage 'Testing'
    $verify=[VoiceWarmup]::Run($runtime,$models,$voice,(Join-Path $backup 'verification.log'))
    $rtf=$verify.GenerationSeconds/$verify.AudioSeconds
    Write-Host ('Fresh worker: first audio {0:F2} s; generation/playback ratio {1:F2}.' -f $verify.FirstAudioSeconds,$rtf)
    [ordered]@{FirstWarmupSeconds=$warm.FirstAudioSeconds;FreshFirstAudioSeconds=$verify.FirstAudioSeconds;GenerationSeconds=$verify.GenerationSeconds;AudioSeconds=$verify.AudioSeconds;RTF=$rtf;Date=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'speed-check.json') -Encoding UTF8
    if($verify.FirstAudioSeconds -ge 4.5 -or $rtf -ge 1.0){throw ('Speech is still too slow on this PC in the standalone check. No new patch or settings were applied. Send the files in '+$backup+' for diagnosis.')}
    Send-UiStage 'Applying'
    Install-Fix $game $PSScriptRoot $backup
    $uiOutcome='Installed'
    Write-Host ''
    Write-Host 'DONE. Start the game normally through Steam and use your preferred call language.' -ForegroundColor Green
    Write-Host 'Qwen is enabled for non-English voices. Game FPS is capped at 60.'
    Write-Host 'Try two NPC replies. This check cannot guarantee performance while playing.'
    Write-Host ('Backup and logs: '+$backup)
    Write-Host 'To revert: close the game and double-click 2 - Undo.cmd.'
    Write-Host 'After a driver update or cache cleanup, run Install again to prepare the cache.'
} catch {
    $uiMessage=$_.Exception.Message
    Write-Host ''
    Write-Host ('STOPPED: '+$_.Exception.Message) -ForegroundColor Yellow
    Write-Host 'Keep this window open or take a screenshot if you need help.'
    exit 1
} finally {
    if($transcript){Stop-Transcript | Out-Null}
    if($ResultPath){
        [ordered]@{Outcome=$uiOutcome;Message=$uiMessage;Game=$game;Backup=$backup} | ConvertTo-Json | Set-Content -LiteralPath $ResultPath -Encoding UTF8
    }
}
