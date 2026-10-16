# Microsoft Workspace Auth Setup (PowerShell)
# PowerShell mirror of auth.sh for Windows users.
#
# Usage:
#   .\auth.ps1 -ClientId ID -ClientSecret SECRET [-TenantId TENANT]
#   .\auth.ps1 -Check
#   .\auth.ps1 -Config [-Name "Your Name"] [-Agent "AgentName"] [-Timezone "Australia/Sydney"]

# Parse $args manually so both PS style (-ClientId X) and bash style (--client-id X) work.
# (PowerShell's binder rejects '--flag' tokens before ValueFromRemainingArguments can see them.)
$Check = $false; $Config = $false
$ClientId = ""; $ClientSecret = ""; $TenantId = "consumers"
$Name = ""; $Agent = ""; $Timezone = ""

$flagMap = @{
    "-clientid"="ClientId"; "-client-id"="ClientId"
    "-clientsecret"="ClientSecret"; "-client-secret"="ClientSecret"
    "-tenantid"="TenantId"; "-tenant-id"="TenantId"
    "-name"="Name"; "-agent"="Agent"; "-timezone"="Timezone"
}
$switchMap = @{ "-check"="Check"; "-config"="Config" }

$i = 0
while ($i -lt $args.Count) {
    $tok = ([string]$args[$i]).ToLower()
    if ($tok -match '^[-/]+(.+)$') { $tok = "-" + $Matches[1] }   # normalize --x, /x, -x to -x
    if ($switchMap.ContainsKey($tok)) {
        Set-Variable -Name $switchMap[$tok] -Value $true -Scope Script -Force
        $i++
    } elseif ($flagMap.ContainsKey($tok)) {
        if ($i + 1 -ge $args.Count) { Write-Host "Missing value for $($args[$i])"; exit 1 }
        Set-Variable -Name $flagMap[$tok] -Value ([string]$args[$i + 1]) -Scope Script -Force
        $i += 2
    } else {
        Write-Host "Unknown arg: $($args[$i])"
        Write-Host "Usage: auth.ps1 [-ClientId ID -ClientSecret SECRET [-TenantId T]] | [-Check] | [-Config [-Name N] [-Agent A] [-Timezone TZ]]"
        exit 1
    }
}

$ErrorActionPreference = "Stop"

# Resolve Hermes home (same rule as auth.sh / microsoft_api.py)
$HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME }
              elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA "hermes" }
              else { Join-Path $HOME ".hermes" }
$SecretFile = Join-Path $HermesHome "microsoft_client_secret.json"
$ConfigFile = Join-Path $HermesHome "microsoft_config.json"
$TokenFile  = Join-Path $HermesHome "microsoft_token.json"
if (-not (Test-Path $HermesHome)) { New-Item -ItemType Directory -Path $HermesHome -Force | Out-Null }

# Resolve a working Python interpreter (python3 is a Store stub on Windows)
function Resolve-Python {
    foreach ($c in @("python", "py", "python3")) {
        if (Get-Command $c -ErrorAction SilentlyContinue) {
            & $c -c "import sys" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { return $c }
        }
    }
    return "python"
}
$Py = Resolve-Python

