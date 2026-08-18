BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
    . "$PSScriptRoot/../Modules/Get-SecurityInfo.ps1"
    if (-not (Get-Command Get-Tpm -ErrorAction SilentlyContinue)) {
        function Get-Tpm { param() }
    }
    if (-not (Get-Command Confirm-SecureBootUEFI -ErrorAction SilentlyContinue)) {
        function Confirm-SecureBootUEFI { param() }
    }
    if (-not (Get-Command Get-BitLockerVolume -ErrorAction SilentlyContinue)) {
        function Get-BitLockerVolume { param() }
    }
}

Describe 'Get-SecurityInventory TPM' {
    It 'reports a clear ErrorNote (not just the raw HRESULT) when Get-Tpm fails with a TPM communication error' {
        # Real field report: Get-Tpm throwing "An internal error has occurred
        # within the Trusted Platform Module support program (Exception from
        # HRESULT: 0x80284001)" on older/real hardware — a genuine TPM
        # driver/firmware communication failure, not something hawico can
        # fix, but the report should say so clearly instead of just showing
        # the raw exception text via Write-Warning and leaving TPM blank.
        Mock Get-Tpm { throw 'An internal error has occurred within the Trusted Platform Module support program. (Exception from HRESULT: 0x80284001)' }

        $result = Get-SecurityInventory

        $result.TPM.Available | Should -BeFalse
        $result.TPM.Present | Should -BeNullOrEmpty
        $result.TPM.ErrorNote | Should -Not -BeNullOrEmpty
        $result.TPM.ErrorNote | Should -Match 'hardware TPM'
    }

    It 'leaves ErrorNote empty when Get-Tpm succeeds' {
        Mock Get-Tpm { [PSCustomObject]@{ TpmPresent = $true; TpmReady = $true; TpmEnabled = $true; TpmActivated = $true } }

        $result = Get-SecurityInventory

        $result.TPM.Available | Should -BeTrue
        $result.TPM.Present | Should -BeTrue
        $result.TPM.ErrorNote | Should -BeNullOrEmpty
    }

}
