# =============================================
#  windows-funciones_http.ps1  --  Funciones
#  Windows Server 2022 Core
# =============================================

$global:VERSION_ELEGIDA = ""
$global:PUERTO_ELEGIDO  = 80

# =============== MENSAJES ===============
function Write-Ok    { param($msg) Write-Host "[OK] $msg" }
function Write-Info  { param($msg) Write-Host "[INFO] $msg" }
function Write-Err   { param($msg) Write-Host "[ERROR] $msg" }
function Write-Title { param($msg) Write-Host "`n==== $msg ====`n" }

# =============== CHOCOLATEY ===============
function Asegurar-Chocolatey {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Info "Instalando Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = `
            [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
            'https://community.chocolatey.org/install.ps1')) *>&1 | Out-Null
        $env:PATH += ";$env:ALLUSERSPROFILE\chocolatey\bin"
        Write-Ok "Chocolatey instalado."
    } else {
        Write-Info "Chocolatey: ok."
    }
}

# =============== REFRESCAR PATH ===============
function Refrescar-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

# =============== BUSCAR RUTA NGINX ===============
function Obtener-Ruta-Nginx {
    # choco instala nginx como nginx-VERSION dentro de C:\tools
    $exe = Get-ChildItem "C:\tools" -Filter "nginx.exe" -Recurse `
        -ErrorAction SilentlyContinue -Depth 3 | Select-Object -First 1
    if ($exe) { return $exe.DirectoryName }

    foreach ($r in @("C:\nginx","C:\ProgramData\chocolatey\lib\nginx\tools\nginx")) {
        if (Test-Path "$r\nginx.exe") { return $r }
    }

    $exe = Get-ChildItem "C:\" -Filter "nginx.exe" -Recurse `
        -ErrorAction SilentlyContinue -Depth 5 | Select-Object -First 1
    if ($exe) { return $exe.DirectoryName }

    return $null
}

# =============== OBTENER VERSIONES CHOCO ===============
function Obtener-Versiones-Choco {
    param([string]$paquete)
    Asegurar-Chocolatey

    # choco search devuelve de mayor a menor, tomar las 5 mas recientes
    $versiones = choco search $paquete --exact --all-versions --limit-output 2>$null `
        | ForEach-Object {
            if ($_ -match '\|') { ($_ -split '\|')[1].Trim() }
        } `
        | Where-Object { $_ -match '^\d+\.\d+' } `
        | Select-Object -Unique `
        | Select-Object -First 5

    return $versiones
}

function Obtener-Versiones-IIS {
    $ver = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" `
        -ErrorAction SilentlyContinue).VersionString
    if ($ver) { return @($ver) }
    return @("10.0")
}

# =============== ELEGIR VERSION APACHE ===============
function Elegir-Version-Apache {
    param([string[]]$versiones)
    Clear-Host

    if ($versiones.Count -eq 0) {
        Write-Err "No se encontraron versiones para Apache."
        return $false
    }

    Write-Host ""
    Write-Host "=== Versiones disponibles: Apache2 ==="
    Write-Host ""

    # choco ya devuelve de mayor a menor: [0]=latest, [1]=estable, [2]=LTS
    $limite = [Math]::Min($versiones.Count, 3)
    for ($i = 0; $i -lt $limite; $i++) {
        $etiqueta = switch ($i) {
            0 { "  [Latest - Desarrollo]" }
            1 { "  [Estable anterior]"    }
            2 { "  [LTS]"                 }
        }
        Write-Host "  [$($i+1)] $($versiones[$i])$etiqueta"
    }
    Write-Host ""

    while ($true) {
        $sel = Read-Host "Elige una version [1-$limite]"
        $sel = $sel -replace '[^0-9]',''
        if ($sel -match '^\d+$' -and [int]$sel -ge 1 -and [int]$sel -le $limite) {
            $global:VERSION_ELEGIDA = $versiones[[int]$sel - 1]
            Write-Ok "Version elegida: $global:VERSION_ELEGIDA"
            return $true
        }
        Write-Err "Opcion invalida."
    }
}

