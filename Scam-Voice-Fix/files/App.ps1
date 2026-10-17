$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
try {
    $source=Join-Path $PSScriptRoot 'VoiceFix.cs'
    if(-not(Test-Path -LiteralPath $source)){throw 'Extract the entire ZIP first. / Сначала распакуйте весь ZIP-архив.'}
    Add-Type -TypeDefinition ([IO.File]::ReadAllText($source)) -ReferencedAssemblies @('System','System.Core','System.Drawing','System.Windows.Forms','System.Web.Extensions')
    [ScamVoiceFix.VoiceForm]::RunApp($PSScriptRoot)
} catch {
    $message="Could not open Voice Fix. Extract the entire ZIP and try again.`r`nНе удалось открыть помощник. Распакуйте весь ZIP-архив и повторите попытку.`r`n`r`n"+$_.Exception.Message
    [Windows.Forms.MessageBox]::Show($message,'Scam Voice Fix',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    exit 1
}
