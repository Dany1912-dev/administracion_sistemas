# ============================================================================
# Script de Automatización de Servidor FTP - Windows Server
# Administración de Sistemas
# Servidor: IIS FTP Service
# Interfaz de red: Ethernet 3
# ============================================================================

# ---------- Colores ----------
function Print-Error      { param($msg) Write-Host $msg -ForegroundColor Red }
function Print-Completado { param($msg) Write-Host $msg -ForegroundColor Green }
function Print-Info       { param($msg) Write-Host $msg -ForegroundColor Yellow }
function Print-Titulo     { param($msg) Write-Host $msg -ForegroundColor Cyan }

# ---------- Variables Globales ----------
$script:FTP_ROOT = "C:\inetpub\ftproot"
$script:GRUPO_REPROBADOS = "reprobados"
$script:GRUPO_RECURSADORES = "recursadores"
$script:INTERFAZ_RED = "Ethernet 3"

# ---------- Verificar Administrador ----------
function Verificar-Admin {
    $esAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $esAdmin) {
        Print-Error "Este script debe ejecutarse como Administrador."
        Print-Info  "Haz clic derecho en PowerShell y selecciona 'Ejecutar como administrador'."
        exit 1
    }
}

# ============================================================================
# FUNCIÓN: Ayuda
# ============================================================================
function Ayuda {
    Write-Host "Uso del script: .\script-ftp.ps1 [opcion]"
    Write-Host "Opciones:"
    Write-Host "  -verify       Verifica si esta instalado FTP"
    Write-Host "  -install      Instala y configura el servidor FTP"
    Write-Host "  -users        Gestionar usuarios FTP"
    Write-Host "  -restart      Reiniciar servidor FTP"
    Write-Host "  -status       Verificar estado del servidor FTP"
    Write-Host "  -list         Listar usuarios y estructura FTP"
    Write-Host "  -help         Muestra esta ayuda"
}

# ============================================================================
# FUNCIÓN: Verificar instalación de IIS FTP
# ============================================================================
function Verificar-Instalacion {
    Print-Info "Verificando instalacion de IIS FTP..."
    
    $ftpFeature = Get-WindowsFeature -Name Web-Ftp-Server -ErrorAction SilentlyContinue
    
    if ($null -eq $ftpFeature) {
        Print-Error "No se pudo verificar el estado de IIS FTP"
        return $false
    }
    
    if ($ftpFeature.Installed) {
        Print-Completado "IIS FTP ya esta instalado"
        return $true
    }
    
    Print-Error "IIS FTP no esta instalado"
    return $false
}

# ============================================================================
# FUNCIÓN: Crear estructura de directorios base
# ============================================================================
function Crear-EstructuraBase {
    Print-Info "Creando estructura de directorios FTP..."
    
    # Crear directorio raíz FTP
    if (-not (Test-Path $script:FTP_ROOT)) {
        New-Item -ItemType Directory -Path $script:FTP_ROOT -Force | Out-Null
        Print-Completado "Directorio raiz creado: $script:FTP_ROOT"
    }
    
    # Crear carpeta general (pública)
    $generalPath = Join-Path $script:FTP_ROOT "general"
    if (-not (Test-Path $generalPath)) {
        New-Item -ItemType Directory -Path $generalPath -Force | Out-Null
        Print-Completado "Carpeta 'general' creada"
    }
    
    # Crear carpetas de grupos
    $reprobadosPath = Join-Path $script:FTP_ROOT $script:GRUPO_REPROBADOS
    if (-not (Test-Path $reprobadosPath)) {
        New-Item -ItemType Directory -Path $reprobadosPath -Force | Out-Null
        Print-Completado "Carpeta '$script:GRUPO_REPROBADOS' creada"
    }
    
    $recursadoresPath = Join-Path $script:FTP_ROOT $script:GRUPO_RECURSADORES
    if (-not (Test-Path $recursadoresPath)) {
        New-Item -ItemType Directory -Path $recursadoresPath -Force | Out-Null
        Print-Completado "Carpeta '$script:GRUPO_RECURSADORES' creada"
    }
    
    Print-Completado "Estructura de directorios base configurada"
}

