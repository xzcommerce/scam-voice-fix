param([string]$OutputZip='')
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
if(-not $OutputZip){$OutputZip=Join-Path $repo 'dist\Scam-Voice-Fix-GUI-26003210.zip'}
if(Test-Path -LiteralPath $OutputZip){throw 'Output already exists'}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$parent=Split-Path -Parent ([IO.Path]::GetFullPath($OutputZip))
New-Item -ItemType Directory -Path $parent -Force | Out-Null
[IO.Compression.ZipFile]::CreateFromDirectory((Join-Path $repo 'Scam-Voice-Fix'),$OutputZip,[IO.Compression.CompressionLevel]::Optimal,$true)
Get-FileHash -LiteralPath $OutputZip -Algorithm SHA256
Write-Output 'ZIP container bytes may differ due to timestamps. Extracted files must match the repository.'
