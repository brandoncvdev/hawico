Describe 'Start-Inventory storage-diagnostic integration' {
 BeforeAll { $script=Get-Content "$PSScriptRoot/../Start-Inventory.ps1" -Raw }
 It 'references the storage diagnostic collector' { $script|Should -Match 'Collector_Storage_Diagnostic\.ps1' }
 It 'offers a storage diagnostic menu action under option 10' {
  $script|Should -Match '10\.\s*Ejecutar diagnóstico de almacenamiento'
  $script|Should -Match '"10"\s*\{'
 }
 It 'dispatches the storage collector with -Mode Diagnostic from the "10" case, same pattern as option 3' {
  $tenIndex = $script.IndexOf('"10" {')
  $tenIndex | Should -BeGreaterThan -1
  $eightIndex = $script.IndexOf('"8" {')
  $eightIndex | Should -BeGreaterThan -1
  # "10" case must come after "9" (last existing option) so 8/9 stay undisturbed.
  $nineIndex = $script.IndexOf('"9" {')
  $nineIndex | Should -BeGreaterThan -1
  $tenIndex | Should -BeGreaterThan $nineIndex
  $tenBlock = $script.Substring($tenIndex)
  $tenBlock | Should -Match '\$storageCollector\s+-Mode\s+Diagnostic'
 }
 It 'prints the storage diagnostic result and waits for keyboard input before returning to the menu' {
  $tenIndex = $script.IndexOf('"10" {')
  $tenBlock = $script.Substring($tenIndex)
  $tenBlock | Should -Match 'Wait-MenuInput'
 }
 It 'does not disturb option 8 (Salir) or option 9 (Cambiar contexto)' {
  $script|Should -Match '"8"\s*\{'
  $script|Should -Match '"9"\s*\{'
  $script|Should -Match 'Cerrando el recolector'
  $script|Should -Match 'Cambiar contexto de esta visita'
 }
}
