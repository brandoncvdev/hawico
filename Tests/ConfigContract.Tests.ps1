Describe 'config.json HealthCheck contract' {
 It 'contains the documented validated defaults' {
  $c=Get-Content "$PSScriptRoot/../config.json" -Raw|ConvertFrom-Json
  $c.HealthCheck.SampleDurationSeconds|Should -Be 60
  $c.HealthCheck.SampleIntervalSeconds|Should -Be 1
  $c.HealthCheck.EventLookbackDays|Should -Be 7
  $c.HealthCheck.MinimumFreeDiskPercent|Should -Be 20
  $c.HealthCheck.CriticalFreeDiskPercent|Should -Be 10
  $c.HealthCheck.MemoryWarningPercent|Should -Be 70
  $c.HealthCheck.MemoryHighPercent|Should -Be 85
  $c.HealthCheck.MemoryCriticalPercent|Should -Be 95
 $c.HealthCheck.TopProcessCount|Should -Be 10
 }
}

Describe 'config.json CollectionSession contract' {
 It 'contains backward-compatible collection context defaults' {
  $c=Get-Content "$PSScriptRoot/../config.json" -Raw|ConvertFrom-Json
  $c.CollectionSession.SessionId|Should -Be 'SES-UNASSIGNED'
  $c.CollectionSession.ProfileId|Should -Be 'basic-inventory'
  $c.CollectionSession.OrganizationId|Should -BeNullOrEmpty
  $c.CollectionSession.Technician|Should -BeNullOrEmpty
 }
}

Describe 'config.json ManualFields contract' {
 It 'contains the five basic-inventory manual fields in institutional order' {
  $c=Get-Content "$PSScriptRoot/../config.json" -Raw|ConvertFrom-Json
  $c.ManualFields.Count|Should -Be 5
  $c.ManualFields[0]|Should -Be 'assignment.user.fullName'
  $c.ManualFields[1]|Should -Be 'assignment.organizationUnitId'
  $c.ManualFields[2]|Should -Be 'assignment.locationId'
  $c.ManualFields[3]|Should -Be 'asset.assetTag'
  $c.ManualFields[4]|Should -Be 'collection.observations'
 }
}

Describe 'config.json Consolidation contract' {
 It 'contains the default paths used to build the consolidated workbook' {
  $c=Get-Content "$PSScriptRoot/../config.json" -Raw|ConvertFrom-Json
  $c.Consolidation.RecordsPath|Should -Be '.\Output'
  $c.Consolidation.OutputPath|Should -Be '.\Output\Consolidado.xlsx'
  $c.Consolidation.HistoryDirectory|Should -Be '.\Output\Historico'
 }
}

Describe 'config.json Administration contract' {
 It 'contains the default paths used to import records into the local asset store' {
  $c=Get-Content "$PSScriptRoot/../config.json" -Raw|ConvertFrom-Json
  $c.Administration.RecordsPath|Should -Be '.\Output'
  $c.Administration.BasePath|Should -Be '.'
 }
}

Describe 'config.json OrganizationPackages contract' {
 It 'contains the default base path used to resolve organization packages' {
  $c=Get-Content "$PSScriptRoot/../config.json" -Raw|ConvertFrom-Json
  $c.OrganizationPackages.BasePath|Should -Be '.\Config\Organizations'
 }
}
