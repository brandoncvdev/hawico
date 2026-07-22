function ConvertTo-HealthEventMessage {
 param([AllowNull()][string]$Message)
 if([string]::IsNullOrWhiteSpace($Message)){return $null}
 $value=$Message -replace '(?i)C:\\Users\\[^\\\s]+','C:\Users\<USER>'
 $value=$value -replace '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b','<EMAIL>'
 $value=$value -replace '(?i)\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b','<GUID>'
 $value=$value -replace '\b(?:\d{1,3}\.){3}\d{1,3}\b','<IP>'
 $value=($value -replace '\b\d+\b','<N>') -replace '\s+',' '
 if($value.Length-gt 240){$value=$value.Substring(0,237)+'...'}
 return $value
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
function Get-CriticalEvent {
 param([ValidateRange(1,30)][int]$LookbackDays=7)
 return @((Get-CriticalEventResult -LookbackDays $LookbackDays).Events)
}

function Get-CriticalEventResult {
 param([ValidateRange(1,30)][int]$LookbackDays=7)
 $startedAt=[datetimeoffset]::Now
 $timer=[System.Diagnostics.Stopwatch]::StartNew()
 $definitions=@(
  [pscustomobject]@{Provider='Disk';LogName='System'},
  [pscustomobject]@{Provider='Ntfs';LogName='System'},
  [pscustomobject]@{Provider='StorPort';LogName='System'},
  [pscustomobject]@{Provider='stornvme';LogName='System'},
  [pscustomobject]@{Provider='WHEA-Logger';LogName='System'},
  [pscustomobject]@{Provider='Kernel-Power';LogName='System'},
  [pscustomobject]@{Provider='Application Error';LogName='Application'},
  [pscustomobject]@{Provider='Application Hang';LogName='Application'}
 )
 $raw=@()
 $errors=@()
 foreach($definition in $definitions){
  try{
   $raw+=@(Get-WinEvent -FilterHashtable @{LogName=$definition.LogName;ProviderName=$definition.Provider;StartTime=(Get-Date).AddDays(-$LookbackDays)} -ErrorAction Stop)
  }
  catch{
   $errors+=[pscustomobject][ordered]@{Provider=$definition.Provider;LogName=$definition.LogName;Code='EVENT-PROVIDER-FAILED';Message='The event provider could not be queried.'}
  }
 }
 $timer.Stop()
 $status=if($errors.Count-eq 0){'Collected'}elseif($errors.Count-lt $definitions.Count){'Partial'}else{'Failed'}
 return [ordered]@{
  Status=$status
  StartedAt=$startedAt
  DurationMilliseconds=$timer.ElapsedMilliseconds
  ErrorCode=if($status-eq'Failed'){'EVENT-QUERY-FAILED'}elseif($status-eq'Partial'){'EVENT-QUERY-PARTIAL'}else{$null}
  ErrorMessage=if($status-eq'Failed'){'No configured event provider could be queried.'}elseif($status-eq'Partial'){'One or more configured event providers could not be queried.'}else{$null}
  Events=@(Group-CriticalEvent -Events $raw)
  Errors=$errors
 }
}
