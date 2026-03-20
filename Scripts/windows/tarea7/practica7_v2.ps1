# ============================================================================
# Practica 7 - Instalacion Hibrida con SSL/TLS (Windows)
# Combina: Descarga FTP + Instalacion + SSL
# ============================================================================
 
# Cargar funciones existentes
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. "$scriptDir\..\tarea6\windows-funciones_http.ps1"

# Variables globales
$FTP_SERVER = "192.168.100.139"
$FTP_USER = "ftprepo"
$FTP_PASS = "Repo123!"
$FTP_BASE_PATH = "/http/Windows"
$TMP_DIR = "$env:TEMP\practica7"
$SSL_DIR = "C:\SSL\practica7"
 
$SERVICIO_ACTUAL = ""
$FUENTE_INSTALACION = ""
$CONFIGURAR_SSL = $false
$PUERTO_ELEGIDO = 0
 
# ============================================================================
# FUNCION: Preparar entorno
# ============================================================================
function Preparar-Entorno {
    if (-not (Test-Path $TMP_DIR)) {
        New-Item -ItemType Directory -Path $TMP_DIR -Force | Out-Null
    }
    
    if (-not (Test-Path $SSL_DIR)) {
        New-Item -ItemType Directory -Path "$SSL_DIR\certs" -Force | Out-Null
        New-Item -ItemType Directory -Path "$SSL_DIR\private" -Force | Out-Null
    }
    
    # Verificar OpenSSL
    if (-not (Get-Command openssl -ErrorAction SilentlyContinue)) {
        Write-Info "Instalando OpenSSL..."
        Asegurar-Chocolatey
        choco install openssl --yes --no-progress 2>&1 | Out-Null
        Refrescar-Path
    }
}
 
# ============================================================================
# FUNCION: Menu principal
# ============================================================================
function Menu-Principal {
    Clear-Host
    Write-Title "========================================================"
    Write-Title "  Practica 7 - Instalacion Hibrida con SSL/TLS"
    Write-Title "========================================================"
    Write-Host ""
    Write-Info "Seleccione el servicio a instalar:"
    Write-Host ""
    Write-Host "  [1] IIS"
    Write-Host "  [2] Apache HTTP Server"
    Write-Host "  [3] Nginx"
    Write-Host "  [0] Salir"
    Write-Host ""
    
    do {
        $opcion = Read-Host "Opcion"
    } while ($opcion -notmatch '^[0-3]$')
    
    switch ($opcion) {
        "1" { $script:SERVICIO_ACTUAL = "IIS" }
        "2" { $script:SERVICIO_ACTUAL = "Apache" }
        "3" { $script:SERVICIO_ACTUAL = "Nginx" }
        "0" { exit 0 }
    }
}
 
# ============================================================================
# FUNCION: Seleccionar fuente
# ============================================================================
function Seleccionar-Fuente {
    Write-Host ""
    Write-Info "Desde donde desea instalar $SERVICIO_ACTUAL?"
    Write-Host ""
    Write-Host "  [W] WEB - Chocolatey/Repositorios oficiales"
    Write-Host "  [F] FTP - Repositorio privado"
    Write-Host ""
    
    do {
        $fuente = Read-Host "Seleccione [W/F]"
    } while ($fuente -notmatch '^[WwFf]$')
    
    $script:FUENTE_INSTALACION = if ($fuente -match '^[Ww]$') { "WEB" } else { "FTP" }
}
 
