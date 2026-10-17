param([Parameter(Mandatory=$true)][string]$OriginalDll)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$build=Join-Path $repo '.local'
New-Item -ItemType Directory -Path $build -Force | Out-Null
$files=Join-Path $repo 'Scam-Voice-Fix\files\engine\EN\files'
foreach($path in (Get-ChildItem -LiteralPath $files -Filter '*.ps1')) {
    $tokens=$null;$errors=$null
    $null=[Management.Automation.Language.Parser]::ParseFile($path.FullName,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors | Out-String)}
}
Add-Type -TypeDefinition ([IO.File]::ReadAllText((Join-Path $files 'Warmup.cs')))
. (Join-Path $files 'Fix-Core.ps1')
$productionClosedGuard=${function:Assert-GameClosed}
$guardWorked=$false
try{Assert-GameClosed}catch{$guardWorked=$true}
if(Get-Process -Name 'Scam With Your Friends','QwenTtsWorker' -ErrorAction SilentlyContinue){if(-not $guardWorked){throw 'Live-game guard failed.'}}
# Only isolated DLL copies and a throwaway registry key are used below.
function Assert-GameClosed {}
$id=[guid]::NewGuid().ToString('N')
$script:PrefsKey='Software\ScamVoiceFix-InstallerTests\'+$id
$testRoot=Join-Path $build ('test-'+$id)
$game=Join-Path $testRoot 'Тест игры [one]'
$backup=Join-Path $testRoot 'backup'
$managed=Join-Path $game 'Scam With Your Friends_Data\Managed'
$null=New-Item -ItemType Directory -Path $managed -Force
$dll=Get-GameDll $game
Copy-Item -LiteralPath $OriginalDll -Destination $dll
$tests=[Collections.Generic.List[string]]::new()
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw $Message}}
try{
    Assert ((Assert-Compatible $game) -eq $script:OriginalHash) 'Original compatibility failed'
    $tests.Add('PowerShell syntax and C# compilation; live-game guard')
    # Verify missing preference values are removed again by Undo.
    Install-Fix $game $files $backup
    Assert ((Get-Hash $dll) -eq $script:PatchedHash) 'Patch differs from the exact tested DLL'
    $prefs=@(Read-Preferences)
    Assert ($prefs[0].Value -eq 0 -and $prefs[1].Value -eq 4) 'Fixed preferences missing'
    $saved=[IO.File]::ReadAllText((Join-Path $backup 'state.json'))
    Install-Fix $game $files $backup
    Assert ($saved -eq [IO.File]::ReadAllText((Join-Path $backup 'state.json'))) 'Repeated install changed original backup'
    $tests.Add('Exact patch reconstruction; Unicode/bracket paths; install and repeat install')
    Undo-Fix $game $backup
    Assert ((Get-Hash $dll) -eq $script:OriginalHash) 'Undo file mismatch'
    Assert (@(Read-Preferences | Where-Object Exists).Count -eq 0) 'Absent settings were not restored'
    $tests.Add('Undo restores exact original and removes previously absent settings')
    $before=@([pscustomobject]@{Name=$script:PreferenceNames[0];Exists=$true;Kind='DWord';Value=2},[pscustomobject]@{Name=$script:PreferenceNames[1];Exists=$true;Kind='DWord';Value=-1})
    Write-Preferences $before
    Install-Fix $game $files $backup
    # Simulate a Steam update: neither install nor undo may overwrite it.
    $altered=[IO.File]::ReadAllBytes($dll);$altered[300]=$altered[300] -bxor 1;[IO.File]::WriteAllBytes($dll,$altered)
    $changedHash=Get-Hash $dll
    $blocked=$false;try{Install-Fix $game $files $backup}catch{$blocked=$true}
    Assert $blocked 'Unknown DLL accepted by install'
    $blocked=$false;try{Undo-Fix $game $backup}catch{$blocked=$true}
    Assert $blocked 'Unknown DLL accepted by undo'
    Assert ((Get-Hash $dll) -eq $changedHash) 'Unknown DLL was overwritten'
    $tests.Add('Different game build rejected by both install and undo without overwrite')
    Copy-Item -LiteralPath (Join-Path $backup 'patched.dll') -Destination $dll -Force
    Undo-Fix $game $backup
    $prefs=@(Read-Preferences)
    Assert ($prefs[0].Value -eq 2 -and $prefs[1].Value -eq -1) 'Previous settings not restored'
    $tests.Add('Undo restores existing settings including unlimited FPS (-1)')
    # Failed settings write must roll back the installed DLL and old settings.
    $setter=${function:Set-FixedPreferences}
    function Set-FixedPreferences {throw 'Simulated settings-write failure'}
    $blocked=$false;try{Install-Fix $game $files $backup}catch{$blocked=$true}
    Set-Item -Path Function:Set-FixedPreferences -Value $setter
    Assert $blocked 'Simulated failure ignored'
    Assert ((Get-Hash $dll) -eq $script:OriginalHash) 'Rollback did not restore original DLL'
    $prefs=@(Read-Preferences)
    Assert ($prefs[0].Value -eq 2 -and $prefs[1].Value -eq -1) 'Rollback did not restore settings'
    $tests.Add('Partial install failure rolls back DLL and settings')
    Undo-Fix $game $backup
    # Steam Verify Integrity restores the same original. Undo still restores prefs.
    Install-Fix $game $files $backup
    Copy-Item -LiteralPath (Join-Path $backup 'original.dll') -Destination $dll -Force
    Undo-Fix $game $backup
    Assert ((Get-Hash $dll) -eq $script:OriginalHash) 'Undo after Steam verification failed'
    $tests.Add('Undo after Steam restores the same supported original')
    # A truncated delta must never produce a result.
    $broken=Join-Path $testRoot 'broken.patch'
    [IO.File]::WriteAllBytes($broken,[Text.Encoding]::ASCII.GetBytes('QWENFIX1'))
    $output=Join-Path $testRoot 'must-not-exist.dll'
    $blocked=$false;try{New-PatchedFile $dll $broken $output}catch{$blocked=$true}
    Assert ($blocked -and -not(Test-Path -LiteralPath $output)) 'Corrupt patch accepted'
    $tests.Add('Truncated patch rejected before output/game writes')
    $tests | ForEach-Object {Write-Output ('PASS: '+$_)}
    [ordered]@{Date=(Get-Date).ToString('o');Passed=$true;Tests=$tests.ToArray();Fixture=$testRoot} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $build 'installer-test-results.json') -Encoding UTF8
}finally{
    # This exact unique key was created only by this test run.
    if($script:PrefsKey -eq ('Software\ScamVoiceFix-InstallerTests\'+$id)){
        [Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($script:PrefsKey,$false)
    }
}
