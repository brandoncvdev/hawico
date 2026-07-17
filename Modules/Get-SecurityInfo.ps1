function Get-SecurityInventory {
    $tpm = [ordered]@{
        Available = $false
        Present = $null
        Ready = $null
        Enabled = $null
        Activated = $null
    }

    if (Get-Command -Name Get-Tpm -ErrorAction SilentlyContinue) {
        try {
            $t = Get-Tpm -ErrorAction Stop
            $tpm = [ordered]@{
                Available = $true
                Present = $t.TpmPresent
                Ready = $t.TpmReady
                Enabled = $t.TpmEnabled
                Activated = $t.TpmActivated
            }
        } catch {
            Write-Warning ("No se pudo consultar TPM: {0}" -f $_.Exception.Message)
        }
    }

    $secureBoot = [ordered]@{ Supported = $null; Enabled = $null }
    if (Get-Command -Name Confirm-SecureBootUEFI -ErrorAction SilentlyContinue) {
        try {
            $secureBoot = [ordered]@{
                Supported = $true
                Enabled = [bool](Confirm-SecureBootUEFI -ErrorAction Stop)
            }
        } catch {
            $secureBoot = [ordered]@{ Supported = $false; Enabled = $null }
        }
    }

    $bitLocker = @()
    if (Get-Command -Name Get-BitLockerVolume -ErrorAction SilentlyContinue) {
        try {
            $bitLocker = @(
                Get-BitLockerVolume -ErrorAction Stop | ForEach-Object {
                    [ordered]@{
                        MountPoint = Get-SafeString $_.MountPoint
                        VolumeStatus = Get-SafeString $_.VolumeStatus
                        ProtectionStatus = Get-SafeString $_.ProtectionStatus
                        EncryptionPercentage = $_.EncryptionPercentage
                        EncryptionMethod = Get-SafeString $_.EncryptionMethod
                    }
                }
            )
        } catch {
            Write-Warning ("No se pudo consultar BitLocker: {0}" -f $_.Exception.Message)
        }
    }

    return [ordered]@{
        TPM = $tpm
        SecureBoot = $secureBoot
        BitLocker = $bitLocker
    }
}