# ============================================================================
# FUNCION: Descargar desde FTP
# ============================================================================
function Descargar-DesdeFTP {
    param([string]$servicio)
    
    Write-Title "Conectando al Repositorio FTP"
    
    $ftpPath = "$FTP_BASE_PATH/$servicio/"
    
    try {
        Write-Info "Usando lista predefinida de archivos..."
        
        # Lista de archivos disponibles por servicio
        $archivosDisponibles = switch ($servicio) {
            "Nginx" {
                @(
                    "nginx-1.22.1.zip",
                    "nginx-1.24.0.zip"
                )
            }
            "Apache" {
                @(
                    "apache-httpd-2.4.58-win64-VS17.zip",
                    "apache-httpd-2.4.62-win64-VS17.zip"
                )
            }
            "IIS" {
                @(
                    "iis-config.msi"
                )
            }
            default { @() }
        }
        
        if ($archivosDisponibles.Count -eq 0) {
            Write-Err "No hay archivos disponibles para $servicio"
            return $false
        }
        
        Write-Ok "Versiones disponibles:"
        Write-Host ""
        
        for ($i = 0; $i -lt $archivosDisponibles.Count; $i++) {
            Write-Host "  [$($i+1)] $($archivosDisponibles[$i])"
        }
        
        Write-Host ""
        do {
            $seleccion = Read-Host "Seleccione version [1-$($archivosDisponibles.Count)]"
        } while ($seleccion -notmatch '^\d+$' -or [int]$seleccion -lt 1 -or [int]$seleccion -gt $archivosDisponibles.Count)
        
        $archivoElegido = $archivosDisponibles[[int]$seleccion - 1]
        Write-Ok "Seleccionado: $archivoElegido"
        
        # Descargar archivo con WebClient
        $localFile = Join-Path $TMP_DIR $archivoElegido
        $downloadUrl = "ftp://$FTP_USER`:$FTP_PASS@$FTP_SERVER$ftpPath$archivoElegido"
        
        Write-Info "Descargando $archivoElegido..."
        
        $webClient = New-Object System.Net.WebClient
        $webClient.Credentials = New-Object System.Net.NetworkCredential($FTP_USER, $FTP_PASS)
        
        # Event handler para progreso
        $global:downloadComplete = $false
        Register-ObjectEvent -InputObject $webClient -EventName DownloadProgressChanged -SourceIdentifier WebClient.DownloadProgressChanged -Action {
            Write-Progress -Activity "Descargando archivo" -Status "$($EventArgs.ProgressPercentage)% completado" -PercentComplete $EventArgs.ProgressPercentage
        } | Out-Null
        
        Register-ObjectEvent -InputObject $webClient -EventName DownloadFileCompleted -SourceIdentifier WebClient.DownloadFileCompleted -Action {
            $global:downloadComplete = $true
        } | Out-Null
        
        $webClient.DownloadFileAsync($downloadUrl, $localFile)
        
        # Esperar hasta que termine
        while (-not $global:downloadComplete) {
            Start-Sleep -Milliseconds 100
        }
        
        Unregister-Event -SourceIdentifier WebClient.DownloadProgressChanged -ErrorAction SilentlyContinue
        Unregister-Event -SourceIdentifier WebClient.DownloadFileCompleted -ErrorAction SilentlyContinue
        $webClient.Dispose()
        
        Write-Progress -Activity "Descargando archivo" -Completed
        
        if (-not (Test-Path $localFile)) {
            Write-Err "Error: archivo no descargado"
            return $false
        }
        
        $fileSize = (Get-Item $localFile).Length
        Write-Ok "Descarga completa ($([math]::Round($fileSize/1MB, 2)) MB)"
        
        # Intentar descargar hash (opcional)
        $hashUrl = "ftp://$FTP_USER`:$FTP_PASS@$FTP_SERVER$ftpPath$archivoElegido.sha256"
        $hashFile = "$localFile.sha256"
        
        Write-Info "Intentando descargar hash SHA256..."
        
        try {
            $hashClient = New-Object System.Net.WebClient
            $hashClient.Credentials = New-Object System.Net.NetworkCredential($FTP_USER, $FTP_PASS)
            $hashClient.DownloadFile($hashUrl, $hashFile)
            $hashClient.Dispose()
            
            # Verificar hash
            Write-Title "Verificando Integridad"
            
            $hashCalc = (Get-FileHash -Path $localFile -Algorithm SHA256).Hash.ToLower()
            $hashEsp = (Get-Content $hashFile -Raw).Split()[0].Trim().ToLower()
            
            Write-Info "Hash calculado: $hashCalc"
            Write-Info "Hash esperado:  $hashEsp"
            
            if ($hashCalc -eq $hashEsp) {
                Write-Ok "Archivo integro (hash verificado)"
            } else {
                Write-Warn "Hash no coincide, pero continuando..."
            }
        } catch {
            Write-Warn "No se pudo descargar archivo de hash"
            Write-Info "Continuando sin verificacion de hash..."
            Write-Info "Hash SHA256 del archivo descargado:"
            $hashCalc = (Get-FileHash -Path $localFile -Algorithm SHA256).Hash.ToLower()
            Write-Info "  $hashCalc"
        }
        
        return $true
        
    } catch {
        Write-Err "Error al descargar desde FTP: $($_.Exception.Message)"
        if ($_.Exception.InnerException) {
            Write-Err "Detalles: $($_.Exception.InnerException.Message)"
        }
        return $false
    }
}