# =============== ELEGIR VERSION NGINX ===============
function Elegir-Version-Nginx {
    param([string[]]$versiones)
    Clear-Host

    if ($versiones.Count -eq 0) {
        Write-Err "No se encontraron versiones para Nginx."
        return $false
    }

    # Separar mainline (menor impar) de stable (menor par)
    $mainline = $versiones | Where-Object {
        $p = $_ -split '\.'
        $p.Count -ge 2 -and ([int]$p[1] % 2 -ne 0)
    } | Select-Object -First 1

    $stable = $versiones | Where-Object {
        $p = $_ -split '\.'
        $p.Count -ge 2 -and ([int]$p[1] % 2 -eq 0)
    } | Select-Object -First 1

    if (-not $mainline) { $mainline = $versiones[0] }
    if (-not $stable)   { $stable   = if ($versiones.Count -ge 2) { $versiones[1] } else { $versiones[0] } }

    Write-Host ""
    Write-Host "=== Versiones disponibles: Nginx ==="
    Write-Host ""
    Write-Host "  [1] $mainline  [Mainline - Desarrollo]"
    Write-Host "  [2] $stable    [Stable - LTS]"
    Write-Host ""

    while ($true) {
        $sel = Read-Host "Elige una version [1-2]"
        $sel = $sel -replace '[^0-9]',''
        switch ($sel) {
            "1" { $global:VERSION_ELEGIDA = $mainline; Write-Ok "Version elegida: $mainline"; return $true }
            "2" { $global:VERSION_ELEGIDA = $stable;   Write-Ok "Version elegida: $stable";   return $true }
            default { Write-Err "Opcion invalida." }
        }
    }
}

# =============== ELEGIR VERSION IIS ===============
function Elegir-Version-IIS {
    param([string[]]$versiones)
    Clear-Host

    Write-Host ""
    Write-Host "=== Version disponible: IIS ==="
    Write-Host ""
    Write-Host "  [1] $($versiones[0])  [Segun version de Windows]"
    Write-Host ""

    $global:VERSION_ELEGIDA = $versiones[0]
    Write-Ok "Version: $global:VERSION_ELEGIDA"
    return $true
}

# =============== VALIDAR PUERTO ===============
function Validar-Puerto {
    param([int]$puerto)

    if ($puerto -ne 80 -and ($puerto -lt 1024 -or $puerto -gt 65535)) {
        Write-Err "Usa 80 o un puerto entre 1024 y 65535."
        return $false
    }
    foreach ($r in $global:PUERTOS_RESERVADOS) {
        if ($puerto -eq $r) {
            Write-Err "Puerto $puerto reservado para otro servicio."
            return $false
        }
    }
    $enUso = Get-NetTCPConnection -LocalPort $puerto -ErrorAction SilentlyContinue
    if ($enUso) {
        $proc = Get-Process -Id $enUso[0].OwningProcess -ErrorAction SilentlyContinue
        Write-Err "Puerto $puerto ocupado por: $($proc.ProcessName) (PID $($enUso[0].OwningProcess))"
        return $false
    }
    return $true
}

# =============== PEDIR PUERTO ===============
function Pedir-Puerto {
    Clear-Host
    Write-Host ""
    Write-Host "=== Configuracion de Puerto ==="
    Write-Host ""
    Write-Info "Puerto por defecto : 80"
    Write-Info "Otros comunes      : 8080, 8888"
    Write-Info "Bloqueados         : $($global:PUERTOS_RESERVADOS -join ', ')"
    Write-Host ""

    while ($true) {
        $inp = Read-Host "Ingresa el puerto [Enter = 80]"
        if ([string]::IsNullOrWhiteSpace($inp)) { $inp = "80" }
        $inp = $inp -replace '[^0-9]',''
        if ([string]::IsNullOrWhiteSpace($inp)) { Write-Err "Ingresa un numero."; continue }
        $puerto = [int]$inp
        if (Validar-Puerto $puerto) {
            $global:PUERTO_ELEGIDO = $puerto
            Write-Ok "Puerto $puerto aceptado."
            Start-Sleep -Seconds 1
            break
        }
    }
}

# =============== FIREWALL ===============
function Abrir-Puerto-Firewall {
    param([int]$puerto, [string]$nombre)
    # Eliminar regla anterior si existe
    Remove-NetFirewallRule -DisplayName "HTTP-$nombre-*" -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "HTTP-$nombre-$puerto" `
        -Direction Inbound -Protocol TCP -LocalPort $puerto `
        -Action Allow -Profile Any | Out-Null
    Write-Ok "Firewall: puerto $puerto abierto para $nombre."
}

