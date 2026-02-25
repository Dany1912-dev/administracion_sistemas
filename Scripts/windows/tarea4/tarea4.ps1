# Tarea 4 - Automatizacion y gestion del servidor SSH (Windows)
# Requiere ejecutarse como Administrador

# ---------- Colores ----------
function Print-Error      { param($msg) Write-Host $msg -ForegroundColor Red }
function Print-Completado { param($msg) Write-Host $msg -ForegroundColor Green }
function Print-Info       { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Print-Titulo     { param($msg) Write-Host $msg -ForegroundColor Cyan }

# ---------- Verificar Administrador ----------
function Verificar-Admin {
    $esAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $esAdmin) {
        Print-Error "Este script debe ejecutarse como Administrador."
        Print-Info  "Haz clic derecho en PowerShell y selecciona 'Ejecutar como administrador'."
        exit 1
    }
}

# ---------- Funciones ----------

function Ayuda {
    Write-Host "Uso del script: .\tarea4_SSH_windows.ps1 [opcion]"
    Write-Host "Opciones:"
    Write-Host "  -verify       Verifica si esta instalado SSH"
    Write-Host "  -install      Instala y configura SSH"
    Write-Host "  -restart      Reiniciar servidor SSH"
    Write-Host "  -status       Verificar estado del servidor SSH"
    Write-Host "  -help         Muestra esta ayuda"
}

function Verificar-Instalacion {
    Print-Info "Verificando instalacion de SSH..."

    $ssh = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" }

    if ($ssh.State -eq "Installed") {
        $version = (Get-Item "$env:SystemRoot\System32\OpenSSH\sshd.exe").VersionInfo.FileVersion
        Print-Completado "SSH ya esta instalado (version: $version)"
        return $true
    }

    Print-Error "SSH no esta instalado"
    return $false
}

