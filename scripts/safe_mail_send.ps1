# Safe email sender (PowerShell) - previews before sending to prevent mangled emails
# PowerShell mirror of safe_mail_send.sh.
# Usage:
#   .\safe_mail_send.ps1 -To "user@example.com" -Subject "Subject" -BodyFile C:\path\body.txt
#   .\safe_mail_send.ps1 -To "..." -Subject "..." -BodyFile ... -Attachment C:\path\file.png -Confirm

# Parse $args manually so both PS style (-To X) and bash style (--to X) work.
$To = ""; $Subject = ""; $BodyFile = ""; $Attachment = ""; $Confirm = $false

$flagMap = @{
    "-to"="To"; "-subject"="Subject"; "-bodyfile"="BodyFile"; "-body-file"="BodyFile"
    "-attachment"="Attachment"
}
$switchMap = @{ "-confirm"="Confirm" }

$i = 0
while ($i -lt $args.Count) {
    $tok = ([string]$args[$i]).ToLower()
    if ($tok -match '^[-/]+(.+)$') { $tok = "-" + $Matches[1] }
    if ($switchMap.ContainsKey($tok)) {
        Set-Variable -Name $switchMap[$tok] -Value $true -Scope Script -Force
        $i++
    } elseif ($flagMap.ContainsKey($tok)) {
        if ($i + 1 -ge $args.Count) { Write-Host "Missing value for $($args[$i])"; exit 1 }
        Set-Variable -Name $flagMap[$tok] -Value ([string]$args[$i + 1]) -Scope Script -Force
        $i += 2
    } else {
        Write-Host "Unknown arg: $($args[$i])"
        Write-Host "Usage: safe_mail_send.ps1 -To EMAIL -Subject SUBJECT -BodyFile PATH [-Attachment FILE] [-Confirm]"
        exit 1
    }
}

$ErrorActionPreference = "Stop"

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
$Api = Join-Path $PSScriptRoot "microsoft_api.py"

if (-not $To -or -not $Subject -or -not $BodyFile) {
    Write-Host "Usage: .\safe_mail_send.ps1 -To EMAIL -Subject SUBJECT -BodyFile PATH [-Attachment FILE] [-Confirm]"
    Write-Host ""
    Write-Host "  -To          Recipient email address"
    Write-Host "  -Subject     Email subject line"
    Write-Host "  -BodyFile    Path to file containing email body"
    Write-Host "  -Attachment  Optional file to attach (max 3MB)"
    Write-Host "  -Confirm     Send after preview (default: preview only)"
    exit 1
}

if (-not (Test-Path $BodyFile)) {
    Write-Host "ERROR: Body file not found: $BodyFile"
    exit 1
}

$Body = Get-Content -Path $BodyFile -Raw

Write-Host "=========================================="
Write-Host "EMAIL PREVIEW"
Write-Host "=========================================="
Write-Host "To:      $To"
Write-Host "Subject: $Subject"
if ($Attachment) {
    if (Test-Path $Attachment) {
        $sz = [math]::Round((Get-Item $Attachment).Length / 1KB, 1)
        Write-Host "Attachment: $(Split-Path -Leaf $Attachment) ($sz KB)"
    } else {
        Write-Host "WARNING: Attachment not found: $Attachment"
    }
}
Write-Host "------------------------------------------"
Write-Host $Body
Write-Host "=========================================="

# Check for common issues
$Issues = 0
# In PowerShell single-quoted regex, $ is literal — flag "$" followed by a digit
if ($Subject -match '\$\d') {
    Write-Host 'WARNING: Subject contains $ followed by a digit (check it survived quoting)'
    $Issues++
}
if ($Body -match '\$\d') {
    Write-Host 'WARNING: Body contains $ followed by a digit (check it survived quoting)'
    $Issues++
}

if ($Attachment -and (Test-Path $Attachment)) {
    $bytes = (Get-Item $Attachment).Length
    if ($bytes -gt 3145728) {
        Write-Host "ERROR: Attachment exceeds 3MB limit ($bytes bytes)"
        $Issues++
    }
}

if ($Issues -gt 0) {
    Write-Host ""
    Write-Host "Found $Issues potential issue(s). Review above warnings before sending."
}

Write-Host ""

if ($Confirm) {
    Write-Host "Sending..."
    $apiArgs = @($Api, "mail", "send", "--to", $To, "--subject", $Subject, "--body", $Body)
    if ($Attachment) { $apiArgs += @("--attachment", $Attachment) }
    & $Py @apiArgs
    exit $LASTEXITCODE
} else {
    Write-Host "To send, re-run with -Confirm:"
    $line = ".\safe_mail_send.ps1 -To `"$To`" -Subject `"$Subject`" -BodyFile `"$BodyFile`""
    if ($Attachment) { $line += " -Attachment `"$Attachment`"" }
    Write-Host "  $line -Confirm"
}