# =============== INSTALAR IIS ===============
function Instalar-IIS {
    Write-Title "Instalando IIS..."

    $features = @(
        "Web-Server","Web-Common-Http","Web-Static-Content",
        "Web-Default-Doc","Web-Http-Errors","Web-Security",
        "Web-Filtering","Web-Http-Logging","Web-Stat-Compression"
    )
    foreach ($f in $features) {
        Install-WindowsFeature -Name $f -ErrorAction SilentlyContinue | Out-Null
    }
    Write-Ok "IIS instalado."

    $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
    & $appcmd set site "Default Web Site" /bindings:"http/*:$($global:PUERTO_ELEGIDO):" 2>&1 | Out-Null
    Write-Ok "Puerto configurado -> $global:PUERTO_ELEGIDO"

    # Seguridad via web.config (compatible con Core, sin WebAdministration)
    Set-Content -Path "$global:IIS_WEBROOT\web.config" -Encoding UTF8 -Value @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <security>
      <requestFiltering removeServerHeader="true">
        <verbs>
          <add verb="TRACE" allowed="false" />
          <add verb="TRACK" allowed="false" />
        </verbs>
      </requestFiltering>
    </security>
    <httpProtocol>
      <customHeaders>
        <remove name="X-Powered-By" />
        <add name="X-Frame-Options" value="SAMEORIGIN" />
        <add name="X-Content-Type-Options" value="nosniff" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
"@
    Write-Ok "Seguridad configurada."

    Set-Content -Path "$global:IIS_WEBROOT\index.html" -Encoding UTF8 -Force -Value @"
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>IIS</title></head>
<body>
<h1>Servidor: IIS</h1>
<p>Version: $($global:VERSION_ELEGIDA)</p>
<p>Puerto: $($global:PUERTO_ELEGIDO)</p>
</body>
</html>
"@
    Write-Ok "index.html creado."

    $acl  = Get-Acl $global:IIS_WEBROOT
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "IIS_IUSRS","ReadAndExecute","ContainerInherit,ObjectInherit","None","Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $global:IIS_WEBROOT $acl
    Write-Ok "Permisos aplicados -> IIS_IUSRS."

    Abrir-Puerto-Firewall $global:PUERTO_ELEGIDO "IIS"

    Start-Service W3SVC -ErrorAction SilentlyContinue
    Set-Service   W3SVC -StartupType Automatic
    Start-Sleep -Seconds 2

    if ((Get-Service W3SVC -ErrorAction SilentlyContinue).Status -eq "Running") {
        Write-Ok "IIS activo en puerto $global:PUERTO_ELEGIDO"
    } else {
        Write-Err "IIS no arranco. Revisa el Visor de Eventos."
    }
}

# =============== INSTALAR APACHE ===============
function Instalar-Apache-Win {
    Write-Title "Instalando Apache2 (Windows)..."

    Asegurar-Chocolatey
    Write-Info "Instalando Apache $global:VERSION_ELEGIDA en puerto $global:PUERTO_ELEGIDO via Chocolatey..."

    # Pasar el puerto directamente al instalador para evitar editar httpd.conf manualmente
    choco install apache-httpd `
        --version="$global:VERSION_ELEGIDA" `
        --params="`"/port:$global:PUERTO_ELEGIDO /installLocation:C:\Apache24`"" `
        --yes `
        --no-progress `
        --force 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Err "Fallo la instalacion de Apache. Codigo: $LASTEXITCODE"
        return
    }

    Refrescar-Path
    Write-Ok "Apache $global:VERSION_ELEGIDA instalado."

    # Apache queda en C:\Apache24 por el installLocation
    $apacheRoot = "C:\Apache24"
    $httpdConf  = "$apacheRoot\conf\httpd.conf"

    if (-not (Test-Path $httpdConf)) {
        Write-Err "No se encontro httpd.conf en $apacheRoot\conf"
        return
    }

    # Seguridad: agregar bloque si no existe ya
    $contenido = Get-Content $httpdConf -Raw
    if ($contenido -notmatch 'TAREA6-SECURITY') {
        Add-Content -Path $httpdConf -Value @"

# TAREA6-SECURITY-START
ServerTokens Prod
ServerSignature Off

<LimitExcept GET POST HEAD>
    Require all denied
</LimitExcept>

Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
# TAREA6-SECURITY-END
"@
        Write-Ok "Seguridad configurada en httpd.conf."
    } else {
        Write-Info "Seguridad ya configurada, omitiendo."
    }

    # index.html
    $htmlDir = "$apacheRoot\htdocs"
    New-Item -ItemType Directory -Force -Path $htmlDir | Out-Null
    Set-Content -Path "$htmlDir\index.html" -Encoding UTF8 -Force -Value @"
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>Apache2</title></head>
<body>
<h1>Servidor: Apache2</h1>
<p>Version: $($global:VERSION_ELEGIDA)</p>
<p>Puerto: $($global:PUERTO_ELEGIDO)</p>
</body>
</html>
"@
    Write-Ok "index.html creado."

    Abrir-Puerto-Firewall $global:PUERTO_ELEGIDO "Apache"

    # Arrancar servicio (choco ya lo registra)
    $svc = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^Apache" } | Select-Object -First 1

    if ($svc) {
        Start-Service $svc.Name -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        $svc = Get-Service $svc.Name -ErrorAction SilentlyContinue
        if ($svc.Status -eq "Running") {
            Write-Ok "Apache activo en puerto $global:PUERTO_ELEGIDO"
        } else {
            Write-Err "Apache no arranco. Revisa C:\Apache24\logs\error.log"
        }
    } else {
        # Si choco no registro el servicio, registrar manualmente
        $httpdExe = "$apacheRoot\bin\httpd.exe"
        if (Test-Path $httpdExe) {
            & $httpdExe -k install 2>&1 | Out-Null
            Start-Sleep -Seconds 1
            $svc = Get-Service -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "^Apache" } | Select-Object -First 1
            if ($svc) {
                Start-Service $svc.Name -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 3
                $svc = Get-Service $svc.Name -ErrorAction SilentlyContinue
                if ($svc.Status -eq "Running") {
                    Write-Ok "Apache activo en puerto $global:PUERTO_ELEGIDO"
                } else {
                    Write-Err "Apache no arranco. Revisa C:\Apache24\logs\error.log"
                }
            }
        } else {
            Write-Err "No se encontro httpd.exe en $apacheRoot\bin"
        }
    }
}