# ============================================================================
# FUNCIÓN: Crear grupos locales
# ============================================================================
function Crear-Grupos {
    Print-Info "Verificando grupos del sistema..."
    
    # Crear grupo reprobados
    try {
        $grupoReprobados = Get-LocalGroup -Name $script:GRUPO_REPROBADOS -ErrorAction SilentlyContinue
        if ($null -eq $grupoReprobados) {
            New-LocalGroup -Name $script:GRUPO_REPROBADOS -Description "Grupo de usuarios reprobados FTP" | Out-Null
            Print-Completado "Grupo '$script:GRUPO_REPROBADOS' creado"
        } else {
            Print-Info "Grupo '$script:GRUPO_REPROBADOS' ya existe"
        }
    } catch {
        Print-Error "Error al crear grupo '$script:GRUPO_REPROBADOS': $_"
    }
    
    # Crear grupo recursadores
    try {
        $grupoRecursadores = Get-LocalGroup -Name $script:GRUPO_RECURSADORES -ErrorAction SilentlyContinue
        if ($null -eq $grupoRecursadores) {
            New-LocalGroup -Name $script:GRUPO_RECURSADORES -Description "Grupo de usuarios recursadores FTP" | Out-Null
            Print-Completado "Grupo '$script:GRUPO_RECURSADORES' creado"
        } else {
            Print-Info "Grupo '$script:GRUPO_RECURSADORES' ya existe"
        }
    } catch {
        Print-Error "Error al crear grupo '$script:GRUPO_RECURSADORES': $_"
    }
    
    Print-Completado "Grupos configurados correctamente"
}

# ============================================================================
# FUNCIÓN: Configurar permisos NTFS
# ============================================================================
function Configurar-PermisosNTFS {
    param(
        [string]$Ruta,
        [string]$Usuario,
        [string]$Permisos = "Modify"
    )
    
    try {
        $acl = Get-Acl $Ruta
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $Usuario,
            $Permisos,
            "ContainerInherit,ObjectInherit",
            "None",
            "Allow"
        )
        $acl.SetAccessRule($accessRule)
        Set-Acl -Path $Ruta -AclObject $acl
        return $true
    } catch {
        Print-Error "Error configurando permisos NTFS: $_"
        return $false
    }
}

