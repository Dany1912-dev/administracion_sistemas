#Requires -RunAsAdministrator

function Print-Ok   { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green  }
function Print-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan   }
function Print-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Print-Err  { param($msg) Write-Host "[ERR]  $msg" -ForegroundColor Red    }

$MULTIOTP_EXE  = "C:\Program Files\multiOTP\multiotp.exe"
$MULTIOTP_MSI  = "$PSScriptRoot\..\lib\Practica9\multiOTP.msi"
$VCREDIST_EXE  = "$PSScriptRoot\..\lib\Practica9\VC_redist.x64.exe"
$MULTIOTP_REG  = "Registry::HKEY_CLASSES_ROOT\CLSID\{FCEFDFAB-B0A1-4C4D-8B2B-4FF4E0A3D978}"


function Instalar-MultiOTP {
    Print-Info "Verificando instalacion de multiOTP..."

    $instalado = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" |
                 Where-Object { $_.DisplayName -like "*multiOTP*" } |
                 Select-Object -First 1

    if ($instalado) {
        Print-Warn "multiOTP ya instalado: $($instalado.DisplayVersion) (se omite)"
        return
    }

    if (-not (Test-Path $VCREDIST_EXE)) {
        Print-Err "No se encontro: $VCREDIST_EXE"
        Print-Info "Copia VC_redist.x64.exe y multiOTP.msi al mismo directorio que este script."
        return
    }

    if (-not (Test-Path $MULTIOTP_MSI)) {
        Print-Err "No se encontro: $MULTIOTP_MSI"
        return
    }

    Print-Info "Instalando Visual C++ Redistributable..."
    Start-Process $VCREDIST_EXE -ArgumentList "/quiet /norestart" -Wait
    Print-Ok "Visual C++ instalado."

    Print-Info "Instalando multiOTP Credential Provider..."
    Start-Process "msiexec.exe" -ArgumentList "/i `"$MULTIOTP_MSI`" /quiet /norestart" -Wait
    Print-Ok "multiOTP instalado."
}


function Configurar-CredentialProvider {
    Print-Info "Configurando Credential Provider..."

    if (-not (Test-Path $MULTIOTP_EXE)) {
        Print-Err "multiotp.exe no encontrado. Ejecuta primero la opcion 1."
        return
    }

    & $MULTIOTP_EXE -config max-block-failures=3      | Out-Null
    & $MULTIOTP_EXE -config failure-delayed-time=1800 | Out-Null
    Print-Ok "Lockout: 3 intentos fallidos, bloqueo 30 minutos."

    try {
        Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_logon"        -Value "0e" -ErrorAction Stop
        Set-ItemProperty -Path $MULTIOTP_REG -Name "cpus_unlock"       -Value "0e" -ErrorAction Stop
        Set-ItemProperty -Path $MULTIOTP_REG -Name "two_step_hide_otp" -Value 1    -ErrorAction Stop
        Set-ItemProperty -Path $MULTIOTP_REG -Name "multiOTPUPNFormat" -Value 0    -ErrorAction Stop
        Print-Ok "Credential Provider configurado en registro."
    } catch {
        Print-Err "Error al escribir en registro: $_"
        Print-Warn "Verifica que multiOTP este correctamente instalado."
    }
}


function Importar-Tokens-Servidor {
    if (-not (Test-Path $MULTIOTP_EXE)) {
        Print-Err "multiotp.exe no encontrado. Ejecuta primero la opcion 1."
        return
    }

    $ip = Read-Host "IP del servidor (Windows Server)"

    if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') {
        Print-Err "IP no valida: $ip"
        return
    }

    Print-Info "Introduce las credenciales de administrador del servidor."
    $usuario = Read-Host "Usuario (ej: EMPRESA\dleyva)"
    $passseg = Read-Host "Contrasena" -AsSecureString
    $passTxt = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                   [Runtime.InteropServices.Marshal]::SecureStringToBSTR($passseg))

    Print-Info "Estableciendo conexion con el servidor..."
    net use "\\$ip\c$" $passTxt /user:$usuario 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Print-Err "No se pudo conectar a \\$ip\c$"
        Print-Info "Verifica la IP y las credenciales."
        return
    }
    Print-Ok "Conexion establecida."

    $rutaRemota = "\\$ip\c$\Users\dleyva\claves_mfa.txt"

    if (-not (Test-Path $rutaRemota)) {
        Print-Err "No se encontro el archivo en: $rutaRemota"
        Print-Info "Verifica que la opcion 5 del servidor se haya ejecutado."
        net use "\\$ip\c$" /delete 2>&1 | Out-Null
        return
    }

    Print-Info "Desactivando modo servidor (validacion local)..."
    & $MULTIOTP_EXE -config server-url="" | Out-Null
    Print-Ok "Modo local activado."

    $lineas   = Get-Content $rutaRemota
    $usuario  = $null
    $registrados = 0
    $omitidos    = 0

    Write-Host ""
    Print-Info "Registrando tokens..."
    Write-Host ""

    foreach ($linea in $lineas) {
        if ($linea -match '^Usuario:\s+(.+)$') {
            $usuario = $matches[1].Trim()
        }

        if ($linea -match '^\s+Clave:\s+(.+)$' -and $usuario) {
            $clave        = $matches[1].Trim()
            $usuarioCp    = "$usuario@EMPRESA"

            & $MULTIOTP_EXE -createga $usuarioCp $clave | Out-Null

            if ($LASTEXITCODE -eq 11) {
                & $MULTIOTP_EXE -set $usuarioCp prefix-pin=0 | Out-Null
                Print-Ok "  $usuarioCp - token registrado"
                $registrados++
            } elseif ($LASTEXITCODE -eq 22) {
                Print-Warn "  $usuarioCp - ya registrado (se omite)"
                $omitidos++
            } else {
                Print-Err "  $usuarioCp - error (codigo: $LASTEXITCODE)"
            }

            $usuario = $null
        }
    }

    net use "\\$ip\c$" /delete 2>&1 | Out-Null

    Write-Host ""
    Print-Info "Resumen: $registrados registrado(s), $omitidos omitido(s)."
    Print-Warn "Reinicia el cliente para que los cambios apliquen."
}


function Mostrar-Instrucciones {
    Clear-Host
    Write-Host "========== Instrucciones de uso ==========" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "ORDEN de ejecucion:"
    Write-Host "  1) Instalar multiOTP Credential Provider"
    Write-Host "  2) Configurar Credential Provider"
    Write-Host "  3) Importar tokens del servidor (necesitas la IP del servidor)"
    Write-Host "  4) Reiniciar"
    Write-Host ""
    Write-Host "La opcion 3 se conecta a \\<IP>\c$\Users\dleyva\claves_mfa.txt"
    Write-Host "y registra todos los tokens localmente en este equipo."
    Write-Host "La validacion del OTP ocurre de forma local, sin depender del servidor."
    Write-Host ""
    Write-Host "Al iniciar sesion pon el usuario como: EMPRESA\dleyva"
    Write-Host "Se pedira primero la contrasena y luego el codigo de Google Authenticator."
    Write-Host ""
}


function Mostrar-Menu {
    do {
        Clear-Host
        Write-Host "========== Practica 09: Configuracion MFA - Cliente =========="
        Write-Host ""
        Write-Host "  [1] Instalar multiOTP Credential Provider"
        Write-Host "  [2] Configurar Credential Provider"
        Write-Host "  [3] Importar tokens del servidor"
        Write-Host "  [4] Ver instrucciones"
        Write-Host "  [5] Salir"
        Write-Host ""

        $op = Read-Host "Selecciona una opcion"

        switch ($op) {
            "1" { Clear-Host; Instalar-MultiOTP;             Read-Host "`nEnter para continuar" }
            "2" { Clear-Host; Configurar-CredentialProvider; Read-Host "`nEnter para continuar" }
            "3" { Clear-Host; Importar-Tokens-Servidor;      Read-Host "`nEnter para continuar" }
            "4" { Mostrar-Instrucciones;                     Read-Host "`nEnter para continuar" }
            "5" { Clear-Host; Write-Host "Saliendo..."; return }
            default { Print-Warn "Opcion no valida."; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}

Mostrar-Menu
