param(
 [Parameter(Mandatory=$true)][string]$Source,
 [Parameter(Mandatory=$true)][string]$Destination,
 [Parameter(Mandatory=$true)][string]$CecilPath,
 [Parameter(Mandatory=$true)][string]$ManagedDirectory
)
$ErrorActionPreference='Stop'
if((Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash -ne '53BD673F796EA21F8B1512C3F113E6BB1997CE62665AB3EF2C1A72B4BED490EC'){throw 'Unsupported original DLL'}
if(Test-Path -LiteralPath $Destination){throw 'Output already exists'}
Add-Type -Path $CecilPath
$resolver=[Mono.Cecil.DefaultAssemblyResolver]::new()
$resolver.AddSearchDirectory($ManagedDirectory)
$readerParameters=[Mono.Cecil.ReaderParameters]::new()
$readerParameters.AssemblyResolver=$resolver
$module = [Mono.Cecil.ModuleDefinition]::ReadModule($source,$readerParameters)
try {
 $client = $module.Types | Where-Object FullName -eq 'Kolkata.QwenTts.QwenWorkerClient'
 if (-not $client) { throw 'Qwen client not found.' }
 if ($client.Methods.Name -contains 'LocalDiagnosticLog') { throw 'Source is already instrumented.' }
 $debug = @($module.GetMemberReferences() | Where-Object { $_ -is [Mono.Cecil.MethodReference] -and $_.DeclaringType.FullName -eq 'UnityEngine.Debug' -and $_.Name -eq 'Log' -and $_.Parameters.Count -eq 1 -and $_.Parameters[0].ParameterType.FullName -eq 'System.Object' })[0]
 if (-not $debug) { throw 'Debug.Log reference not found.' }
 $dateGetter = $module.ImportReference([DateTime].GetProperty('UtcNow').GetGetMethod())
 $dateType = $module.ImportReference([DateTime])
 $format = $module.ImportReference([string].GetMethod('Format',[type[]]@([string],[object],[object])))
 $concat = $module.ImportReference([string].GetMethod('Concat',[type[]]@([string],[string])))
 $eventGetter = $module.ImportReference([System.Diagnostics.DataReceivedEventArgs].GetProperty('Data').GetGetMethod())
 $attrs = [Mono.Cecil.MethodAttributes]145
 $logger = [Mono.Cecil.MethodDefinition]::new('LocalDiagnosticLog',$attrs,$module.TypeSystem.Void)
 $logger.Parameters.Add([Mono.Cecil.ParameterDefinition]::new('message',[Mono.Cecil.ParameterAttributes]::None,$module.TypeSystem.String))
 $client.Methods.Add($logger)
 $il = $logger.Body.GetILProcessor()
 $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldstr,'[QwenDiag {0:O}] {1}'))
 $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call,$dateGetter))
 $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Box,$dateType))
 $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_0))
 $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call,$format))
 $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Call,$debug))
 $il.Append($il.Create([Mono.Cecil.Cil.OpCodes]::Ret))
 function Insert-Message($method,$anchor,[string]$message) {
  $processor = $method.Body.GetILProcessor()
  $processor.InsertBefore($anchor,$processor.Create([Mono.Cecil.Cil.OpCodes]::Ldstr,$message))
  $processor.InsertBefore($anchor,$processor.Create([Mono.Cecil.Cil.OpCodes]::Call,$logger))
 }
 $closure = $client.NestedTypes | Where-Object Name -eq '<>c'
 $handler = $closure.Methods | Where-Object Name -eq '<.ctor>b__10_0'
 if (-not $handler -or $handler.Body.Instructions.Count -ne 1 -or $handler.Body.Instructions[0].OpCode.Code -ne 'Ret') { throw 'Unexpected original stderr handler.' }
 $il = $handler.Body.GetILProcessor()
 $ret = $handler.Body.Instructions[0]
 $il.InsertBefore($ret,$il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_2))
 $il.InsertBefore($ret,$il.Create([Mono.Cecil.Cil.OpCodes]::Callvirt,$eventGetter))
 $il.InsertBefore($ret,$il.Create([Mono.Cecil.Cil.OpCodes]::Call,$logger))
 $load = $client.Methods | Where-Object Name -eq 'Load'
 $il = $load.Body.GetILProcessor()
 $first = $load.Body.Instructions[0]
 $il.InsertBefore($first,$il.Create([Mono.Cecil.Cil.OpCodes]::Ldstr,'Load requested; backend='))
 $il.InsertBefore($first,$il.Create([Mono.Cecil.Cil.OpCodes]::Ldarg_3))
 $il.InsertBefore($first,$il.Create([Mono.Cecil.Cil.OpCodes]::Call,$concat))
 $il.InsertBefore($first,$il.Create([Mono.Cecil.Cil.OpCodes]::Call,$logger))
 $flush = @($load.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.FullName -eq 'System.IO.BinaryWriter' -and $_.Operand.Name -eq 'Flush' })
 if ($flush.Count -ne 1) { throw 'Unexpected Load flush count.' }
 Insert-Message $load $flush[0].Next 'Load request written to worker.'
 $synthesis = $client.Methods | Where-Object Name -eq 'Synthesize'
 Insert-Message $synthesis $synthesis.Body.Instructions[0] 'Synthesis begins; writing reference and prompt.'
 $flush = @($synthesis.Body.Instructions | Where-Object { $_.Operand -is [Mono.Cecil.MethodReference] -and $_.Operand.DeclaringType.FullName -eq 'System.IO.BinaryWriter' -and $_.Operand.Name -eq 'Flush' })
 if ($flush.Count -ne 1) { throw 'Unexpected Synthesize flush count.' }
 Insert-Message $synthesis $flush[0].Next 'Synthesis request written; waiting for audio.'
 $module.Write($destination)
} finally { $module.Dispose() }
