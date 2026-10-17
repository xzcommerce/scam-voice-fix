$ErrorActionPreference='Stop'
try {
    $app=Join-Path $PSScriptRoot 'App.ps1'
    if(-not(Test-Path -LiteralPath $app)){throw 'Extract the entire ZIP first. / Сначала распакуйте весь ZIP-архив.'}
    $arguments=@('-NoProfile','-STA','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"'+$app+'"'))
    Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $arguments -WindowStyle Hidden
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [Windows.Forms.MessageBox]::Show($_.Exception.Message,'Scam Voice Fix') | Out-Null
    exit 1
}
