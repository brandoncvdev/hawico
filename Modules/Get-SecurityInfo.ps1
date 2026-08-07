function Get-SecurityInventory {
    $tpm = [ordered]@{
        Available = $false
        Present = $null
        Ready = $null
        Enabled = $null
        Activated = $null
        ErrorNote = $null
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
                ErrorNote = $null
            }
        } catch {
            # Real field report: Get-Tpm throwing HRESULT 0x80284001 ("An
            # internal error has occurred within the Trusted Platform Module
            # support program") — a genuine TPM driver/firmware communication
            # failure between Windows and the physical chip, not something
            # hawico's code can fix. The raw exception alone (Write-Warning
            # only, console-only, TPM section left blank) wasn't informative
            # in the generated report — this gives the technician a plain
            # explanation plus the raw detail for anyone who needs it.
            Write-Warning ("No se pudo consultar TPM: {0}" -f $_.Exception.Message)
            $tpm.ErrorNote = ("No se pudo comunicar con el hardware TPM (fallo del controlador/firmware del equipo, no de hawico). " +
                "Puede ser transitorio: probar reiniciar el equipo o revisar actualizaciones de BIOS/firmware. Detalle técnico: {0}" -f $_.Exception.Message)
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
