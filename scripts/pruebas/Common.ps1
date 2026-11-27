$script:PracticeRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script:PracticeResults = @()
$script:PracticeTestCases = @()
$script:PracticeRunDirectory = $null
$script:PracticeTranscript = $null
$script:PracticeRunName = $null
$script:PracticeRunDescription = $null
$script:PracticeRunStartedAt = $null

function Resolve-PracticeExecutable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    if ($Name -eq 'flutter') {
        $localProperties = Join-Path $script:PracticeRoot 'android\local.properties'
        if (Test-Path -LiteralPath $localProperties) {
            $sdkLine = Get-Content -LiteralPath $localProperties |
                Where-Object { $_ -match '^flutter\.sdk=' } |
                Select-Object -First 1
            if ($sdkLine) {
                $sdkPath = ($sdkLine -replace '^flutter\.sdk=', '').Replace('\\', '\')
                $flutterBat = Join-Path $sdkPath 'bin\flutter.bat'
                if (Test-Path -LiteralPath $flutterBat) {
                    return $flutterBat
                }
            }
        }
    }

    return $Name
}

function Start-PracticeRun {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    $script:PracticeResults = @()
    $script:PracticeTestCases = @()
    $runId = Get-Date -Format 'yyyyMMdd-HHmmss'
    $script:PracticeRunName = $Name
    $script:PracticeRunDescription = $Description
    $script:PracticeRunStartedAt = Get-Date
    $safeName = $Name -replace '[^a-zA-Z0-9-]', '-'
    $script:PracticeRunDirectory = Join-Path $script:PracticeRoot (
        Join-Path 'test-results\pruebas' "$safeName-$runId"
    )
    New-Item -ItemType Directory -Path $script:PracticeRunDirectory -Force |
        Out-Null

    $script:PracticeTranscript = Join-Path $script:PracticeRunDirectory 'salida-terminal.log'
    Start-Transcript -Path $script:PracticeTranscript | Out-Null

    Write-Host ''
    Write-Host "BioMedica - $Description"
    Write-Host "Fecha: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
    Write-Host "Evidencia: $script:PracticeRunDirectory"
    Write-Host '----------------------------------------------------------------'
}

