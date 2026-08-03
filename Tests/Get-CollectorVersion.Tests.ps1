BeforeAll {
    . "$PSScriptRoot/../Modules/Common.ps1"
}

Describe 'Get-CollectorVersion' {
    BeforeEach {
        $script:tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:tempDir -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'reads CollectorVersion from manifest.json under the given base path' {
        Set-Content -LiteralPath (Join-Path $script:tempDir 'manifest.json') `
            -Value '{"CollectorVersion":"1.2.3"}' -Encoding UTF8

        Get-CollectorVersion -BasePath $script:tempDir | Should -Be '1.2.3'
    }

    It 'falls back to the default version when manifest.json is missing' {
        Get-CollectorVersion -BasePath $script:tempDir -DefaultVersion '0.0.0-missing' | Should -Be '0.0.0-missing'
    }

    It 'falls back to the default version when manifest.json is malformed' {
        Set-Content -LiteralPath (Join-Path $script:tempDir 'manifest.json') -Value '{not valid json' -Encoding UTF8

        Get-CollectorVersion -BasePath $script:tempDir -DefaultVersion '0.0.0-malformed' -WarningAction SilentlyContinue |
            Should -Be '0.0.0-malformed'
    }

    It 'falls back to the default version when CollectorVersion is blank' {
        Set-Content -LiteralPath (Join-Path $script:tempDir 'manifest.json') `
            -Value '{"CollectorVersion":"  "}' -Encoding UTF8

        Get-CollectorVersion -BasePath $script:tempDir -DefaultVersion '0.0.0-blank' | Should -Be '0.0.0-blank'
    }

    It 'reads the repository manifest.json used by the collector' {
        $repoRoot = Resolve-Path "$PSScriptRoot/.."
        Get-CollectorVersion -BasePath $repoRoot | Should -Be '0.5.0'
    }
}