# ============================================================================
# FUNCION: Generar certificado SSL
# ============================================================================
function Generar-CertificadoSSL {
    param([string]$servicio)
    
    $certFile = "$SSL_DIR\certs\$($servicio.ToLower()).crt"
    $keyFile = "$SSL_DIR\private\$($servicio.ToLower()).key"
    
    Write-Title "Generando Certificado SSL Autofirmado"
    
    # Verificar que OpenSSL está disponible
    $opensslPath = (Get-Command openssl -ErrorAction SilentlyContinue).Source
    
    if (-not $opensslPath) {
        Write-Err "OpenSSL no encontrado en PATH"
        Write-Info "Instalando OpenSSL..."
        
        Asegurar-Chocolatey
        choco install openssl -y --force
        
        # Refrescar PATH
        Refrescar-Path
        
        $opensslPath = (Get-Command openssl -ErrorAction SilentlyContinue).Source
        
        if (-not $opensslPath) {
            Write-Err "No se pudo instalar OpenSSL"
            return $false
        }
    }
    
    Write-Info "Usando OpenSSL: $opensslPath"
    
    # Generar certificado
    try {
        $process = Start-Process -FilePath "openssl" -ArgumentList @(
            "req", "-x509", "-nodes", "-days", "365",
            "-newkey", "rsa:2048",
            "-keyout", "`"$keyFile`"",
            "-out", "`"$certFile`"",
            "-subj", "/C=MX/ST=BajaCalifornia/L=Tijuana/O=Reprobados/OU=IT/CN=www.reprobados.com"
        ) -NoNewWindow -Wait -PassThru
        
        if ($process.ExitCode -ne 0) {
            Write-Err "OpenSSL fallo con codigo: $($process.ExitCode)"
            return $false
        }
    } catch {
        Write-Err "Error ejecutando OpenSSL: $_"
        return $false
    }
    
    Start-Sleep -Seconds 1
    
    if ((Test-Path $certFile) -and (Test-Path $keyFile)) {
        Write-Ok "Certificado SSL generado"
        Write-Info "  Certificado: $certFile"
        Write-Info "  Clave: $keyFile"
        return $true
    } else {
        Write-Err "Archivos de certificado no encontrados"
        Write-Info "Esperados:"
        Write-Info "  $certFile"
        Write-Info "  $keyFile"
        return $false
    }
}
 
