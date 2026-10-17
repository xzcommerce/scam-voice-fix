# Offline, version-specific installer. All game-file writes are hash guarded.
Set-StrictMode -Version 2.0
$script:OriginalHash = '53BD673F796EA21F8B1512C3F113E6BB1997CE62665AB3EF2C1A72B4BED490EC'
$script:PatchedHash = '27C1332662B862A2DED30370D36294C20AEAAA9847260FDA4FF4DEA82B06312D'
$script:PrefsKey = 'Software\Jatater Worldwide\Scam With Your Friends'
$script:PreferenceNames = @('Kolkata.Qwen3Tts_h1324939569','Max FPS_h1315227636')

function Get-Hash([string]$Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Assert-GameClosed {
    if (Get-Process -Name 'Scam With Your Friends','QwenTtsWorker' -ErrorAction SilentlyContinue) {
        throw 'Сначала закройте Scam With Your Friends, затем снова запустите этот файл. Ничего не установлено.'
    }
}
function Get-GameDll([string]$Game) {
    Join-Path $Game 'Scam With Your Friends_Data\Managed\Assembly-CSharp.dll'
}
function Assert-Compatible([string]$Game) {
    $dll = Get-GameDll $Game
    if (-not (Test-Path -LiteralPath $dll)) { throw 'В этой папке нет игры Scam With Your Friends.' }
    $hash = Get-Hash $dll
    if ($hash -notin @($script:OriginalHash,$script:PatchedHash)) {
        throw 'У вас другая версия игры или уже установлен другой мод. Исправление поддерживает только сборку 25996926. Файлы игры не изменены. Попросите обновлённый набор.'
    }
    return $hash
}
function Find-Game {
    $roots = [Collections.Generic.List[string]]::new()
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Valve\Steam')
    if ($key) { try { $value = $key.GetValue('SteamPath'); if ($value) { $roots.Add([string]$value) } } finally { $key.Close() } }
    if (${env:ProgramFiles(x86)}) { $roots.Add((Join-Path ${env:ProgramFiles(x86)} 'Steam')) }
    foreach ($root in @($roots.ToArray())) {
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($match in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s*"([^"]+)"')) {
                $roots.Add($match.Groups[1].Value.Replace('\\','\'))
            }
        }
    }
    $found = @()
    foreach ($root in ($roots | Select-Object -Unique)) {
        if (-not [IO.Directory]::Exists($root)) { continue }
        $manifest = Join-Path $root 'steamapps\appmanifest_4954910.acf'
        if (Test-Path -LiteralPath $manifest) {
            $match = [regex]::Match([IO.File]::ReadAllText($manifest), '"installdir"\s*"([^"]+)"')
            if ($match.Success) {
                $game = [IO.Path]::GetFullPath((Join-Path (Join-Path $root 'steamapps\common') $match.Groups[1].Value))
                if (Test-Path -LiteralPath (Get-GameDll $game)) { $found += $game }
            }
        }
    }
    $found = @($found | Sort-Object -Unique)
    if ($found.Count -eq 1) { return $found[0] }
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
    $dialog.Description = 'Выберите папку Scam With Your Friends: Steam > Управление > Просмотреть локальные файлы.'
    $dialog.ShowNewFolderButton = $false
    try {
        if ($dialog.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { throw 'Папка игры не выбрана. Изменений нет.' }
        return $dialog.SelectedPath
    } finally { $dialog.Dispose() }
}
function Get-BackupDirectory([string]$Game) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $id = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Game.ToLowerInvariant()))).Replace('-','').Substring(0,16) } finally { $sha.Dispose() }
    Join-Path $env:LOCALAPPDATA ("ScamVoiceFix\25996926-" + $id)
}
function Read-Preferences {
    $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($script:PrefsKey)
    try {
        foreach ($name in $script:PreferenceNames) {
            $exists = $key -and ($name -in $key.GetValueNames())
            $value = $null; $kind = $null
            if ($exists) {
                $kind = $key.GetValueKind($name).ToString()
                if ($kind -ne 'DWord') { throw ('Неожиданный тип сохранённой настройки: ' + $name) }
                $value = $key.GetValue($name)
            }
            [pscustomobject]@{ Name=$name; Exists=[bool]$exists; Value=$value; Kind=$kind }
        }
    } finally { if ($key) { $key.Close() } }
}
function Write-Preferences($Preferences) {
    # Only these two integer settings can be written/restored. Never read API keys.
    if (@($Preferences).Count -ne 2) { throw 'Резервная копия настроек некорректна.' }
    foreach ($pref in $Preferences) {
        if ($pref.Name -notin $script:PreferenceNames -or ($pref.Exists -and $pref.Kind -ne 'DWord')) { throw 'Резервная копия настроек некорректна.' }
    }
    if (@($Preferences.Name | Select-Object -Unique).Count -ne 2) { throw 'Резервная копия настроек некорректна.' }
    $key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($script:PrefsKey)
    try {
        foreach ($pref in $Preferences) {
            if ($pref.Exists) { $key.SetValue($pref.Name,[int]$pref.Value,[Microsoft.Win32.RegistryValueKind]::DWord) }
            else { $key.DeleteValue($pref.Name,$false) }
        }
        $key.Flush()
    } finally { $key.Close() }
}
function Set-FixedPreferences {
    Write-Preferences @(
        [pscustomobject]@{Name=$script:PreferenceNames[0];Exists=$true;Kind='DWord';Value=0},
        [pscustomobject]@{Name=$script:PreferenceNames[1];Exists=$true;Kind='DWord';Value=4}
    )
}
function New-PatchedFile([string]$Original,[string]$Delta,[string]$Output) {
    if ((Get-Hash $Original) -ne $script:OriginalHash) { throw 'Исходный файл игры не соответствует поддерживаемой версии.' }
    $reader = [IO.BinaryReader]::new([IO.File]::OpenRead($Delta))
    try {
        if ([Text.Encoding]::ASCII.GetString($reader.ReadBytes(8)) -ne 'QWENFIX1') { throw 'Данные исправления повреждены.' }
        $length = $reader.ReadInt32()
        if ($length -ne 2915328) { throw 'Некорректный размер данных исправления.' }
        $bytes = New-Object byte[] $length
        $originalBytes = [IO.File]::ReadAllBytes($Original)
        [Array]::Copy($originalBytes,$bytes,[Math]::Min($originalBytes.Length,$length))
        $end = 0
        while ($true) {
            $offset = $reader.ReadInt32()
            if ($offset -eq -1) { break }
            $count = $reader.ReadInt32()
            if ($offset -lt $end -or $count -le 0 -or ([long]$offset+$count) -gt $length) { throw 'Некорректный диапазон данных исправления.' }
            $part = $reader.ReadBytes($count)
            if ($part.Length -ne $count) { throw 'Данные исправления неполные.' }
            [Array]::Copy($part,0,$bytes,$offset,$count)
            $end = $offset+$count
        }
        if ($reader.BaseStream.Position -ne $reader.BaseStream.Length) { throw 'После данных исправления обнаружены лишние данные.' }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','') } finally { $sha.Dispose() }
        if ($hash -ne $script:PatchedHash) { throw 'Проверка исправленного файла не пройдена. Игра не изменена.' }
        [IO.File]::WriteAllBytes($Output,$bytes)
    } finally { $reader.Dispose() }
}
function Replace-Verified([string]$Source,[string]$Target,[string]$ExpectedCurrent,[string]$ExpectedNew) {
    if ((Get-Hash $Source) -ne $ExpectedNew -or (Get-Hash $Target) -ne $ExpectedCurrent) { throw 'Файл игры изменился во время установки. Остановка.' }
    # Atomic replace: a crash cannot leave a half-written game DLL.
    $temp = Join-Path (Split-Path -Parent $Target) ('qwen-fix-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::Copy($Source,$temp,$false)
        if ((Get-Hash $temp) -ne $ExpectedNew -or (Get-Hash $Target) -ne $ExpectedCurrent) { throw 'Файл игры изменился во время установки. Остановка.' }
        [IO.File]::Replace($temp,$Target,[NullString]::Value)
        if ((Get-Hash $Target) -ne $ExpectedNew) { throw 'Проверка установленного файла не пройдена.' }
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}
function Read-Backup([string]$Backup,[string]$Game) {
    $state = Get-Content -LiteralPath (Join-Path $Backup 'state.json') -Raw | ConvertFrom-Json
    if ($state.Game -ne $Game -or $state.OriginalHash -ne $script:OriginalHash -or $state.PatchedHash -ne $script:PatchedHash) { throw 'Резервная копия не соответствует этой установленной игре.' }
    if ((Get-Hash (Join-Path $Backup 'original.dll')) -ne $script:OriginalHash) { throw 'Резервная копия исходного файла повреждена. Восстановите игру через проверку целостности файлов в Steam.' }
    return $state
}
function Install-Fix([string]$Game,[string]$Files,[string]$Backup) {
    Assert-GameClosed
    $current = Assert-Compatible $Game
    $dll = Get-GameDll $Game
    $stateFile = Join-Path $Backup 'state.json'
    if ($current -eq $script:PatchedHash) {
        if (-not (Test-Path -LiteralPath $stateFile)) { throw 'На этом ПК уже установлено проверенное исправление. Сохраните прежнюю резервную копию и инструкцию по отмене. Изменений нет.' }
        $null = Read-Backup $Backup $Game
        $before = @(Read-Preferences)
        try { Set-FixedPreferences } catch { Write-Preferences $before; throw }
        return
    }
    if (Test-Path -LiteralPath $stateFile) {
        $null = Read-Backup $Backup $Game
        throw 'Резервная копия уже существует, но Steam восстановил исходный файл игры. Сначала запустите «2 - Отменить.cmd», затем «1 - Установить.cmd», чтобы сохранить текущие настройки правильно.'
    }
    $null = New-Item -ItemType Directory -Path $Backup -Force
    $preferences = @(Read-Preferences)
    $original = Join-Path $Backup 'original.dll'
    if ((Test-Path -LiteralPath $original) -and (Get-Hash $original) -ne $script:OriginalHash) { throw 'Существующая резервная копия не соответствует нужной версии. Остановка.' }
    Copy-Item -LiteralPath $dll -Destination $original -Force
    if ((Get-Hash $original) -ne $script:OriginalHash) { throw 'Проверка резервной копии не пройдена.' }
    $staged = Join-Path $Backup 'patched.dll'
    New-PatchedFile $original (Join-Path $Files 'voice-fix.patch') $staged
    [ordered]@{Game=$Game;OriginalHash=$script:OriginalHash;PatchedHash=$script:PatchedHash;Preferences=$preferences;Created=(Get-Date).ToString('o')} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $stateFile -Encoding UTF8
    $changed = $false
    try {
        Assert-GameClosed
        Replace-Verified $staged $dll $script:OriginalHash $script:PatchedHash
        $changed = $true
        Set-FixedPreferences
    } catch {
        $problem = $_
        if ($changed) { Replace-Verified $original $dll $script:PatchedHash $script:OriginalHash }
        Write-Preferences $preferences
        throw $problem
    }
}
function Undo-Fix([string]$Game,[string]$Backup) {
    Assert-GameClosed
    $current = Assert-Compatible $Game
    $state = Read-Backup $Backup $Game
    $before = @(Read-Preferences)
    $changed = $false
    try {
        if ($current -eq $script:PatchedHash) {
            Replace-Verified (Join-Path $Backup 'original.dll') (Get-GameDll $Game) $script:PatchedHash $script:OriginalHash
            $changed = $true
        }
        Write-Preferences $state.Preferences
    } catch {
        $problem = $_
        if ($changed) { Replace-Verified (Join-Path $Backup 'patched.dll') (Get-GameDll $Game) $script:OriginalHash $script:PatchedHash }
        Write-Preferences $before
        throw $problem
    }
    # Retain the original backup; archive metadata so a later install captures fresh settings.
    Move-Item -LiteralPath (Join-Path $Backup 'state.json') -Destination (Join-Path $Backup ('restored-' + [guid]::NewGuid().ToString('N') + '.json'))
}
