param()

. (Join-Path $PSScriptRoot 'Common.ps1')

Start-PracticeRun `
    -Name 'caja-roja' `
    -Description 'Caja roja: entradas invalidas, fallos de red y recuperacion'

$flutter = Resolve-PracticeExecutable 'flutter'
$npm = Resolve-PracticeExecutable 'npm'

Invoke-PracticeStep `
    -Label 'Wear OS: captura incompleta, nombre vacio, rangos y lectura vencida' `
    -Executable $flutter `
    -Arguments @(
        'test', 'test/watch_capture_validation_test.dart',
        '--plain-name', 'rejects', '--reporter', 'expanded'
    ) `
    -WorkingDirectory $script:PracticeRoot

Invoke-PracticeStep `
    -Label 'API de mediciones: rechaza datos invalidos y sesion expirada' `
    -Executable $flutter `
    -Arguments @(
        'test', 'test/watch_capture_api_integration_test.dart',
        '--plain-name', 'rejects', '--reporter', 'expanded'
    ) `
    -WorkingDirectory $script:PracticeRoot

Invoke-PracticeStep `
    -Label 'API de mediciones: HTTP 503 no se reporta como guardado exitoso' `
    -Executable $flutter `
    -Arguments @(
        'test', 'test/watch_capture_error_integration_test.dart',
        '--reporter', 'expanded'
    ) `
    -WorkingDirectory $script:PracticeRoot

Invoke-PracticeStep `
    -Label 'Conectividad: HTTP no saludable, error de conexion y timeout' `
    -Executable $flutter `
    -Arguments @(
        'test', 'test/supabase_connectivity_monitor_test.dart',
        '--plain-name', 'reports', '--reporter', 'expanded'
    ) `
    -WorkingDirectory $script:PracticeRoot

Invoke-PracticeStep `
    -Label 'Reportes clinicos: rechazo de campos, identificadores y datos invalidos' `
    -Executable $flutter `
    -Arguments @(
        'test', 'test/health_report_validation_test.dart',
        '--plain-name', 'rejects', '--reporter', 'expanded'
    ) `
    -WorkingDirectory $script:PracticeRoot

Invoke-PracticeStep `
    -Label 'API backend: suite completa, incluye validacion, sesion, rol y autorizacion' `
    -Executable $npm `
    -Arguments @('test', '--prefix', 'backend') `
    -WorkingDirectory $script:PracticeRoot

Write-Host ''
Write-Host '"Caja roja" aqui significa ejercitar fallos controlados y entradas invalidas;'
Write-Host 'no es una prueba de intrusion ni genera solicitudes de carga a servicios productivos.'

exit (Complete-PracticeRun)