# ============================================================================
# FUNCION: Configurar IIS con SSL
# ============================================================================
function Configurar-IIS-SSL {
    param([int]$puerto)
    
    Write-Title "Configurando IIS con HTTPS"
    
    if (-not (Generar-CertificadoSSL -servicio "IIS")) {
        return
    }
    
    $certFile = "$SSL_DIR\certs\iis.crt"
    $keyFile = "$SSL_DIR\private\iis.key"
    
    # Convertir certificado a PFX
    $pfxFile = "$SSL_DIR\certs\iis.pfx"
    $pfxPass = "reprobados123"
    
    Write-Info "Creando certificado PFX..."
    $opensslCmd = "openssl pkcs12 -export " +
                  "-out `"$pfxFile`" " +
                  "-inkey `"$keyFile`" " +
                  "-in `"$certFile`" " +
                  "-passout pass:$pfxPass"
    
    Invoke-Expression $opensslCmd 2>&1 | Out-Null
    
    # Importar certificado a Windows
    Write-Info "Importando certificado al almacen de Windows..."
    $securePass = ConvertTo-SecureString -String $pfxPass -Force -AsPlainText
    $cert = Import-PfxCertificate -FilePath $pfxFile -CertStoreLocation Cert:\LocalMachine\My -Password $securePass
    
    # Crear binding HTTPS en IIS
    Write-Info "Configurando binding HTTPS en IIS..."
    
    Import-Module WebAdministration
    
    # Eliminar binding HTTP si existe
    $existingBinding = Get-WebBinding -Name "Default Web Site" -Port $puerto -Protocol "http" -ErrorAction SilentlyContinue
    if ($existingBinding) {
        Remove-WebBinding -Name "Default Web Site" -Port $puerto -Protocol "http"
    }
    
    # Agregar binding HTTPS
    New-WebBinding -Name "Default Web Site" -Protocol "https" -Port $puerto -SslFlags 0
    
    # Asignar certificado al binding
    $binding = Get-WebBinding -Name "Default Web Site" -Port $puerto -Protocol "https"
    $binding.AddSslCertificate($cert.Thumbprint, "my")
    
    # Configurar firewall
    $ruleName = "IIS-HTTPS-$puerto"
    $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    if ($existingRule) {
        Remove-NetFirewallRule -DisplayName $ruleName
    }
    New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Protocol TCP -LocalPort $puerto -Action Allow | Out-Null
    
    Write-Ok "IIS configurado con HTTPS en puerto $puerto"
}
 
# ============================================================================
# FUNCION: Configurar Apache con SSL
# ============================================================================
function Configurar-Apache-SSL {
    param([int]$puerto, [string]$apacheRoot)
    
    Write-Title "Configurando Apache con HTTPS"
    
    if (-not (Generar-CertificadoSSL -servicio "Apache")) {
        return
    }
    
    $certFile = "$SSL_DIR\certs\apache.crt"
    $keyFile = "$SSL_DIR\private\apache.key"
    
    $httpdConf = "$apacheRoot\conf\httpd.conf"
    $sslConf = "$apacheRoot\conf\extra\httpd-ssl.conf"
    
    # Habilitar modulos SSL
    $conf = Get-Content $httpdConf -Raw
    $conf = $conf -replace '#LoadModule ssl_module', 'LoadModule ssl_module'
    $conf = $conf -replace '#LoadModule socache_shmcb_module', 'LoadModule socache_shmcb_module'
    $conf = $conf -replace '#Include conf/extra/httpd-ssl.conf', 'Include conf/extra/httpd-ssl.conf'
    Set-Content $httpdConf $conf -Encoding UTF8
    
    # Configurar SSL
    $certFileEscaped = $certFile -replace '\\', '/'
    $keyFileEscaped = $keyFile -replace '\\', '/'
    $htdocsEscaped = "$apacheRoot\htdocs" -replace '\\', '/'
    
    $sslConfig = @"
Listen $puerto
 
<VirtualHost *:$puerto>
    ServerName www.reprobados.com
    DocumentRoot "$htdocsEscaped"
    
    SSLEngine on
    SSLCertificateFile "$certFileEscaped"
    SSLCertificateKeyFile "$keyFileEscaped"
    
    <Directory "$htdocsEscaped">
        Options -Indexes -FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
 
SSLCipherSuite HIGH:MEDIUM:!MD5:!RC4
SSLProtocol all -SSLv3 -TLSv1 -TLSv1.1
SSLSessionCache "shmcb:$apacheRoot/logs/ssl_scache(512000)"
SSLSessionCacheTimeout 300
"@
    
    Set-Content $sslConf $sslConfig -Encoding UTF8
    
    Write-Ok "Apache configurado con HTTPS en puerto $puerto"
}
 
# ============================================================================
# FUNCION: Configurar Nginx con SSL
# ============================================================================
function Configurar-Nginx-SSL {
    param([int]$puerto, [string]$nginxRoot)
    
    Write-Title "Configurando Nginx con HTTPS"
    
    if (-not (Generar-CertificadoSSL -servicio "Nginx")) {
        return
    }
    
    $certFile = "$SSL_DIR\certs\nginx.crt" -replace '\\', '/'
    $keyFile = "$SSL_DIR\private\nginx.key" -replace '\\', '/'
    
    $nginxConf = "$nginxRoot\conf\nginx.conf"
    
    # Crear configuracion SSL
    $sslConfig = @"
worker_processes 1;
 
events {
    worker_connections 1024;
}
 
http {
    include       mime.types;
    default_type  application/octet-stream;
    
    server_tokens off;
    
    sendfile        on;
    keepalive_timeout  65;
    
    server {
        listen       $puerto ssl;
        server_name  www.reprobados.com;
        
        ssl_certificate      $certFile;
        ssl_certificate_key  $keyFile;
        
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        
        location / {
            root   html;
            index  index.html;
        }
    }
}
"@
    
    Set-Content $nginxConf $sslConfig -Encoding UTF8
    
    Write-Ok "Nginx configurado con HTTPS en puerto $puerto"
}
 
# ============================================================================
# MAIN
# ============================================================================
 
# Verificar privilegios de administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "Este script debe ejecutarse como Administrador"
    exit 1
}
 
Preparar-Entorno
Menu-Principal
Seleccionar-Fuente
 
# Preguntar por SSL
Write-Host ""
$sslResp = Read-Host "Desea activar SSL/TLS? [S/N]"
$script:CONFIGURAR_SSL = $sslResp -match '^[SsYy]'
 
# Si elige FTP, descargar primero
if ($FUENTE_INSTALACION -eq "FTP") {
    if (-not (Descargar-DesdeFTP -servicio $SERVICIO_ACTUAL)) {
        exit 1
    }
}
 
# Pedir puerto
$script:PUERTO_ELEGIDO = pedirPuerto -default 80
 
# Instalar servicio
switch ($SERVICIO_ACTUAL) {
    "IIS" {
        instalarIIS -puerto $PUERTO_ELEGIDO
        
        if ($CONFIGURAR_SSL) {
            Configurar-IIS-SSL -puerto $PUERTO_ELEGIDO
            Restart-Service W3SVC
        }
    }
    
    "Apache" {
        instalarApache -puerto $PUERTO_ELEGIDO
        
        if ($CONFIGURAR_SSL) {
            # Encontrar Apache root
            $posibles = @("C:\Apache24","$env:APPDATA\Apache24","$env:LOCALAPPDATA\Apache24")
            $apacheRoot = $posibles | Where-Object { Test-Path "$_\bin\httpd.exe" } | Select-Object -First 1
            
            if ($apacheRoot) {
                Configurar-Apache-SSL -puerto $PUERTO_ELEGIDO -apacheRoot $apacheRoot
                
                # Reiniciar Apache
                $svc = Get-Service | Where-Object { $_.Name -match "^Apache" } | Select-Object -First 1
                if ($svc) {
                    Restart-Service $svc.Name
                }
            }
        }
    }
    
    "Nginx" {
        instalarNginx -puerto $PUERTO_ELEGIDO
        
        if ($CONFIGURAR_SSL) {
            # Buscar Nginx root de forma más exhaustiva
            $nginxRoot = $null
            
            # Opción 1: Buscar en Chocolatey
            $chocoPath = "C:\ProgramData\chocolatey\lib\nginx\tools"
            if (Test-Path $chocoPath) {
                # Buscar subdirectorios nginx-*
                $nginxDirs = Get-ChildItem -Path $chocoPath -Directory | Where-Object { $_.Name -match '^nginx-' }
                if ($nginxDirs) {
                    $nginxRoot = $nginxDirs[0].FullName
                    Write-Info "Nginx encontrado en: $nginxRoot"
                }
            }
            
            # Opción 2: Buscar en C:\tools
            if (-not $nginxRoot) {
                $toolsPath = "C:\tools\nginx"
                if (Test-Path "$toolsPath\nginx.exe") {
                    $nginxRoot = $toolsPath
                }
            }
            
            # Opción 3: Buscar nginx.exe en todo el sistema
            if (-not $nginxRoot) {
                Write-Info "Buscando nginx.exe en el sistema..."
                $nginxExe = Get-ChildItem -Path "C:\" -Filter "nginx.exe" -Recurse -ErrorAction SilentlyContinue -Depth 5 | Select-Object -First 1
                if ($nginxExe) {
                    $nginxRoot = $nginxExe.DirectoryName
                    Write-Info "Nginx encontrado en: $nginxRoot"
                }
            }
            
            if ($nginxRoot -and (Test-Path "$nginxRoot\nginx.exe")) {
                Write-Ok "Configurando SSL en: $nginxRoot"
                Configurar-Nginx-SSL -puerto $PUERTO_ELEGIDO -nginxRoot $nginxRoot
                
                # Detener Nginx si está corriendo
                Get-Process nginx -ErrorAction SilentlyContinue | Stop-Process -Force
                Start-Sleep -Seconds 2
                
                # Iniciar Nginx con la nueva configuración
                Write-Info "Iniciando Nginx..."
                Start-Process -FilePath "$nginxRoot\nginx.exe" -WorkingDirectory $nginxRoot -WindowStyle Hidden
                
                Start-Sleep -Seconds 3
                
                # Verificar que está corriendo
                $nginxProcess = Get-Process nginx -ErrorAction SilentlyContinue
                if ($nginxProcess) {
                    Write-Ok "Nginx iniciado correctamente"
                    
                    # Verificar puerto
                    $listening = Get-NetTCPConnection -LocalPort $PUERTO_ELEGIDO -State Listen -ErrorAction SilentlyContinue
                    if ($listening) {
                        Write-Ok "Nginx escuchando en puerto $PUERTO_ELEGIDO"
                    } else {
                        Write-Warn "Nginx corriendo pero no escucha en puerto $PUERTO_ELEGIDO"
                        Write-Info "Ver logs: $nginxRoot\logs\error.log"
                    }
                } else {
                    Write-Err "Nginx no inicio correctamente"
                    Write-Info "Ver logs: $nginxRoot\logs\error.log"
                }
            } else {
                Write-Err "No se encontro la instalacion de Nginx"
            }
        }
    }
}
 
# Resumen final
$ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch "Loopback" } | Select-Object -First 1).IPAddress
 
Write-Host ""
Write-Ok "========================================================"
Write-Ok "  Instalacion Completada"
Write-Ok "========================================================"
Write-Host ""
 
if ($CONFIGURAR_SSL) {
    Write-Info "Servicio: $SERVICIO_ACTUAL"
    Write-Info "URL: https://$ip`:$PUERTO_ELEGIDO"
    Write-Info "Certificados en: $SSL_DIR"
} else {
    Write-Info "Servicio: $SERVICIO_ACTUAL"
    Write-Info "URL: http://$ip`:$PUERTO_ELEGIDO"
}
 
Write-Host ""