function Invoke-PracticeStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [string]$Executable,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    Write-Host ''
    Write-Host "=== $Label ===" -ForegroundColor Cyan
    Write-Host "Comando: $Executable $($Arguments -join ' ')"

    $resolved = Get-Command $Executable -ErrorAction SilentlyContinue
    if (-not $resolved -and (Test-Path -LiteralPath $Executable -PathType Leaf)) {
        $resolvedPath = (Resolve-Path -LiteralPath $Executable).Path
    } elseif ($resolved) {
        $resolvedPath = $resolved.Source
    } else {
        Write-Host "ERROR: No se encontro el ejecutable '$Executable'." -ForegroundColor Red
        $script:PracticeResults += [pscustomobject]@{
            Step = $Label
            ExitCode = 127
            Seconds = 0
        }
        return 127
    }

    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    $exitCode = 1
    $stepTestCases = New-Object 'System.Collections.Generic.List[object]'
    $flutterTestsById = @{}
    Push-Location -LiteralPath $WorkingDirectory
    try {
        $commandOutput = & $resolvedPath @Arguments 2>&1
        if ($null -ne $LASTEXITCODE) {
            $exitCode = $LASTEXITCODE
        } else {
            $exitCode = 0
        }
        foreach ($outputLine in $commandOutput) {
            $line = [string]$outputLine
            Write-Host $line

            if ($line -match '^\s*\{') {
                try {
                    $event = $line | ConvertFrom-Json
                    if ($event.type -eq 'testStart' -and $event.test) {
                        $flutterTestsById[[string]$event.test.id] = $event.test
                    } elseif ($event.type -eq 'testDone' -and $flutterTestsById.ContainsKey([string]$event.testID)) {
                        $test = $flutterTestsById[[string]$event.testID]
                        if (-not $event.hidden) {
                            $result = if ($event.skipped) {
                                'SKIP'
                            } elseif ($event.result -eq 'success') {
                                'PASS'
                            } else {
                                'FAIL'
                            }
                            $stepTestCases.Add([pscustomobject]@{
                                Name = $test.name
                                Result = $result
                                DurationMs = [int]$event.time
                            })
                        }
                    }
                } catch {
                    # Ignore non-test JSON output from package managers and test tools.
                }
            }

            if ($line -match '^\s*(ok|not ok)\s+\d+\s+-\s+(.+?)(?:\s+#\s*(SKIP|TODO).*)?$') {
                $result = if ($Matches[1] -eq 'ok') { 'PASS' } else { 'FAIL' }
                if ($Matches[3] -eq 'SKIP' -or $Matches[3] -eq 'TODO') {
                    $result = 'SKIP'
                }
                $stepTestCases.Add([pscustomobject]@{
                    Name = $Matches[2]
                    Result = $result
                    DurationMs = $null
                })
            }
        }
    } catch {
        Write-Host "ERROR al ejecutar '$Label': $($_.Exception.Message)" -ForegroundColor Red
        $exitCode = 1
    } finally {
        Pop-Location
        $timer.Stop()
    }

    $script:PracticeResults += [pscustomobject]@{
        Step = $Label
        ExitCode = $exitCode
        Seconds = [math]::Round($timer.Elapsed.TotalSeconds, 2)
        TestCount = $stepTestCases.Count
        PassedTestCount = @($stepTestCases | Where-Object { $_.Result -eq 'PASS' }).Count
        FailedTestCount = @($stepTestCases | Where-Object { $_.Result -eq 'FAIL' }).Count
        SkippedTestCount = @($stepTestCases | Where-Object { $_.Result -eq 'SKIP' }).Count
        Tests = @($stepTestCases)
    }
    $script:PracticeTestCases += @($stepTestCases)

    $color = if ($exitCode -eq 0) { 'Green' } else { 'Red' }
    $status = if ($exitCode -eq 0) { 'PASS' } else { 'FAIL' }
    Write-Host ("Resultado: {0}; exit code {1}; {2}s" -f $status, $exitCode, [math]::Round($timer.Elapsed.TotalSeconds, 2)) -ForegroundColor $color
    return $exitCode
}

function Complete-PracticeRun {
    $failures = @($script:PracticeResults | Where-Object { $_.ExitCode -ne 0 })

    Write-Host ''
    Write-Host '================ RESUMEN ================'
    foreach ($result in $script:PracticeResults) {
        $status = if ($result.ExitCode -eq 0) { 'PASS' } else { 'FAIL' }
        Write-Host ("{0}: {1} (exit {2}, {3}s, {4} tests: {5} aprobadas, {6} fallidas, {7} omitidas)" -f `
            $status, $result.Step, $result.ExitCode, $result.Seconds, $result.TestCount, `
            $result.PassedTestCount, $result.FailedTestCount, $result.SkippedTestCount)
    }

    $overall = if ($failures.Count -eq 0) { 'PASS' } else { 'FAIL' }
    Write-Host "Resultado global: $overall"
    Write-Host "Log completo: $script:PracticeTranscript"
    $testSummary = [ordered]@{
        total = $script:PracticeTestCases.Count
        passed = @($script:PracticeTestCases | Where-Object { $_.Result -eq 'PASS' }).Count
        failed = @($script:PracticeTestCases | Where-Object { $_.Result -eq 'FAIL' }).Count
        skipped = @($script:PracticeTestCases | Where-Object { $_.Result -eq 'SKIP' }).Count
    }
    $summary = [ordered]@{
        suite = $script:PracticeRunName
        description = $script:PracticeRunDescription
        startedAt = $script:PracticeRunStartedAt.ToString('o')
        finishedAt = (Get-Date).ToString('o')
        result = $overall
        testCases = $testSummary
        steps = @($script:PracticeResults)
        logFile = [System.IO.Path]::GetFileName($script:PracticeTranscript)
    }
    $summaryPath = Join-Path $script:PracticeRunDirectory 'summary.json'
    $summaryJson = $summary | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText(
        $summaryPath,
        $summaryJson,
        [System.Text.UTF8Encoding]::new($false)
    )
    Write-Host "Resumen JSON: $summaryPath"
    Stop-Transcript | Out-Null

    if ($failures.Count -eq 0) {
        return 0
    }
    return 1
}
