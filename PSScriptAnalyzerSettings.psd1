@{
    # The interactive launchers deliberately render menus directly in the host.
    ExcludeRules = @('PSAvoidUsingWriteHost')

    Rules = @{
        PSUseCompatibleSyntax = @{
            Enable = $true
            TargetVersions = @('5.1')
        }
    }
}
