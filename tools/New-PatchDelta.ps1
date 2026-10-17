param(
 [Parameter(Mandatory=$true)][string]$OriginalDll,
 [Parameter(Mandatory=$true)][string]$PatchedDll,
 [Parameter(Mandatory=$true)][string]$Output
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Output already exists'}
if((Get-FileHash -LiteralPath $OriginalDll -Algorithm SHA256).Hash -ne '99791CF93EC829D4784EE514AB78EBA19E5E4A7EA841B291D979432A5C911D8F'){throw 'Unsupported original DLL'}
if((Get-FileHash -LiteralPath $PatchedDll -Algorithm SHA256).Hash -ne '49CF032B165A0775EFC1B093BC137C82A3E3DF3D899755BA360103E3D48F8A83'){throw 'Unexpected patched DLL'}
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
public static class VoiceFixDeltaWriter {
 public static void Write(string original, string patched, string output) {
  byte[] a=File.ReadAllBytes(original), b=File.ReadAllBytes(patched);
  using(var w=new BinaryWriter(new FileStream(output,FileMode.CreateNew))) {
   w.Write(Encoding.ASCII.GetBytes("QWENFIX1")); w.Write(b.Length);
   int i=0;
   while(i<b.Length) {
    if(b[i]==(i<a.Length?a[i]:(byte)0)){i++;continue;}
    int start=i++, end=i;
    // A range header costs eight bytes; include shorter unchanged gaps.
    while(i<b.Length) {
     if(b[i]!=(i<a.Length?a[i]:(byte)0)){end=++i;continue;}
     if(i-end>=8)break;
     i++;
    }
    w.Write(start); w.Write(end-start); w.Write(b,start,end-start);
   }
   w.Write(-1);
  }
 }
}
'@
[VoiceFixDeltaWriter]::Write($OriginalDll,$PatchedDll,$Output)
Get-FileHash -LiteralPath $Output -Algorithm SHA256
