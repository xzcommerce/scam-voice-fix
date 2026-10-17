param(
    [Parameter(Mandatory=$true)][string]$OriginalDll,
    [Parameter(Mandatory=$true)][string]$ManagedDirectory,
    [Parameter(Mandatory=$true)][string]$CecilPath,
    [Parameter(Mandatory=$true)][string]$OutputDirectory
)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
if((Get-FileHash -LiteralPath $CecilPath -Algorithm SHA256).Hash -ne 'C41BDB9FFD3C5F6E17D2382C1012D73703E035E3F1100245FDD4E08C8DC6EB5B'){throw 'Use Mono.Cecil 0.11.6 lib/net40/Mono.Cecil.dll from the official NuGet package'}
if((Get-FileHash -LiteralPath $OriginalDll -Algorithm SHA256).Hash -ne '99791CF93EC829D4784EE514AB78EBA19E5E4A7EA841B291D979432A5C911D8F'){throw 'Unsupported original game DLL'}
if(Test-Path -LiteralPath $OutputDirectory){throw 'Choose a new output directory. No existing files will be overwritten.'}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$logging=Join-Path $OutputDirectory 'logging-only.dll'
$patched=Join-Path $OutputDirectory 'Assembly-CSharp.dll'
& (Join-Path $repo 'patch-source\Add-Diagnostics.ps1') -Source $OriginalDll -Destination $logging -CecilPath $CecilPath -ManagedDirectory $ManagedDirectory
& (Join-Path $repo 'patch-source\Set-WorkerEnvironment.ps1') -Source $logging -Destination $patched -CecilPath $CecilPath -ManagedDirectory $ManagedDirectory
$expected='49CF032B165A0775EFC1B093BC137C82A3E3DF3D899755BA360103E3D48F8A83'
$actual=(Get-FileHash -LiteralPath $patched -Algorithm SHA256).Hash
if($actual -ne $expected){throw "Rebuild differs from the shipped DLL: $actual"}
Write-Output ('Verified exact patched DLL: '+$actual)
Write-Output 'Only the new output directory was written. Nothing was installed.'