# =============== INSTALAR NGINX ===============
function Instalar-Nginx-Win {
    Write-Title "Instalando Nginx (Windows)..."

    Asegurar-Chocolatey
    Write-Info "Instalando Nginx $global:VERSION_ELEGIDA via Chocolatey..."
    choco install nginx --version="$global:VERSION_ELEGIDA" --yes --no-progress --force 2>&1 | Out-Null

    if ($LASTEXITCODE -ne 0) {
        Write-Err "Fallo la instalacion de Nginx. Codigo: $LASTEXITCODE"
        return
    }

    Refrescar-Path
    Write-Ok "Nginx instalado."

    # Instalar NSSM para registrar Nginx como servicio real de Windows
    if (-not (Get-Command nssm -ErrorAction SilentlyContinue)) {
        Write-Info "Instalando NSSM..."
        choco install nssm --yes --no-progress 2>&1 | Out-Null
        Refrescar-Path
    }

    $nginxRoot = Obtener-Ruta-Nginx
    if (-not $nginxRoot) {
        Write-Err "No se encontro nginx.exe tras la instalacion."
        return
    }
    Write-Info "Nginx encontrado en: $nginxRoot"

    # Configurar puerto en nginx.conf
    $nginxConf = "$nginxRoot\conf\nginx.conf"
    if (Test-Path $nginxConf) {
        $contenido = Get-Content $nginxConf -Raw
        # Reemplazar puerto en bloque server { listen X; }
        $contenido = $contenido -replace 'listen\s+\d+\s*;', "listen $global:PUERTO_ELEGIDO;"
        # server_tokens off: oculta version en headers
        if ($contenido -notmatch 'server_tokens') {
            $contenido = $contenido -replace '(http\s*\{)', "`$1`n    server_tokens off;"
        }
        # Headers de seguridad dentro del bloque server
        if ($contenido -notmatch 'X-Frame-Options') {
            $contenido = $contenido -replace '(server\s*\{)', "`$1`n        add_header X-Frame-Options SAMEORIGIN always;`n        add_header X-Content-Type-Options nosniff always;"
        }
        Set-Content $nginxConf $contenido -Encoding UTF8
        Write-Ok "Puerto y seguridad configurados en nginx.conf."
    } else {
        Write-Err "No se encontro nginx.conf en $nginxRoot\conf"
    }

    # index.html personalizado
    $htmlDir = "$nginxRoot\html"
    New-Item -ItemType Directory -Force -Path $htmlDir | Out-Null
    Set-Content -Path "$htmlDir\index.html" -Encoding UTF8 -Force -Value @"
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>Nginx</title></head>
<body>
<h1>Servidor: Nginx</h1>
<p>Version: $($global:VERSION_ELEGIDA)</p>
<p>Puerto: $($global:PUERTO_ELEGIDO)</p>
</body>
</html>
"@
    Write-Ok "index.html creado."

    Abrir-Puerto-Firewall $global:PUERTO_ELEGIDO "Nginx"

    # Registrar Nginx como servicio con NSSM (nombre incluye puerto para evitar conflictos)
    $serviceName = "nginx-$global:PUERTO_ELEGIDO"
    $nginxExe    = "$nginxRoot\nginx.exe"

    # Eliminar servicio anterior si existe
    $svcAnterior = Get-Service $serviceName -ErrorAction SilentlyContinue
    if ($svcAnterior) {
        Stop-Service $serviceName -Force -ErrorAction SilentlyContinue
        & nssm remove $serviceName confirm 2>&1 | Out-Null
    }

    & nssm install $serviceName $nginxExe 2>&1 | Out-Null
    & nssm set $serviceName AppDirectory $nginxRoot 2>&1 | Out-Null
    & nssm set $serviceName DisplayName "Nginx HTTP Server (puerto $global:PUERTO_ELEGIDO)" 2>&1 | Out-Null
    & nssm set $serviceName Start SERVICE_AUTO_START 2>&1 | Out-Null
    & nssm set $serviceName AppStdout "$nginxRoot\logs\service.log" 2>&1 | Out-Null
    & nssm set $serviceName AppStderr "$nginxRoot\logs\service-error.log" 2>&1 | Out-Null

    Start-Service $serviceName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    $svc = Get-Service $serviceName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Ok "Nginx activo en puerto $global:PUERTO_ELEGIDO (servicio: $serviceName)"
    } else {
        Write-Err "Nginx no arranco. Revisa $nginxRoot\logs\error.log"
        Write-Info "O inicia manualmente: nssm start $serviceName"
    }
}

