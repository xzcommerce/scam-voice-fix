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
    Write-Host 'SCAM WITH YOUR FRIENDS - ИСПРАВЛЕНИЕ ОЗВУЧКИ QWEN' -ForegroundColor Cyan
    Write-Host 'Для Steam-сборки 26003210 / Windows x64 / видеокарт NVIDIA'
    Write-Host ''
    # Checksums detect an incomplete extraction or accidental file corruption.
    $checks=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'checksums.json') -Raw | ConvertFrom-Json
    foreach($check in $checks) {
        if($check.Name -notin @('Fix-Core.ps1','Warmup.cs','voice-fix.patch','runtime-manifest.json')){throw 'Некорректный список файлов установщика.'}
        $path=Join-Path $PSScriptRoot $check.Name
        if(-not(Test-Path -LiteralPath $path) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $check.SHA256){throw 'Архив распакован не полностью или один из файлов повреждён. Снова извлеките весь ZIP-архив.'}
    }
    if(@($checks.Name | Select-Object -Unique).Count -ne 4){throw 'Список файлов установщика неполный.'}
    . (Join-Path $PSScriptRoot 'Fix-Core.ps1')
    if(-not [Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64'){throw 'Для этого набора нужна 64-разрядная Windows на процессоре Intel или AMD.'}
    $game=Find-Game
    $current=Assert-Compatible $game
    Write-Host ('Игра найдена: '+$game)
    if($Action -ne 'Check'){Assert-GameClosed}
    $backup=Get-BackupDirectory $game
    if($Action -eq 'Undo') {
        if(-not(Test-Path -LiteralPath (Join-Path $backup 'state.json'))){throw 'Активная резервная копия этого установщика не найдена. Изменений нет.'}
        Send-UiStage 'Restoring'
        Undo-Fix $game $backup
        $uiOutcome='Restored'
        Write-Host 'ОТМЕНЕНО. Исходный файл игры и ваши прежние настройки восстановлены.' -ForegroundColor Green
        Write-Host 'Запустите игру обычным способом через Steam.'
        exit 0
    }
    if($Action -ne 'Check' -and $current -eq $script:PatchedHash -and -not(Test-Path -LiteralPath (Join-Path $backup 'state.json'))) {
        $uiOutcome='AlreadyFixed'
        Write-Host 'На этом ПК уже установлено проверенное исправление. Изменений нет.' -ForegroundColor Green
        Write-Host 'Используйте сохранённую ранее резервную копию и инструкцию по отмене изменений.'
        exit 0
    }
    if($Action -ne 'Check' -and $current -eq $script:OriginalHash -and (Test-Path -LiteralPath (Join-Path $backup 'state.json'))) {
        throw 'Похоже, Steam восстановил исходный файл игры. Сначала запустите «2 - Отменить.cmd», затем снова «1 - Установить.cmd».'
    }
    $system=Get-CimInstance Win32_ComputerSystem
    $os=Get-CimInstance Win32_OperatingSystem
    if(($system.TotalPhysicalMemory/1MB) -lt 16000 -or $system.NumberOfLogicalProcessors -lt 4){throw 'В этой сборке игры для Qwen нужны около 16 ГБ оперативной памяти и минимум четыре потока процессора. Исправление кэша не снимает эти требования игры.'}
    if(($os.FreePhysicalMemory/1024) -lt 6144){throw 'Для Qwen нужно минимум 6 ГБ свободной оперативной памяти. Закройте другие ресурсоёмкие программы и снова запустите «1 - Установить.cmd».'}
    $smi=Get-Command nvidia-smi.exe -ErrorAction SilentlyContinue
    if(-not $smi){
        $candidate=Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe'
        if(Test-Path -LiteralPath $candidate){$smi=Get-Item -LiteralPath $candidate}
    }
    if(-not $smi){throw 'Этот набор предназначен для проблемы с кэшем NVIDIA. Утилита драйвера NVIDIA не найдена. Отправьте снимок этого окна тому, кто дал вам архив. Файлы игры не изменены.'}
    if($smi -is [IO.FileInfo]){$smiPath=$smi.FullName}else{$smiPath=$smi.Source}
    $gpuLines=@(& $smiPath '--query-gpu=name,memory.total,pci.device_id' '--format=csv,noheader,nounits' 2>$null)
    if($LASTEXITCODE -ne 0 -or $gpuLines.Count -eq 0){throw 'Не удалось получить сведения о видеокарте NVIDIA. Файлы игры не изменены.'}
    $eligible=$false
    foreach($line in $gpuLines){
        $parts=$line.Split(',')
        if($parts.Length -ne 3){continue}
        $memory=0
        if(-not [int]::TryParse($parts[1].Trim(),[ref]$memory)){continue}
        $device=[Convert]::ToUInt32($parts[2].Trim().Replace('0x',''),16) -shr 16
        Write-Host ('Видеокарта: '+$parts[0].Trim()+' / '+$memory+' МБ')
        if($memory -ge 8192 -and $device -ne 11141){$eligible=$true}
    }
    if(-not $eligible){throw 'В этой сборке игры для Qwen нужна поддерживаемая видеокарта с минимум 8 ГБ видеопамяти. Исправление кэша не снимает это требование игры.'}
    $assets=Join-Path $game 'Scam With Your Friends_Data\StreamingAssets'
    $runtime=Join-Path $assets 'kolkata-qwen-runtime'
    $runtimeManifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'runtime-manifest.json') -Raw | ConvertFrom-Json
    Write-Host 'Проверка установленного движка озвучки...'
    foreach($file in $runtimeManifest.files){
        if($file.path -match '(^[\\/]|\.\.|:)'){throw 'Некорректный путь в списке файлов движка озвучки.'}
        $path=Join-Path $runtime $file.path
        if(-not(Test-Path -LiteralPath $path) -or (Get-Hash $path) -ne $file.sha256){throw 'Установленный движок озвучки отличается от проверенной версии. Выполните проверку целостности файлов игры в Steam и повторите попытку.'}
    }
    $models=Join-Path (Split-Path -Parent $env:LOCALAPPDATA) 'LocalLow\Jatater Worldwide\Scam With Your Friends\qwen3-tts\b7ee2e8c7459c3bea99da23e3d178125a7d1713c'
    $modelHashes=@{
        'qwen-talker-0.6b-base-Q8_0.gguf'='D54DBAF10591421FA764ED630D764EFA717AE40CD959BD48C66D4EB1AF226426'
        'qwen-tokenizer-12hz-Q8_0.gguf'='1883BEEED99348FC35E23DD225E9082F93F6F8C109330A33D935BAA8ACDBFD94'
    }
    Write-Host 'Проверка загруженных моделей озвучки...'
    foreach($name in $modelHashes.Keys){
        $path=Join-Path $models $name
        if(-not(Test-Path -LiteralPath $path)){throw 'Игра ещё не загрузила модели Qwen. Откройте игру, включите Qwen для языков кроме английского, дождитесь загрузки, закройте игру и снова запустите «1 - Установить.cmd».'}
        if((Get-Hash $path) -ne $modelHashes[$name]){throw 'Модель озвучки загружена не полностью или отличается от проверенной версии. Дайте игре восстановить или загрузить модели Qwen, затем повторите попытку.'}
    }
    $voice=Join-Path $assets 'Callers\Defaults\b442c2193a1cee91e2572255fc73b8e62cee8d20e99d98152b04813e8e6b1b02\voice.wav'
    if(-not(Test-Path -LiteralPath $voice) -or (Get-Hash $voice) -ne '581F54F43F7E118B8E921A941792D5B35160F6ECE796F59D63BD2C3AE0A9EE14'){throw 'Стандартный голос игры, нужный для подготовки, отсутствует или изменён. Выполните проверку целостности файлов игры в Steam и повторите попытку.'}
    if($Action -eq 'Check') {
        $uiOutcome='Checked'
        Write-Host 'Проверки установщика, версии игры, оборудования, движка озвучки, моделей и голоса пройдены.' -ForegroundColor Green
        Write-Host 'Изменений нет.'
        exit 0
    }
    $null=New-Item -ItemType Directory -Path $backup -Force
    Start-Transcript -LiteralPath (Join-Path $backup 'last-install.txt') -Force | Out-Null
    $transcript=$true
    Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'Warmup.cs')))
    Write-Host 'Подготовка кэша озвучки. Не запускайте игру. Это может занять несколько минут...'
    Send-UiStage 'Preparing'
    $warm=[VoiceWarmup]::Run($runtime,$models,$voice,(Join-Path $backup 'warmup.log'))
    Write-Host ('Подготовка завершена. Первый звук через {0:F2} с.' -f $warm.FirstAudioSeconds)
    Write-Host 'Проверка озвучки после повторного запуска движка...'
    Send-UiStage 'Testing'
    $verify=[VoiceWarmup]::Run($runtime,$models,$voice,(Join-Path $backup 'verification.log'))
    $rtf=$verify.GenerationSeconds/$verify.AudioSeconds
    Write-Host ('Повторный запуск: первый звук через {0:F2} с; генерация занимает {1:F2} с на секунду звука.' -f $verify.FirstAudioSeconds,$rtf)
    [ordered]@{FirstWarmupSeconds=$warm.FirstAudioSeconds;FreshFirstAudioSeconds=$verify.FirstAudioSeconds;GenerationSeconds=$verify.GenerationSeconds;AudioSeconds=$verify.AudioSeconds;RTF=$rtf;Date=(Get-Date).ToString('o')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backup 'speed-check.json') -Encoding UTF8
    if($verify.FirstAudioSeconds -ge 4.5 -or $rtf -ge 1.0){throw ('Отдельная проверка показала, что озвучка на этом ПК всё ещё слишком медленная. Новые изменения не применены. Для диагностики отправьте файлы из папки '+$backup+' тому, кто дал вам архив.')}
    Send-UiStage 'Applying'
    Install-Fix $game $PSScriptRoot $backup
    $uiOutcome='Installed'
    Write-Host ''
    Write-Host 'ГОТОВО. Запустите игру обычным способом через Steam и выберите нужный язык звонков.' -ForegroundColor Green
    Write-Host 'Qwen включён для языков кроме английского. Частота кадров игры ограничена до 60 FPS.'
    Write-Host 'Проверьте два ответа персонажей в игре. Скорость во время игры может отличаться от отдельного теста.'
    Write-Host ('Резервная копия и журналы: '+$backup)
    Write-Host 'Для отмены изменений закройте игру и дважды нажмите «2 - Отменить.cmd».'
    Write-Host 'После обновления драйвера или очистки кэша снова запустите «1 - Установить.cmd» для подготовки кэша.'
} catch {
    $uiMessage=$_.Exception.Message
    Write-Host ''
    Write-Host ('ОСТАНОВЛЕНО: '+$_.Exception.Message) -ForegroundColor Yellow
    Write-Host 'Если нужна помощь, оставьте это окно открытым или сделайте его снимок.'
    exit 1
} finally {
    if($transcript){Stop-Transcript | Out-Null}
    if($ResultPath){
        [ordered]@{Outcome=$uiOutcome;Message=$uiMessage;Game=$game;Backup=$backup} | ConvertTo-Json | Set-Content -LiteralPath $ResultPath -Encoding UTF8
    }
}
