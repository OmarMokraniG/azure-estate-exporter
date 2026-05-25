function Write-EstateLog {
    <#
    .SYNOPSIS
        Structured, level-aware logger used across the module.
    .DESCRIPTION
        Writes to the host with a level prefix and ISO-8601 timestamp. Honours
        $VerbosePreference and $InformationPreference so callers can shape the
        chattiness with normal PowerShell parameters (-Verbose, -InformationAction).
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSAvoidUsingWriteHost', '',
        Justification = 'Coloured progress output is intentional for an interactive CLI tool.')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [ValidateSet('Info', 'Verbose', 'Warn', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    $ts = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss')
    $tag = switch ($Level) {
        'Info'    { '·' }
        'Verbose' { '»' }
        'Warn'    { '!' }
        'Error'   { 'x' }
        'Success' { '✓' }
    }
    $color = switch ($Level) {
        'Warn'    { 'Yellow' }
        'Error'   { 'Red' }
        'Success' { 'Green' }
        'Verbose' { 'DarkGray' }
        default   { 'Cyan' }
    }

    $line = "[$ts] $tag $Message"
    switch ($Level) {
        'Verbose' { Write-Verbose $line }
        'Warn'    { Write-Warning $Message }
        'Error'   { Write-Host $line -ForegroundColor $color }
        default   { Write-Host $line -ForegroundColor $color }
    }
}
