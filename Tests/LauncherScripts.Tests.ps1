Describe 'Bootstrap.ps1 catch block keeps the window open on error' {
    BeforeAll {
        $script = Get-Content "$PSScriptRoot/../Bootstrap.ps1" -Raw
    }

    It 'blocks the window with Read-Host inside the catch block, not just claims it will stay open' {
        $catchIndex = $script.IndexOf('catch {')
        $catchIndex | Should -BeGreaterThan -1

        # Bootstrap.ps1 has a single catch block and nothing after it, so
        # everything from "catch {" to end-of-file IS the catch block —
        # this confirms Read-Host is inside it, not merely present
        # somewhere unrelated in the file.
        $catchBlock = $script.Substring($catchIndex)
        $catchBlock | Should -Match 'Read-Host'
        $catchBlock | Should -Match 'permanecerá abierta'
    }
}

Describe 'Iniciar-Recolector.cmd' {
    BeforeAll {
        $script = Get-Content "$PSScriptRoot/../Iniciar-Recolector.cmd" -Raw
    }

    It 'launches Bootstrap.ps1 with Bypass execution policy and a drive-independent relative path' {
        $script | Should -Match 'Bootstrap\.ps1'
        $script | Should -Match '-ExecutionPolicy\s+Bypass'
        $script | Should -Match '%~dp0'
        $script | Should -Not -Match '-NoExit'
    }

    It 'pauses on a launch failure as an extra safety net' {
        $script | Should -Match 'if\s+errorlevel\s+1\s+pause'
    }
}

Describe 'Iniciar-Administracion.cmd' {
    BeforeAll {
        $script = Get-Content "$PSScriptRoot/../Iniciar-Administracion.cmd" -Raw
    }

    It 'launches Start-Administration.ps1 with Bypass execution policy and a drive-independent relative path' {
        $script | Should -Match 'Start-Administration\.ps1'
        $script | Should -Match '-ExecutionPolicy\s+Bypass'
        $script | Should -Match '%~dp0'
        $script | Should -Not -Match '-NoExit'
    }

    It 'pauses on a launch failure as an extra safety net' {
        $script | Should -Match 'if\s+errorlevel\s+1\s+pause'
    }
}
