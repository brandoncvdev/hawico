function ConvertTo-HealthCheckReport {
 param([Parameter(Mandatory)][object]$BaseInventory,[Parameter(Mandatory)][object]$HealthCheck,[datetimeoffset]$CollectedAt,[long]$DurationMilliseconds,[string]$ScriptUser='<REDACTED>')
 $r=[ordered]@{SchemaVersion='2.0';Collection=[ordered]@{CollectedAt=$CollectedAt.ToString('o');Mode='Diagnostic';Type='WindowsHealthCheck';ScriptUser=$ScriptUser;DurationMilliseconds=$DurationMilliseconds}}
 foreach($name in @('Computer','OperatingSystem','BIOS','Motherboard','Processors','Memory','Storage')){
  $r[$name]=if($BaseInventory.PSObject.Properties.Name -contains $name){$BaseInventory.$name}elseif($BaseInventory -is [System.Collections.IDictionary] -and $BaseInventory.Contains($name)){$BaseInventory[$name]}else{if($name-eq'Processors'){@()}else{@{}}}
 }
 $extension=[ordered]@{ContractVersion='1.1'}
 if($HealthCheck -is [System.Collections.IDictionary]){foreach($key in $HealthCheck.Keys){$extension[$key]=$HealthCheck[$key]}}
 else{foreach($property in $HealthCheck.PSObject.Properties){$extension[$property.Name]=$property.Value}}
 $r.HealthCheck=$extension
 return $r
}