function Instalar-SSH {
    Print-Titulo "=== Instalacion y Configuracion de SSH ==="
    Write-Host ""

    # 1. Verificar si SSH ya esta instalado
    if (Verificar-Instalacion) {
        $reconf = Read-Host "Desea reconfigurar el servidor SSH? [s/N]"
        if ($reconf -notmatch "^[Ss]$") {
            Print-Info "Operacion cancelada"
            return
        }
    } else {
        Print-Info "Instalando OpenSSH Server..."

        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null

        if ($?) {
            Print-Completado "SSH instalado correctamente"
        } else {
            Print-Error "Error en la instalacion de SSH"
            return
        }
    }

    Write-Host ""

    # 2. Activar y habilitar el servicio
    Print-Info "Habilitando servicio SSH en el arranque..."
    Set-Service -Name sshd -StartupType Automatic
    Print-Completado "Servicio sshd configurado para arranque automatico"

    Print-Info "Iniciando servicio SSH..."
    $estado = (Get-Service -Name sshd).Status

    if ($estado -eq "Running") {
        Print-Info "Servicio ya estaba activo, reiniciando..."
        Restart-Service sshd
        Print-Completado "Servicio sshd reiniciado"
    } else {
        Start-Service sshd
        if ((Get-Service -Name sshd).Status -eq "Running") {
            Print-Completado "Servicio sshd iniciado"
        } else {
            Print-Error "Error al iniciar el servicio sshd"
            Print-Error "Revise los logs: Get-EventLog -LogName System -Source sshd"
            return
        }
    }

    # 3. Obtener el puerto configurado
    $sshConf = "$env:ProgramData\ssh\sshd_config"
    $puerto = 22

    if (Test-Path $sshConf) {
        $lineaPuerto = Select-String -Path $sshConf -Pattern "^Port\s+(\d+)" | Select-Object -First 1
        if ($lineaPuerto) {
            $puerto = $lineaPuerto.Matches.Groups[1].Value
        }
    }

    Print-Info "Puerto SSH configurado: $puerto"

    # 4. Abrir puerto en el firewall
    Print-Info "Configurando firewall para SSH (puerto $puerto)..."

    $regla = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue

    if ($regla) {
        if ($regla.Enabled -eq "True") {
            Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -Profile Any
            Print-Completado "Regla de firewall ya existe y esta habilitada"
        } else {
            Print-Error "La regla existe pero esta DESHABILITADA, habilitando..."
            Set-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -Enabled True
            Print-Completado "Regla habilitada correctamente"
        }
    } else {
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" `
            -DisplayName "OpenSSH SSH Server (sshd)" `
            -Enabled True `
            -Direction Inbound `
            -Protocol TCP `
            -Action Allow `
            -LocalPort $puerto | Out-Null

        if ($?) {
            Print-Completado "Puerto $puerto/TCP abierto en el firewall"
        } else {
            Print-Error "No se pudo configurar el firewall"
        }
    }

    # 5. Verificacion final
    Write-Host ""
    Print-Info "Verificando estado del servidor SSH..."
    Write-Host ""

    if ((Get-Service -Name sshd).Status -eq "Running") {
        Print-Completado "Servicio sshd: activo y corriendo"
    } else {
        Print-Error "Servicio sshd: NO esta corriendo"
        return
    }

    $escuchando = netstat -an | Select-String ":$puerto\s.*LISTENING"
    if ($escuchando) {
        Print-Completado "Puerto ${puerto}: escuchando"
    } else {
        Print-Error "Puerto ${puerto}: NO esta escuchando"
    }

    # 6. Resumen
    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | Select-Object -First 1).IPAddress

    Write-Host ""
    Print-Completado "======================================"
    Print-Completado "  SSH listo para conexiones remotas"
    Print-Completado "======================================"
    Print-Info       "  IP del servidor : $ip"
    Print-Info       "  Puerto          : $puerto"
    Print-Info       "  Comando SSH     : ssh usuario@$ip -p $puerto"
    Print-Completado "======================================"
}

function Reiniciar-SSH {
    Print-Info "Reiniciando servidor SSH..."

    $estado = (Get-Service -Name sshd -ErrorAction SilentlyContinue).Status

    if ($null -eq $estado) {
        Print-Error "El servicio sshd no existe. Instale SSH primero con -install"
        return
    }

    if ($estado -ne "Running") {
        Print-Error "El servicio SSH no esta activo"
        $opc = Read-Host "Desea iniciarlo en lugar de reiniciarlo? (y/n)"
        if ($opc -eq "y") {
            Start-Service sshd
        } else {
            return
        }
    } else {
        Restart-Service sshd
    }

    if ((Get-Service -Name sshd).Status -eq "Running") {
        Print-Completado "Servidor SSH reiniciado correctamente"
        Get-Service sshd
    } else {
        Print-Error "Error al reiniciar el servidor SSH"
        Print-Info  "Revise los logs: Get-EventLog -LogName System -Source sshd"
    }
}

function Ver-Estado {
    Print-Titulo "=== ESTADO DEL SERVIDOR SSH ==="
    $servicio = Get-Service -Name sshd -ErrorAction SilentlyContinue

    if ($null -eq $servicio) {
        Print-Error "El servicio sshd no existe. SSH no esta instalado."
        return
    }

    Get-Service sshd
    Write-Host ""
    Print-Info "Tipo de inicio: $((Get-Service sshd).StartType)"

    $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | Select-Object -First 1).IPAddress
    $sshConf = "$env:ProgramData\ssh\sshd_config"
    $puerto = 22

    if (Test-Path $sshConf) {
        $lineaPuerto = Select-String -Path $sshConf -Pattern "^Port\s+(\d+)" | Select-Object -First 1
        if ($lineaPuerto) {
            $puerto = $lineaPuerto.Matches.Groups[1].Value
        }
    }

    Print-Info "IP del servidor : $ip"
    Print-Info "Puerto          : $puerto"
}

# ---------- Main ----------
Verificar-Admin

switch ($args[0]) {
    "-verify"  { Verificar-Instalacion }
    "-install" { Instalar-SSH }
    "-restart" { Reiniciar-SSH }
    "-status"  { Ver-Estado }
    "-help"    { Ayuda }
    default    { Ayuda }
}