if ($Check) {
    Write-Host "=== Microsoft Workspace Auth Check ===`n"

    if (Test-Path $SecretFile) {
        Write-Host "Credentials: $SecretFile"
        try {
            $cid = (Get-Content $SecretFile -Raw | ConvertFrom-Json).client_id
            Write-Host ("  Client ID: {0}..." -f $cid.Substring(0, [Math]::Min(8, $cid.Length)))
        } catch { Write-Host "  ERROR reading file" }
    } else {
        Write-Host "Credentials: NOT FOUND"
        Write-Host "  Run: .\auth.ps1 -ClientId YOUR_ID -ClientSecret YOUR_SECRET"
    }

    Write-Host ""

    if (Test-Path $TokenFile) {
        Write-Host "Token: $TokenFile"
        try {
            $tok = Get-Content $TokenFile -Raw | ConvertFrom-Json
            $exp = [double]$tok.expires_at
            if ($exp -gt [DateTimeOffset]::Now.ToUnixTimeSeconds()) {
                $mins = [int](($exp - [DateTimeOffset]::Now.ToUnixTimeSeconds()) / 60)
                Write-Host "  Status: Valid (expires in $mins min)"
            } else {
                Write-Host "  Status: EXPIRED"
            }
        } catch { Write-Host "  Status: ERROR reading token" }
    } else {
        Write-Host "Token: NOT FOUND"
        Write-Host "  Run: $Py setup.py --auth-url"
    }

    Write-Host ""

    if (Test-Path $ConfigFile) {
        Write-Host "Config: $ConfigFile"
        (Get-Content $ConfigFile -Raw | ConvertFrom-Json).PSObject.Properties |
            ForEach-Object { Write-Host "  $($_.Name): $($_.Value)" }
    } else {
        Write-Host "Config: NOT SET (optional)"
        Write-Host "  Run: .\auth.ps1 -Config -Name 'Your Name' -Agent 'AgentName'"
    }

    Write-Host "`nQuick test:"
    & $Py (Join-Path $PSScriptRoot "microsoft_api.py") mail list --max 1 2>&1 | Select-Object -First 3
    exit 0
}

if ($Config) {
    if (-not $Name -and -not $Agent -and -not $Timezone) {
        Write-Host "Current config:"
        if (Test-Path $ConfigFile) { Get-Content $ConfigFile -Raw } else { Write-Host "  (none set)" }
        Write-Host "`nSet with: .\auth.ps1 -Config -Name 'Your Name' -Agent 'AgentName' [-Timezone 'Australia/Sydney']"
        exit 0
    }

    $cfg = if (Test-Path $ConfigFile) {
        Get-Content $ConfigFile -Raw | ConvertFrom-Json
    } else { [pscustomobject]@{} }

    if ($Name)     { $cfg | Add-Member -Force NoteProperty sender_name $Name }
    if ($Agent)    { $cfg | Add-Member -Force NoteProperty agent_name $Agent }
    if ($Timezone) { $cfg | Add-Member -Force NoteProperty timezone $Timezone }

    $cfg | ConvertTo-Json -Depth 5 | Set-Content -Path $ConfigFile -Encoding UTF8
    Write-Host "Config saved to $ConfigFile"
    Get-Content $ConfigFile -Raw
    exit 0
}

# Setup credentials
if (-not $ClientId -or -not $ClientSecret) {
    Write-Host "ERROR: -ClientId and -ClientSecret are required"
    Write-Host ""
    Write-Host "Usage: .\auth.ps1 -ClientId YOUR_ID -ClientSecret YOUR_SECRET [-TenantId YOUR_TENANT]"
    Write-Host ""
    Write-Host "To get these values, see README.md for Azure App Registration setup."
    exit 1
}

Write-Host "=== Saving Microsoft credentials ==="
@{ client_id = $ClientId; client_secret = $ClientSecret; tenant_id = $TenantId } |
    ConvertTo-Json -Depth 5 | Set-Content -Path $SecretFile -Encoding UTF8
Write-Host "Saved to: $SecretFile"

Write-Host ""
Write-Host "Credentials saved. Next step: authorize your account."
Write-Host ""
Write-Host "Run these commands:"
Write-Host ""
Write-Host "  1. Get auth URL:"
Write-Host "     $Py `"$PSScriptRoot\setup.py`" --auth-url"
Write-Host ""
Write-Host "  2. Open the URL in your browser, sign in, and copy the redirect URL"
Write-Host ""
Write-Host "  3. Paste the redirect URL:"
Write-Host "     $Py `"$PSScriptRoot\setup.py`" --auth-code 'PASTE_URL_HERE'"
Write-Host ""
Write-Host "  4. (Optional) Set display name / timezone:"
Write-Host "     .\auth.ps1 -Config -Name 'Your Name' -Agent 'AgentName' -Timezone 'Australia/Sydney'"
