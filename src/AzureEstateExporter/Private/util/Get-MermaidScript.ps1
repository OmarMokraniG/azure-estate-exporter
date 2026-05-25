function Get-MermaidScript {
    <#
    .SYNOPSIS
        Returns the content of mermaid.min.js so callers can embed it inline
        in self-contained HTML artifacts (no internet needed at view time).
    .DESCRIPTION
        Strategy:
          1. Look in the user-cache for a previously downloaded copy.
          2. If absent, download from jsDelivr to the cache.
          3. On any failure, return $null so the caller can fall back to a
             CDN <script src> tag (online-only) with a warning.

        Cache location:
          * Windows: %LOCALAPPDATA%\azure-estate-exporter\cache
          * Linux/macOS: ~/.cache/azure-estate-exporter
    .OUTPUTS
        [string] mermaid.js content, or $null on failure.
    #>
    [CmdletBinding()]
    param(
        [string]$Version = '10.9.1'
    )

    $cacheRoot = if ($IsWindows -or $env:LOCALAPPDATA) {
        Join-Path $env:LOCALAPPDATA 'azure-estate-exporter\cache'
    } else {
        Join-Path $HOME '.cache/azure-estate-exporter'
    }
    if (-not (Test-Path $cacheRoot)) {
        New-Item -ItemType Directory -Force -Path $cacheRoot | Out-Null
    }

    $cacheFile = Join-Path $cacheRoot ("mermaid-$Version.min.js")
    if (Test-Path $cacheFile) {
        try { return (Get-Content -Raw -Path $cacheFile) }
        catch { Write-Verbose "Could not read cached mermaid.js ($_); will re-download." }
    }

    # jsDelivr provides immutable, pinnable URLs and CORS — best fit for a cache hit.
    $url = "https://cdn.jsdelivr.net/npm/mermaid@$Version/dist/mermaid.min.js"
    try {
        Write-Verbose "Downloading mermaid.js $Version from $url"
        $content = Invoke-WebRequest -UseBasicParsing -Uri $url -ErrorAction Stop |
            Select-Object -ExpandProperty Content
        if ($content) {
            Set-Content -Path $cacheFile -Value $content -Encoding utf8
            return $content
        }
    }
    catch {
        Write-Warning "Could not fetch mermaid.js ($($_.Exception.Message)). HTML dashboard will use the CDN link."
    }
    return $null
}
