# Report a successful deployment to Roko. Reporting is best-effort unless
# --strict is supplied or ROKO_STRICT=1 is set.

$strictMode = $env:ROKO_STRICT -eq '1'
if ($args -contains '--strict') {
    $strictMode = $true
}

function Write-AdapterLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Output "roko-adapter: $Message"
}

function Exit-Adapter {
    param([Parameter(Mandatory = $true)][int]$Code)
    if ($script:strictMode) {
        exit $Code
    }
    exit 0
}

if ($args.Count -eq 0 -or $args[0] -ne 'deploy') {
    Write-AdapterLog 'expected command deploy'
    Exit-Adapter 2
}

$values = @{
    url = $env:ROKO_ENDPOINT_URL
    token = $env:ROKO_DEPLOY_TOKEN
    environment = $env:ROKO_ENVIRONMENT
    sha = $env:ROKO_SHA
    deployId = $env:ROKO_DEPLOY_ID
}

$index = 1
while ($index -lt $args.Count) {
    $option = $args[$index]
    if ($option -eq '--strict') {
        $strictMode = $true
        $index += 1
        continue
    }

    $key = switch ($option) {
        '--url' { 'url' }
        '--token' { 'token' }
        '--environment' { 'environment' }
        '--sha' { 'sha' }
        '--deploy-id' { 'deployId' }
        default { $null }
    }

    if ($null -eq $key) {
        Write-AdapterLog "unknown option $option"
        Exit-Adapter 2
    }
    if ($index + 1 -ge $args.Count) {
        Write-AdapterLog "missing value for $option"
        Exit-Adapter 2
    }

    $values[$key] = $args[$index + 1]
    $index += 2
}

foreach ($requiredName in @('url', 'token', 'environment')) {
    if ([string]::IsNullOrWhiteSpace([string]$values[$requiredName])) {
        Write-AdapterLog "missing $requiredName"
        Exit-Adapter 2
    }
}

if ([string]::IsNullOrWhiteSpace([string]$values.sha)) {
    try {
        $values.sha = (& git rev-parse HEAD 2>$null).Trim()
    }
    catch {
        $values.sha = $null
    }
}
if ([string]::IsNullOrWhiteSpace([string]$values.sha)) {
    Write-AdapterLog 'missing sha'
    Exit-Adapter 2
}

$body = [ordered]@{
    environment = [string]$values.environment
    sha = [string]$values.sha
}
if (-not [string]::IsNullOrEmpty([string]$values.deployId)) {
    $body.deployId = [string]$values.deployId
}
$json = $body | ConvertTo-Json -Compress

$attempt = 1
while ($attempt -le 3) {
    $status = 0
    $responseBody = ''
    $networkError = $false

    try {
        $response = Invoke-WebRequest `
            -Uri $values.url `
            -Method Post `
            -Headers @{ Authorization = "Bearer $($values.token)" } `
            -ContentType 'application/json' `
            -Body $json `
            -TimeoutSec 10 `
            -UseBasicParsing `
            -ErrorAction Stop
        $status = [int]$response.StatusCode
        $responseBody = [string]$response.Content
    }
    catch {
        if ($null -ne $_.Exception.Response) {
            try {
                $status = [int]$_.Exception.Response.StatusCode
            }
            catch {
                $status = 0
            }

            if (-not [string]::IsNullOrEmpty([string]$_.ErrorDetails.Message)) {
                $responseBody = [string]$_.ErrorDetails.Message
            }
            else {
                try {
                    $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                    $responseBody = $reader.ReadToEnd()
                    $reader.Dispose()
                }
                catch {
                    $responseBody = ''
                }
            }
        }
        else {
            $networkError = $true
        }
    }

    if ($status -ge 200 -and $status -lt 300) {
        Write-AdapterLog "reported $($values.sha) to $($values.environment)"
        exit 0
    }

    $retry = $networkError -or $status -eq 429 -or ($status -ge 500 -and $status -lt 600)
    if ($retry -and $attempt -lt 3) {
        if ($networkError) {
            Write-AdapterLog "attempt $attempt failed with a network error; retrying"
        }
        else {
            Write-AdapterLog "attempt $attempt failed with HTTP $status; retrying"
        }
        Start-Sleep -Seconds $(if ($attempt -eq 1) { 2 } else { 4 })
        $attempt += 1
        continue
    }

    if ($responseBody.Contains([string]$values.token)) {
        $responseBody = '[redacted]'
    }
    $responseBody = $responseBody -replace '[\r\n]+', ' '

    if ($networkError) {
        Write-AdapterLog "warning: report failed after $attempt attempts because of a network error"
    }
    elseif ($status -eq 401 -or $status -eq 403) {
        if ([string]::IsNullOrWhiteSpace($responseBody)) {
            Write-AdapterLog "HTTP $status; check ROKO_DEPLOY_TOKEN"
        }
        else {
            Write-AdapterLog "HTTP ${status}: $responseBody; check ROKO_DEPLOY_TOKEN"
        }
    }
    elseif ($retry) {
        if ([string]::IsNullOrWhiteSpace($responseBody)) {
            Write-AdapterLog "warning: report failed after $attempt attempts with HTTP $status"
        }
        else {
            Write-AdapterLog "warning: report failed after $attempt attempts with HTTP ${status}: $responseBody"
        }
    }
    elseif ([string]::IsNullOrWhiteSpace($responseBody)) {
        Write-AdapterLog "HTTP $status"
    }
    else {
        Write-AdapterLog "HTTP ${status}: $responseBody"
    }

    Exit-Adapter 3
}

Exit-Adapter 3