# ============================================================================
# FUNCIÓN: Configurar sitio FTP en IIS
# ============================================================================
function Configurar-SitioFTP {
    Print-Info "Configurando sitio FTP en IIS..."
    
    # Importar módulo WebAdministration
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    
    # Verificar si el sitio FTP ya existe
    $sitioFTP = Get-Website | Where-Object { $_.Name -eq "FTP_Server" }
    
    if ($sitioFTP) {
        Print-Info "Sitio FTP ya existe, eliminando para recrear..."
        Remove-Website -Name "FTP_Server" -ErrorAction SilentlyContinue
    }
    
    # Obtener IP de la interfaz Ethernet 3
    $ip = (Get-NetIPAddress -InterfaceAlias $script:INTERFAZ_RED -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    
    if ($null -eq $ip) {
        Print-Error "No se pudo obtener la IP de la interfaz '$script:INTERFAZ_RED'"
        Print-Info "Usando todas las IPs disponibles (*)"
        $ip = "*"
    } else {
        Print-Info "IP de la interfaz '$script:INTERFAZ_RED': $ip"
    }
    
    # Crear sitio FTP
    try {
        New-WebFtpSite -Name "FTP_Server" `
                       -PhysicalPath $script:FTP_ROOT `
                       -IPAddress $ip `
                       -Port 21 `
                       -Force | Out-Null
        
        Print-Completado "Sitio FTP creado"
    } catch {
        Print-Error "Error creando sitio FTP: $_"
        return $false
    }
    
    # Configurar autenticación básica
    Set-ItemProperty "IIS:\Sites\FTP_Server" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\FTP_Server" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    
    Print-Completado "Autenticacion configurada"
    
    # Configurar SSL (opcional - permitir conexiones no SSL)
    Set-ItemProperty "IIS:\Sites\FTP_Server" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
    Set-ItemProperty "IIS:\Sites\FTP_Server" -Name ftpServer.security.ssl.dataChannelPolicy -Value 0
    
    Print-Completado "Politica SSL configurada"
    
    return $true
}

# ============================================================================
# FUNCIÓN: Configurar reglas de autorización FTP
# ============================================================================
function Configurar-AutorizacionFTP {
    Print-Info "Configurando reglas de autorizacion FTP..."
    
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    
    # Limpiar reglas existentes
    Clear-WebConfiguration -PSPath "IIS:\Sites\FTP_Server" -Filter "/system.ftpServer/security/authorization" -ErrorAction SilentlyContinue
    
    # Regla para acceso anónimo (solo lectura en /general)
    Add-WebConfiguration -PSPath "IIS:\Sites\FTP_Server" `
                         -Filter "/system.ftpServer/security/authorization" `
                         -Value @{
                             accessType = "Allow"
                             users = "anonymous"
                             permissions = "Read"
                         }
    
    Print-Completado "Acceso anonimo configurado (solo lectura)"
    
    # Regla para usuarios autenticados (lectura y escritura)
    Add-WebConfiguration -PSPath "IIS:\Sites\FTP_Server" `
                         -Filter "/system.ftpServer/security/authorization" `
                         -Value @{
                             accessType = "Allow"
                             roles = $script:GRUPO_REPROBADOS
                             permissions = "Read,Write"
                         }
    
    Add-WebConfiguration -PSPath "IIS:\Sites\FTP_Server" `
                         -Filter "/system.ftpServer/security/authorization" `
                         -Value @{
                             accessType = "Allow"
                             roles = $script:GRUPO_RECURSADORES
                             permissions = "Read,Write"
                         }
    
    Print-Completado "Reglas de autorizacion configuradas"
}

# ============================================================================
# FUNCIÓN: Configurar Firewall
# ============================================================================
function Configurar-Firewall {
    Print-Info "Configurando firewall para FTP..."
    
    # Regla para puerto 21
    $reglaFTP = Get-NetFirewallRule -DisplayName "FTP Server (Puerto 21)" -ErrorAction SilentlyContinue
    if ($null -eq $reglaFTP) {
        New-NetFirewallRule -DisplayName "FTP Server (Puerto 21)" `
                            -Direction Inbound `
                            -Protocol TCP `
                            -LocalPort 21 `
                            -Action Allow | Out-Null
        Print-Completado "Regla de firewall para puerto 21 creada"
    } else {
        Print-Info "Regla de firewall para puerto 21 ya existe"
    }
    
    # Regla para modo pasivo (puertos 1024-65535)
    $reglaPasivo = Get-NetFirewallRule -DisplayName "FTP Server (Modo Pasivo)" -ErrorAction SilentlyContinue
    if ($null -eq $reglaPasivo) {
        New-NetFirewallRule -DisplayName "FTP Server (Modo Pasivo)" `
                            -Direction Inbound `
                            -Protocol TCP `
                            -LocalPort 1024-65535 `
                            -Action Allow | Out-Null
        Print-Completado "Regla de firewall para modo pasivo creada"
    } else {
        Print-Info "Regla de firewall para modo pasivo ya existe"
    }
}

# ============================================================================
# FUNCIÓN: Instalar y configurar servidor FTP
# ============================================================================
function Instalar-FTP {
    Print-Titulo "=== Instalacion y Configuracion de Servidor FTP ==="
    Write-Host ""
    
    # 1. Verificar si IIS FTP ya está instalado
    if (Verificar-Instalacion) {
        $reconf = Read-Host "Desea reconfigurar el servidor FTP? [s/N]"
        if ($reconf -notmatch "^[Ss]$") {
            Print-Info "Operacion cancelada"
            return
        }
    } else {
        Print-Info "Instalando IIS FTP Server..."
        
        # Instalar IIS Web Server (requisito)
        $iisFeature = Get-WindowsFeature -Name Web-Server
        if (-not $iisFeature.Installed) {
            Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
            Print-Completado "IIS Web Server instalado"
        }
        
        # Instalar FTP Server
        Install-WindowsFeature -Name Web-Ftp-Server -IncludeAllSubFeature | Out-Null
        
        if ($?) {
            Print-Completado "IIS FTP Server instalado correctamente"
        } else {
            Print-Error "Error en la instalacion de IIS FTP Server"
            return
        }
    }
    
    Write-Host ""
    
    # 2. Crear grupos del sistema
    Crear-Grupos
    Write-Host ""
    
    # 3. Crear estructura de directorios
    Crear-EstructuraBase
    Write-Host ""
    
    # 4. Configurar sitio FTP
    if (-not (Configurar-SitioFTP)) {
        return
    }
    Write-Host ""
    
    # 5. Configurar autorización
    Configurar-AutorizacionFTP
    Write-Host ""
    
    # 6. Configurar firewall
    Configurar-Firewall
    Write-Host ""
    
    # 7. Iniciar el sitio FTP
    Print-Info "Iniciando sitio FTP..."
    try {
        Start-Website -Name "FTP_Server"
        Print-Completado "Sitio FTP iniciado"
    } catch {
        Print-Error "Error al iniciar sitio FTP: $_"
    }
    
    # 8. Verificación final
    Write-Host ""
    Print-Info "Verificando estado del servidor FTP..."
    Write-Host ""
    
    $sitio = Get-Website -Name "FTP_Server" -ErrorAction SilentlyContinue
    if ($sitio -and $sitio.State -eq "Started") {
        Print-Completado "Sitio FTP: activo y corriendo"
    } else {
        Print-Error "Sitio FTP: NO esta corriendo"
    }
    
    # Obtener IP de la interfaz
    $ip = (Get-NetIPAddress -InterfaceAlias $script:INTERFAZ_RED -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    
    if ($null -eq $ip) {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127.*" } | Select-Object -First 1).IPAddress
    }
    
    # 9. Resumen
    Write-Host ""
    Print-Completado "══════════════════════════════════════"
    Print-Completado "  Servidor FTP listo"
    Print-Completado "══════════════════════════════════════"
    Print-Info "  IP del servidor : $ip"
    Print-Info "  Interfaz        : $script:INTERFAZ_RED"
    Print-Info "  Puerto FTP      : 21"
    Print-Info "  Acceso anonimo  : ftp://$ip/general"
    Print-Info "  Raiz FTP        : $script:FTP_ROOT"
    Print-Completado "══════════════════════════════════════"
    Write-Host ""
    Print-Info "Ahora puede crear usuarios con: .\script-ftp.ps1 -users"
}

# ============================================================================
# FUNCIÓN: Validar nombre de usuario
# ============================================================================
function Validar-Usuario {
    param([string]$Usuario)
    
    if ([string]::IsNullOrWhiteSpace($Usuario)) {
        Print-Error "El nombre de usuario no puede estar vacio"
        return $false
    }
    
    if ($Usuario.Length -lt 3 -or $Usuario.Length -gt 20) {
        Print-Error "El nombre de usuario debe tener entre 3 y 20 caracteres"
        return $false
    }
    
    if ($Usuario -notmatch '^[a-z][a-z0-9_-]*$') {
        Print-Error "El nombre de usuario debe comenzar con letra minuscula"
        Print-Error "y solo puede contener letras, numeros, guiones y guiones bajos"
        return $false
    }
    
    # Verificar que no exista
    $usuarioExiste = Get-LocalUser -Name $Usuario -ErrorAction SilentlyContinue
    if ($null -ne $usuarioExiste) {
        Print-Error "El usuario '$Usuario' ya existe en el sistema"
        return $false
    }
    
    return $true
}

# ============================================================================
# FUNCIÓN: Crear usuario FTP
# ============================================================================
function Crear-UsuarioFTP {
    param(
        [string]$Usuario,
        [securestring]$Password,
        [string]$Grupo
    )
    
    Print-Info "Creando usuario '$Usuario' en grupo '$Grupo'..."
    
    try {
        # Crear usuario local
        New-LocalUser -Name $Usuario `
                      -Password $Password `
                      -FullName $Usuario `
                      -Description "Usuario FTP - Grupo $Grupo" `
                      -PasswordNeverExpires `
                      -UserMayNotChangePassword | Out-Null
        
        Print-Completado "Usuario del sistema creado"
        
        # Agregar usuario al grupo
        Add-LocalGroupMember -Group $Grupo -Member $Usuario
        Print-Completado "Usuario agregado al grupo '$Grupo'"
        
        # Crear directorio personal
        $userDir = Join-Path $script:FTP_ROOT $Usuario
        if (-not (Test-Path $userDir)) {
            New-Item -ItemType Directory -Path $userDir -Force | Out-Null
            Print-Completado "Directorio personal creado: $userDir"
        }
        
        # Configurar permisos NTFS
        Configurar-PermisosNTFS -Ruta $userDir -Usuario $Usuario -Permisos "Modify"
        Configurar-PermisosNTFS -Ruta (Join-Path $script:FTP_ROOT "general") -Usuario $Usuario -Permisos "Modify"
        Configurar-PermisosNTFS -Ruta (Join-Path $script:FTP_ROOT $Grupo) -Usuario $Usuario -Permisos "Modify"
        
        Print-Completado "Permisos NTFS configurados"
        Print-Completado "Usuario '$Usuario' creado exitosamente"
        
        return $true
    } catch {
        Print-Error "Error al crear usuario: $_"
        return $false
    }
}

# ============================================================================
# FUNCIÓN: Cambiar grupo de usuario
# ============================================================================
function Cambiar-GrupoUsuario {
    param([string]$Usuario)
    
    # Verificar que el usuario existe
    $user = Get-LocalUser -Name $Usuario -ErrorAction SilentlyContinue
    if ($null -eq $user) {
        Print-Error "El usuario '$Usuario' no existe"
        return $false
    }
    
    # Obtener grupos actuales
    $gruposActuales = Get-LocalGroup | Where-Object {
        (Get-LocalGroupMember -Group $_.Name -ErrorAction SilentlyContinue).Name -contains "$env:COMPUTERNAME\$Usuario"
    }
    
    $grupoActual = $gruposActuales | Where-Object { 
        $_.Name -eq $script:GRUPO_REPROBADOS -or $_.Name -eq $script:GRUPO_RECURSADORES 
    } | Select-Object -First 1
    
    if ($grupoActual) {
        Print-Info "Grupo actual de '$Usuario': $($grupoActual.Name)"
    }
    
    # Preguntar nuevo grupo
    Write-Host ""
    Write-Host "Grupos disponibles:"
    Write-Host "  1) $script:GRUPO_REPROBADOS"
    Write-Host "  2) $script:GRUPO_RECURSADORES"
    $opcion = Read-Host "Seleccione el nuevo grupo [1-2]"
    
    $nuevoGrupo = switch ($opcion) {
        "1" { $script:GRUPO_REPROBADOS }
        "2" { $script:GRUPO_RECURSADORES }
        default { 
            Print-Error "Opcion invalida"
            return $false
        }
    }
    
    if ($grupoActual -and $grupoActual.Name -eq $nuevoGrupo) {
        Print-Info "El usuario ya pertenece al grupo '$nuevoGrupo'"
        return $true
    }
    
    try {
        # Remover de grupo anterior
        if ($grupoActual) {
            Remove-LocalGroupMember -Group $grupoActual.Name -Member $Usuario -ErrorAction SilentlyContinue
            Print-Info "Usuario removido del grupo '$($grupoActual.Name)'"
        }
        
        # Agregar a nuevo grupo
        Add-LocalGroupMember -Group $nuevoGrupo -Member $Usuario
        Print-Completado "Usuario '$Usuario' movido al grupo '$nuevoGrupo'"
        
        # Actualizar permisos
        if ($grupoActual) {
            $oldGroupPath = Join-Path $script:FTP_ROOT $grupoActual.Name
            # Aquí podrías remover permisos del grupo anterior si es necesario
        }
        
        $newGroupPath = Join-Path $script:FTP_ROOT $nuevoGrupo
        Configurar-PermisosNTFS -Ruta $newGroupPath -Usuario $Usuario -Permisos "Modify"
        
        Print-Completado "Permisos actualizados"
        return $true
    } catch {
        Print-Error "Error al cambiar grupo: $_"
        return $false
    }
}

# ============================================================================
# FUNCIÓN: Gestionar usuarios FTP
# ============================================================================
function Gestionar-Usuarios {
    Print-Titulo "=== Gestion de Usuarios FTP ==="
    Write-Host ""
    
    if (-not (Verificar-Instalacion)) {
        Print-Error "IIS FTP no esta instalado"
        Print-Info "Ejecute primero: .\script-ftp.ps1 -install"
        return
    }
    
    Write-Host "Opciones:"
    Write-Host "  1) Crear nuevos usuarios"
    Write-Host "  2) Cambiar grupo de un usuario"
    Write-Host "  3) Eliminar usuario"
    Write-Host "  4) Volver"
    Write-Host ""
    $opcion = Read-Host "Seleccione una opcion [1-4]"
    
    switch ($opcion) {
        "1" {
            # Crear nuevos usuarios
            Write-Host ""
            $numUsuarios = Read-Host "Cuantos usuarios desea crear?"
            
            if ($numUsuarios -notmatch '^\d+$' -or [int]$numUsuarios -lt 1) {
                Print-Error "Numero de usuarios invalido"
                return
            }
            
            for ($i = 1; $i -le [int]$numUsuarios; $i++) {
                Write-Host ""
                Print-Titulo "Usuario $i de $numUsuarios"
                
                # Pedir nombre de usuario
                do {
                    $usuario = Read-Host "Nombre de usuario"
                    $valido = Validar-Usuario -Usuario $usuario
                } while (-not $valido)
                
                # Pedir contraseña
                do {
                    $password = Read-Host "Contrasena" -AsSecureString
                    $password2 = Read-Host "Confirmar contrasena" -AsSecureString
                    
                    $pwd1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
                    $pwd2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password2))
                    
                    if ($pwd1.Length -lt 6) {
                        Print-Error "La contrasena debe tener al menos 6 caracteres"
                        $valido = $false
                    } elseif ($pwd1 -ne $pwd2) {
                        Print-Error "Las contrasenas no coinciden"
                        $valido = $false
                    } else {
                        $valido = $true
                    }
                } while (-not $valido)
                
                # Preguntar grupo
                Write-Host ""
                Write-Host "A que grupo pertenece?"
                Write-Host "  1) $script:GRUPO_REPROBADOS"
                Write-Host "  2) $script:GRUPO_RECURSADORES"
                $grupoOpcion = Read-Host "Seleccione el grupo [1-2]"
                
                $grupo = switch ($grupoOpcion) {
                    "1" { $script:GRUPO_REPROBADOS }
                    "2" { $script:GRUPO_RECURSADORES }
                    default {
                        Print-Error "Opcion invalida, asignando a '$script:GRUPO_REPROBADOS'"
                        $script:GRUPO_REPROBADOS
                    }
                }
                
                # Crear usuario
                if (Crear-UsuarioFTP -Usuario $usuario -Password $password -Grupo $grupo) {
                    Write-Host ""
                    Print-Completado "Usuario '$usuario' creado en grupo '$grupo'"
                } else {
                    Print-Error "Error al crear usuario '$usuario'"
                }
            }
            
            Write-Host ""
            Print-Info "Usuarios creados exitosamente"
        }
        
        "2" {
            # Cambiar grupo
            Write-Host ""
            Listar-UsuariosFTP
            Write-Host ""
            $usuario = Read-Host "Ingrese el nombre del usuario"
            Cambiar-GrupoUsuario -Usuario $usuario
        }
        
        "3" {
            # Eliminar usuario
            Write-Host ""
            Listar-UsuariosFTP
            Write-Host ""
            $usuario = Read-Host "Ingrese el nombre del usuario a eliminar"
            
            $user = Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue
            if ($null -eq $user) {
                Print-Error "El usuario '$usuario' no existe"
                return
            }
            
            $confirmar = Read-Host "Esta seguro de eliminar el usuario '$usuario'? [s/N]"
            if ($confirmar -match "^[Ss]$") {
                try {
                    # Eliminar directorio personal
                    $userDir = Join-Path $script:FTP_ROOT $usuario
                    if (Test-Path $userDir) {
                        Remove-Item -Path $userDir -Recurse -Force
                    }
                    
                    # Eliminar usuario
                    Remove-LocalUser -Name $usuario
                    
                    Print-Completado "Usuario '$usuario' eliminado"
                } catch {
                    Print-Error "Error al eliminar usuario: $_"
                }
            } else {
                Print-Info "Operacion cancelada"
            }
        }
        
        "4" {
            return
        }
        
        default {
            Print-Error "Opcion invalida"
        }
    }
}

# ============================================================================
# FUNCIÓN: Listar usuarios FTP
# ============================================================================
function Listar-UsuariosFTP {
    Print-Titulo "=== Usuarios FTP Configurados ==="
    Write-Host ""
    
    $usuarios = Get-LocalUser | Where-Object { 
        $_.Description -like "*Usuario FTP*"
    }
    
    if ($usuarios.Count -eq 0) {
        Print-Info "No hay usuarios FTP configurados"
        return
    }
    
    Write-Host ("{0,-20} {1,-20} {2,-30}" -f "USUARIO", "GRUPO", "DIRECTORIO")
    Write-Host ("=" * 70)
    
    foreach ($user in $usuarios) {
        $grupos = Get-LocalGroup | Where-Object {
            (Get-LocalGroupMember -Group $_.Name -ErrorAction SilentlyContinue).Name -contains "$env:COMPUTERNAME\$($user.Name)"
        }
        
        $grupoFTP = $grupos | Where-Object { 
            $_.Name -eq $script:GRUPO_REPROBADOS -or $_.Name -eq $script:GRUPO_RECURSADORES 
        } | Select-Object -First 1
        
        $dir = Join-Path $script:FTP_ROOT $user.Name
        
        $grupoNombre = if ($grupoFTP) { $grupoFTP.Name } else { "N/A" }
        
        Write-Host ("{0,-20} {1,-20} {2,-30}" -f $user.Name, $grupoNombre, $dir)
    }
    
    Write-Host ""
}

# ============================================================================
# FUNCIÓN: Listar estructura FTP
# ============================================================================
function Listar-Estructura {
    Print-Titulo "=== Estructura del Servidor FTP ==="
    Write-Host ""
    
    if (-not (Test-Path $script:FTP_ROOT)) {
        Print-Error "El directorio FTP no existe: $script:FTP_ROOT"
        return
    }
    
    Print-Info "Raiz FTP: $script:FTP_ROOT"
    Print-Info "Interfaz: $script:INTERFAZ_RED"
    
    $ip = (Get-NetIPAddress -InterfaceAlias $script:INTERFAZ_RED -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    if ($ip) {
        Print-Info "IP: $ip"
    }
    
    Write-Host ""
    Print-Info "Estructura de directorios:"
    Get-ChildItem -Path $script:FTP_ROOT -Directory | Format-Table Name, LastWriteTime, @{Name="Permisos";Expression={(Get-Acl $_.FullName).Access.Count}}
    
    Write-Host ""
    Listar-UsuariosFTP
}

# ============================================================================
# FUNCIÓN: Reiniciar servidor FTP
# ============================================================================
function Reiniciar-FTP {
    Print-Info "Reiniciando servidor FTP..."
    
    $sitio = Get-Website -Name "FTP_Server" -ErrorAction SilentlyContinue
    
    if ($null -eq $sitio) {
        Print-Error "El sitio FTP no existe"
        return
    }
    
    try {
        Stop-Website -Name "FTP_Server" -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Start-Website -Name "FTP_Server"
        
        $sitio = Get-Website -Name "FTP_Server"
        if ($sitio.State -eq "Started") {
            Print-Completado "Servidor FTP reiniciado correctamente"
            Ver-Estado
        } else {
            Print-Error "Error al reiniciar el servidor FTP"
        }
    } catch {
        Print-Error "Error al reiniciar: $_"
    }
}

# ============================================================================
# FUNCIÓN: Ver estado del servidor
# ============================================================================
function Ver-Estado {
    Print-Titulo "=== ESTADO DEL SERVIDOR FTP ==="
    Write-Host ""
    
    $sitio = Get-Website -Name "FTP_Server" -ErrorAction SilentlyContinue
    
    if ($null -eq $sitio) {
        Print-Error "El sitio FTP no existe"
        return
    }
    
    Write-Host "Estado del sitio: " -NoNewline
    if ($sitio.State -eq "Started") {
        Print-Completado "Activo"
    } else {
        Print-Error "Detenido"
    }
    
    Write-Host "Puerto: $($sitio.bindings.Collection.bindingInformation)"
    Write-Host "Ruta fisica: $($sitio.physicalPath)"
    
    Write-Host ""
    Print-Info "Conexiones FTP activas:"
    $conexiones = Get-NetTCPConnection -LocalPort 21 -State Established -ErrorAction SilentlyContinue
    if ($conexiones) {
        $conexiones | Format-Table LocalAddress, LocalPort, RemoteAddress, RemotePort, State
    } else {
        Write-Host "  No hay conexiones activas"
    }
    
    Write-Host ""
    $ip = (Get-NetIPAddress -InterfaceAlias $script:INTERFAZ_RED -AddressFamily IPv4 -ErrorAction SilentlyContinue).IPAddress
    if ($ip) {
        Print-Info "IP de la interfaz '$script:INTERFAZ_RED': $ip"
        Print-Info "Acceso FTP: ftp://$ip"
    }
}

# ============================================================================
# MAIN - Verificar administrador y procesar argumentos
# ============================================================================
Verificar-Admin

# Procesar argumentos
switch ($args[0]) {
    "-verify"  { Verificar-Instalacion }
    "-install" { Instalar-FTP }
    "-users"   { Gestionar-Usuarios }
    "-status"  { Ver-Estado }
    "-restart" { Reiniciar-FTP }
    "-list"    { Listar-Estructura }
    "-help"    { Ayuda }
    default    { Ayuda }
}