# =============== MENU INSTALACION ===============
function Instalar-HTTP {
    Clear-Host
    Write-Host ""
    Write-Host "=== Instalacion de Servidor HTTP ==="
    Write-Host ""
    Write-Host "  [1] IIS (Internet Information Services)"
    Write-Host "  [2] Apache2"
    Write-Host "  [3] Nginx"
    Write-Host ""

    while ($true) {
        $opcion = Read-Host "Selecciona un servidor [1-3]"
        $opcion = $opcion -replace '[^0-9]',''
        if ($opcion -match '^[123]$') { break }
        Write-Err "Opcion invalida."
    }

    switch ($opcion) {
        "1" {
            $versiones = Obtener-Versiones-IIS
            if (-not (Elegir-Version-IIS $versiones)) { return }
            Pedir-Puerto
            Instalar-IIS
        }
        "2" {
            Write-Info "Consultando versiones de Apache..."
            $versiones = Obtener-Versiones-Choco "apache-httpd"
            if ($versiones.Count -eq 0) { $versiones = @("2.4.55","2.4.54","2.4.53") }
            if (-not (Elegir-Version-Apache $versiones)) { return }
            Pedir-Puerto
            Instalar-Apache-Win
        }
        "3" {
            Write-Info "Consultando versiones de Nginx..."
            $versiones = Obtener-Versiones-Choco "nginx"
            if ($versiones.Count -eq 0) { $versiones = @("1.29.5","1.26.2") }
            if (-not (Elegir-Version-Nginx $versiones)) { return }
            Pedir-Puerto
            Instalar-Nginx-Win
        }
    }
}

