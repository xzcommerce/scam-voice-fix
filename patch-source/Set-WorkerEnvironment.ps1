param(
 [Parameter(Mandatory=$true)][string]$Source,
 [Parameter(Mandatory=$true)][string]$Destination,
 [Parameter(Mandatory=$true)][string]$CecilPath,
 [Parameter(Mandatory=$true)][string]$ManagedDirectory
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Destination){throw 'Output already exists'}
Add-Type -Path $CecilPath
$resolver=[Mono.Cecil.DefaultAssemblyResolver]::new()
$resolver.AddSearchDirectory($ManagedDirectory)
$parameters=[Mono.Cecil.ReaderParameters]::new()
$parameters.AssemblyResolver=$resolver
$module=[Mono.Cecil.ModuleDefinition]::ReadModule($source,$parameters)
try {
 $client=$module.Types | Where-Object FullName -eq 'Kolkata.QwenTts.QwenWorkerClient'
 $ctor=$client.Methods | Where-Object Name -eq '.ctor'
 $logger=$client.Methods | Where-Object Name -eq 'LocalDiagnosticLog'
 $start=@($ctor.Body.Instructions | Where-Object{$_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.FullName -eq 'System.Diagnostics.Process' -and $_.Operand.Name -eq 'Start'})
 if($start.Count -ne 1){throw 'Unexpected Process.Start count'}
 if($start[0].Previous.OpCode.Code -ne 'Ldloc_0' -or $start[0].Previous.Previous.OpCode.Code -ne 'Ldarg_0'){throw 'Unexpected process-start sequence'}
 $anchor=$start[0].Previous.Previous
 $getter=$module.ImportReference([System.Diagnostics.ProcessStartInfo].GetProperty('EnvironmentVariables').GetGetMethod())
 $setter=$module.ImportReference([System.Collections.Specialized.StringDictionary].GetProperty('Item').GetSetMethod())
 $il=$ctor.Body.GetILProcessor()
 foreach($key in 'DISABLE_VK_LAYER_VALVE_steam_fossilize_1','DISABLE_VK_LAYER_VALVE_steam_overlay_1'){
  $il.InsertBefore($anchor,$il.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_0))
  $il.InsertBefore($anchor,$il.Create([Mono.Cecil.Cil.OpCodes]::Callvirt,$getter))
  $il.InsertBefore($anchor,$il.Create([Mono.Cecil.Cil.OpCodes]::Ldstr,$key))
  $il.InsertBefore($anchor,$il.Create([Mono.Cecil.Cil.OpCodes]::Ldstr,'1'))
  $il.InsertBefore($anchor,$il.Create([Mono.Cecil.Cil.OpCodes]::Callvirt,$setter))
 }
 $remover=$module.ImportReference([System.Collections.Specialized.StringDictionary].GetMethod('Remove',[type[]]@([string])))
 foreach($key in '__GL_SHADER_DISK_CACHE_PATH','__GL_SHADER_DISK_CACHE_APP_NAME','__GL_SHADER_DISK_CACHE_READ_ONLY_APP_NAME','__GL_SHADER_DISK_CACHE_SKIP_CLEANUP'){
  $il.InsertBefore($anchor,$il.Create([Mono.Cecil.Cil.OpCodes]::Ldloc_0))
  $il.InsertBefore($anchor,$il.Create([Mono.Cecil.Cil.OpCodes]::Callvirt,$getter))
  $il.InsertBefore($anchor,$il.Create([Mono.Cecil.Cil.OpCodes]::Ldstr,$key))
  $il.InsertBefore($anchor,$il.Create([Mono.Cecil.Cil.OpCodes]::Callvirt,$remover))
 }
 $il.InsertBefore($anchor,$il.Create([Mono.Cecil.Cil.OpCodes]::Ldstr,'Qwen worker only: use default NVIDIA shader cache; Steam Vulkan layers disabled.'))
 $il.InsertBefore($anchor,$il.Create([Mono.Cecil.Cil.OpCodes]::Call,$logger))
 $module.Write($destination)
}finally{$module.Dispose()}
