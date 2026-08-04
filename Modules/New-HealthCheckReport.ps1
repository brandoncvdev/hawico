function ConvertTo-HealthCheckReport {
 param([Parameter(Mandatory)][object]$BaseInventory,[Parameter(Mandatory)][object]$HealthCheck,[datetimeoffset]$CollectedAt,[long]$DurationMilliseconds,[string]$ScriptUser='<REDACTED>')
 $r=[ordered]@{SchemaVersion='2.0';Collection=[ordered]@{CollectedAt=$CollectedAt.ToString('o');Mode='Diagnostic';Type='WindowsHealthCheck';ScriptUser=$ScriptUser;DurationMilliseconds=$DurationMilliseconds}}
 foreach($name in @('Computer','OperatingSystem','BIOS','Motherboard','Processors','Memory','Storage')){
  # Every branch here is comma-guarded: `$r[$name] = if (...) {...} else {...}`
  # routes each branch's trailing value through the same output-stream
  # boundary a `return` does, so an array value (Processors, usually exactly
  # one element) collapses to a bare scalar unless guarded. The comma is
  # safe for the non-array branches (Computer/OperatingSystem/etc., which
  # hold a single dictionary) too — it always yields the wrapped value back
  # unchanged, verified empirically before applying this fix.
  $r[$name]=if($BaseInventory.PSObject.Properties.Name -contains $name){,$BaseInventory.$name}elseif($BaseInventory -is [System.Collections.IDictionary] -and $BaseInventory.Contains($name)){,$BaseInventory[$name]}else{if($name-eq'Processors'){,@()}else{,@{}}}
 }
 $extension=[ordered]@{ContractVersion='1.2';ExtendedDiagnostics=[ordered]@{ContractVersion='1.0'}}
 if($HealthCheck -is [System.Collections.IDictionary]){foreach($key in $HealthCheck.Keys){$extension[$key]=$HealthCheck[$key]}}
 else{foreach($property in $HealthCheck.PSObject.Properties){$extension[$property.Name]=$property.Value}}
 $r.HealthCheck=$extension
 return $r
}
