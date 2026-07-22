function ConvertTo-HealthEventMessage {
 param([AllowNull()][string]$Message)
 if([string]::IsNullOrWhiteSpace($Message)){return $null}
 $value=$Message -replace '(?i)C:\\Users\\[^\\\s]+','C:\Users\<USER>'
 return ($value -replace '\b\d+\b','<N>')
}
function Group-CriticalEvent {
 param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Events)
 $prepared=@($Events|Where-Object{$null-ne $_}|ForEach-Object{
  [pscustomobject]@{Provider=[string]$_.ProviderName;Id=[int]$_.Id;Level=[string]$_.LevelDisplayName;Time=[datetime]$_.TimeCreated;Message=ConvertTo-HealthEventMessage -Message $_.Message}
 })
 return @($prepared|Group-Object Provider,Id,Message|ForEach-Object{
  $ordered=@($_.Group|Sort-Object Time)
  [pscustomobject][ordered]@{Provider=$ordered[0].Provider;Id=$ordered[0].Id;Level=$ordered[0].Level;Message=$ordered[0].Message;OccurrenceCount=$ordered.Count;FirstSeen=$ordered[0].Time;LastSeen=$ordered[-1].Time}
 })
}