# =============== VERIFICAR ESTADO ===============
function Verificar-HTTP {
    Clear-Host
    Write-Host ""
    Write-Host "=== Estado de Servidores HTTP ==="
    Write-Host ""

    Write-Host -NoNewline "  IIS     : "
    $iis = Get-Service W3SVC -ErrorAction SilentlyContinue
    if ($iis) {
        $ver = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" `
            -ErrorAction SilentlyContinue).VersionString
        $puerto = & "$env:SystemRoot\system32\inetsrv\appcmd.exe" list site "Default Web Site" 2>$null `
            | Select-String ':(\d+):' `
            | ForEach-Object { $_.Matches[0].Groups[1].Value } `
            | Select-Object -First 1
        if ($iis.Status -eq "Running") {
            Write-Host "Instalado y activo -- version: $ver -- puerto: $puerto"
        } else {
            Write-Host "Instalado pero detenido -- version: $ver"
        }
    } else { Write-Host "No instalado" }

    Write-Host -NoNewline "  Apache2 : "
    $apache = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^Apache" } | Select-Object -First 1
    if ($apache) {
        $puerto = "?"
        if (Test-Path "C:\Apache24\conf\httpd.conf") {
            $puerto = Get-Content "C:\Apache24\conf\httpd.conf" |
                Select-String '^Listen\s+(\d+)' |
                ForEach-Object { $_.Matches[0].Groups[1].Value } |
                Select-Object -First 1
        }
        if ($apache.Status -eq "Running") {
            Write-Host "Instalado y activo -- puerto: $puerto"
        } else {
            Write-Host "Instalado pero detenido -- puerto: $puerto"
        }
    } else { Write-Host "No instalado" }

    Write-Host -NoNewline "  Nginx   : "
    $nginx = Get-Service -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^nginx" } | Select-Object -First 1
    if ($nginx) {
        $nginxRoot = Obtener-Ruta-Nginx
        $puerto = "?"
        if ($nginxRoot -and (Test-Path "$nginxRoot\conf\nginx.conf")) {
            $puerto = Get-Content "$nginxRoot\conf\nginx.conf" |
                Select-String 'listen\s+(\d+)' |
                ForEach-Object { $_.Matches[0].Groups[1].Value } |
                Select-Object -First 1
        }
        if ($nginx.Status -eq "Running") {
            Write-Host "Instalado y activo -- puerto: $puerto (servicio: $($nginx.Name))"
        } else {
            Write-Host "Instalado pero detenido -- puerto: $puerto"
        }
    } else { Write-Host "No instalado" }

    Write-Host ""
}

# =============== REVISAR CURL ===============
function Revisar-HTTP {
    Clear-Host
    Write-Host ""
    Write-Host "=== Revision de Servidores HTTP ==="
    Write-Host ""
    Write-Host "  [1] IIS"
    Write-Host "  [2] Apache2"
    Write-Host "  [3] Nginx"
    Write-Host "  [4] Todos"
    Write-Host ""

    while ($true) {
        $opcion = Read-Host "Selecciona [1-4]"
        $opcion = $opcion -replace '[^0-9]',''
        if ($opcion -match '^[1234]$') { break }
        Write-Err "Opcion invalida."
    }

    function Curl-Servidor {
        param([string]$nombre, [int]$puerto)
        Write-Host ""
        Write-Host "--- $nombre (puerto $puerto) ---"
        Write-Host "Headers:"
        try {
            $resp = Invoke-WebRequest -Uri "http://localhost:$puerto" `
                -Method Head -UseBasicParsing -ErrorAction Stop
            $resp.Headers.GetEnumerator() | ForEach-Object {
                Write-Host "$($_.Key): $($_.Value)"
            }
        } catch { Write-Err "No se pudo conectar a puerto $puerto" }
        Write-Host "Index:"
        try {
            $resp = Invoke-WebRequest -Uri "http://localhost:$puerto" `
                -UseBasicParsing -ErrorAction Stop
            Write-Host $resp.Content
        } catch { Write-Err "No se pudo obtener index de puerto $puerto" }
    }

    # Detectar puertos activos
    $puertoIIS = & "$env:SystemRoot\system32\inetsrv\appcmd.exe" list site "Default Web Site" 2>$null `
        | Select-String ':(\d+):' `
        | ForEach-Object { $_.Matches[0].Groups[1].Value } `
        | Select-Object -First 1

    $puertoApache = if (Test-Path "C:\Apache24\conf\httpd.conf") {
        Get-Content "C:\Apache24\conf\httpd.conf" |
            Select-String '^Listen\s+(\d+)' |
            ForEach-Object { $_.Matches[0].Groups[1].Value } |
            Select-Object -First 1
    } else { 80 }

    $nginxRoot   = Obtener-Ruta-Nginx
    $puertoNginx = if ($nginxRoot -and (Test-Path "$nginxRoot\conf\nginx.conf")) {
        Get-Content "$nginxRoot\conf\nginx.conf" |
            Select-String 'listen\s+(\d+)' |
            ForEach-Object { $_.Matches[0].Groups[1].Value } |
            Select-Object -First 1
    } else { 80 }

    switch ($opcion) {
        "1" { Curl-Servidor "IIS"    ([int]$puertoIIS)    }
        "2" { Curl-Servidor "Apache" ([int]$puertoApache) }
        "3" { Curl-Servidor "Nginx"  ([int]$puertoNginx)  }
        "4" {
            Curl-Servidor "IIS"    ([int]$puertoIIS)
            Curl-Servidor "Apache" ([int]$puertoApache)
            Curl-Servidor "Nginx"  ([int]$puertoNginx)
        }
    }
}
