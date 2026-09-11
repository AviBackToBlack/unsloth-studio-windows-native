@{
    Severity = @('Error', 'Warning')

    # These are interactive operator scripts. Colored/status-oriented host
    # output in doctor/update/start/model-sync is intentional UX, not library
    # output. Keep every other PSScriptAnalyzer warning blocking.
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
    )
}
