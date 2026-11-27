param()

. (Join-Path $PSScriptRoot 'Common.ps1')

Start-PracticeRun `
    -Name 'caja-roja' `
    -Description 'Caja roja: entradas invalidas, fallos de red y recuperacion'

$flutter = Resolve-PracticeExecutable 'flutter'
$npm = Resolve-PracticeExecutable 'npm'

Invoke-PracticeStep `
    -Label 'Wear OS: validacion completa de capturas, rangos, sensores y sincronizacion' `
    -Executable $flutter `
    -Arguments @(
        'test', 'test/watch_capture_validation_test.dart', '--reporter=json'
    ) `
    -WorkingDirectory $script:PracticeRoot

Invoke-PracticeStep `
    -Label 'API de mediciones: autenticacion, rechazo de datos y permisos' `
    -Executable $flutter `
    -Arguments @(
        'test', 'test/watch_capture_api_integration_test.dart', '--reporter=json'
    ) `
    -WorkingDirectory $script:PracticeRoot

Invoke-PracticeStep `
    -Label 'API de mediciones: errores de servicio, timeout y estados HTTP' `
    -Executable $flutter `
    -Arguments @(
        'test', 'test/watch_capture_error_integration_test.dart', '--reporter=json'
    ) `
    -WorkingDirectory $script:PracticeRoot

Invoke-PracticeStep `
    -Label 'Conectividad: errores de red, recuperacion y respuestas no saludables' `
    -Executable $flutter `
    -Arguments @(
        'test', 'test/supabase_connectivity_monitor_test.dart', '--reporter=json'
    ) `
    -WorkingDirectory $script:PracticeRoot

Invoke-PracticeStep `
    -Label 'Reportes clinicos: validacion, duplicados y contenido invalido' `
    -Executable $flutter `
    -Arguments @(
        'test', 'test/health_report_validation_test.dart', '--reporter=json'
    ) `
    -WorkingDirectory $script:PracticeRoot

Invoke-PracticeStep `
    -Label 'API backend: suite completa, incluye validacion, sesion, rol y autorizacion' `
    -Executable $npm `
    -Arguments @('test', '--prefix', 'backend', '--', '--test-reporter=tap') `
    -WorkingDirectory $script:PracticeRoot

Write-Host ''
Write-Host '"Caja roja" aqui significa ejercitar fallos controlados y entradas invalidas;'
Write-Host 'no es una prueba de intrusion ni genera solicitudes de carga a servicios productivos.'

exit (Complete-PracticeRun)
