$script:SensitiveKeyPattern = '(?i)(password|secret|connectionstring|clientsecret|key|sas|token|certificate|cert|pwd|apikey)'

function Protect-SensitiveValue {
    <#
    .SYNOPSIS
        Recursively redacts values whose JSON key matches a sensitive pattern.
    .DESCRIPTION
        Walks any PSCustomObject / Hashtable / IDictionary / IEnumerable tree
        and replaces values whose key matches the sensitive pattern with the
        literal string '***REDACTED***'. The input is cloned (via JSON
        round-trip) so the caller's object is not mutated.

        Used by every renderer before writing artifacts to disk. Disabled
        only when the orchestrator was called with -NoRedact.
    .PARAMETER InputObject
        Any object — typically the normalized inventory or graph model.
    .PARAMETER NoRedact
        When set, returns the input unchanged. Provided so callers can
        thread the user's -NoRedact intent without conditional logic.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        [object]$InputObject,

        [switch]$NoRedact
    )

    process {
        if ($NoRedact -or $null -eq $InputObject) { return $InputObject }

        # Clone via JSON to avoid mutating caller's objects and to normalise types.
        $json   = $InputObject | ConvertTo-Json -Depth 32 -Compress
        $cloned = $json | ConvertFrom-Json -Depth 32

        return (Invoke-Redaction -Node $cloned)
    }
}

function Invoke-Redaction {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Node
    )

    if ($null -eq $Node) { return $null }

    if ($Node -is [string] -or $Node -is [bool] -or $Node -is [int] -or $Node -is [long] -or $Node -is [double] -or $Node -is [decimal]) {
        return $Node
    }

    if ($Node -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($k in $Node.Keys) {
            if ($k -match $script:SensitiveKeyPattern) {
                $copy[$k] = '***REDACTED***'
            }
            else {
                $copy[$k] = Invoke-Redaction -Node $Node[$k]
            }
        }
        return [pscustomobject]$copy
    }

    if ($Node -is [pscustomobject]) {
        $copy = [ordered]@{}
        foreach ($p in $Node.PSObject.Properties) {
            if ($p.Name -match $script:SensitiveKeyPattern) {
                $copy[$p.Name] = '***REDACTED***'
            }
            else {
                $copy[$p.Name] = Invoke-Redaction -Node $p.Value
            }
        }
        return [pscustomobject]$copy
    }

    if ($Node -is [System.Collections.IEnumerable]) {
        $items = @()
        foreach ($item in $Node) { $items += , (Invoke-Redaction -Node $item) }
        return $items
    }

    return $Node
}
