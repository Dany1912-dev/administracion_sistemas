. "$PSScriptRoot\..\lib\utils.ps1"

# ---------- Funciones de validacion especificas de DHCP ----------

function validar_Mascara {
    param([string]$masc)

    $mascarasValidas = @(
        "255.0.0.0",       "255.128.0.0",    "255.192.0.0",    "255.224.0.0",
        "255.240.0.0",     "255.248.0.0",    "255.252.0.0",    "255.254.0.0",
        "255.255.0.0",     "255.255.128.0",  "255.255.192.0",  "255.255.224.0",
        "255.255.240.0",   "255.255.248.0",  "255.255.252.0",  "255.255.254.0",
        "255.255.255.0",   "255.255.255.128","255.255.255.192","255.255.255.224",
        "255.255.255.240", "255.255.255.248","255.255.255.252"
    )

    if ($mascarasValidas -contains $masc) {
        return $true
    }

    Write-Host "Mascara invalida" -ForegroundColor $rojo
    return $false
}

function calcular_Rango {
    param([string]$ip1, [string]$ip2)

    $o1 = $ip1 -split '\.'
    $o2 = $ip2 -split '\.'

    $n1 = ([int]$o1[0] * 16777216) + ([int]$o1[1] * 65536) + ([int]$o1[2] * 256) + [int]$o1[3]
    $n2 = ([int]$o2[0] * 16777216) + ([int]$o2[1] * 65536) + ([int]$o2[2] * 256) + [int]$o2[3]

    return [Math]::Abs($n2 - $n1)
}

function calcular_Mascara {
    param([string]$ipIni, [string]$ipFin)

    $rango = calcular_Rango -ip1 $ipIni -ip2 $ipFin

    if     ($rango -le 254)   { return "255.255.255.0"   }
    elseif ($rango -le 510)   { return "255.255.254.0"   }
    elseif ($rango -le 1022)  { return "255.255.252.0"   }
    elseif ($rango -le 2046)  { return "255.255.248.0"   }
    elseif ($rango -le 4094)  { return "255.255.240.0"   }
    elseif ($rango -le 8190)  { return "255.255.224.0"   }
    elseif ($rango -le 16382) { return "255.255.192.0"   }
    elseif ($rango -le 32766) { return "255.255.128.0"   }
    elseif ($rango -le 65534) { return "255.255.0.0"     }
    else                      { return "255.0.0.0"       }
}

function calcular_Bits {
    param([string]$masc)

    $bits = 0
    foreach ($o in ($masc -split '\.')) {
        $n = [int]$o
        while ($n -gt 0) {
            if ($n -band 1) { $bits++ }
            $n = $n -shr 1
        }
    }
    return $bits
}

function validar_IPMascara {
    param([string]$ipIni, [string]$ipFin, [string]$masc)

    $oIni  = $ipIni -split '\.'
    $oFin  = $ipFin -split '\.'
    $oMasc = $masc  -split '\.'

    $redIni = @()
    $redFin = @()

    for ($i = 0; $i -lt 4; $i++) {
        $redIni += [int]$oIni[$i] -band [int]$oMasc[$i]
        $redFin += [int]$oFin[$i] -band [int]$oMasc[$i]
    }

    if (($redIni -join '.') -eq ($redFin -join '.')) {
        return $true
    }

    Write-Host "Las IPs no pertenecen a la misma red con esa mascara" -ForegroundColor $rojo
    return $false
}

# ---------- Funciones principales ----------

function configurar_IP_Estatica {
    param([string]$ipServidor, [string]$mascara, [string]$gateway)

    Write-Host "`n=== Configurando IP Estatica del Servidor ===" -ForegroundColor $amarillo
    Write-Host "IP a asignar: $ipServidor" -ForegroundColor $verde

    Write-Host "`nInterfaces disponibles:" -ForegroundColor $amarillo
    Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object Name, InterfaceDescription | Format-Table -AutoSize

    $interfaz = ""
    do {
        $interfaz = Read-Host "Nombre de la interfaz a usar"
        if (-not (Get-NetAdapter -Name $interfaz -ErrorAction SilentlyContinue)) {
            Write-Host "Interfaz no encontrada, intente de nuevo" -ForegroundColor $rojo
            $interfaz = ""
        }
    } while ($interfaz -eq "")

    $ifIndex   = (Get-NetAdapter -Name $interfaz).ifIndex
    $prefixLen = calcular_Bits -masc $mascara

    Write-Host "Eliminando configuracion IP anterior..." -ForegroundColor $amarillo
    Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Remove-NetIPAddress -Confirm:$false -ErrorAction SilentlyContinue
    Get-NetRoute -InterfaceIndex $ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Remove-NetRoute -Confirm:$false -ErrorAction SilentlyContinue

    try {
        New-NetIPAddress `
            -InterfaceIndex $ifIndex `
            -IPAddress      $ipServidor `
            -PrefixLength   $prefixLen `
            -AddressFamily  IPv4 `
            -ErrorAction    Stop | Out-Null
        Write-Host "IP $ipServidor/$prefixLen asignada correctamente" -ForegroundColor $verde
    }
    catch {
        Write-Host "Error al asignar IP estatica: $_" -ForegroundColor $rojo
        return $false
    }

    if ($gateway -ne "") {
        try {
            New-NetRoute `
                -InterfaceIndex    $ifIndex `
                -DestinationPrefix "0.0.0.0/0" `
                -NextHop           $gateway `
                -ErrorAction       Stop | Out-Null
            Write-Host "Gateway $gateway configurado" -ForegroundColor $verde
        }
        catch {
            Write-Host "Advertencia: no se pudo configurar el gateway: $_" -ForegroundColor $amarillo
        }
    }

    Start-Sleep -Seconds 1
    $verificacion = Get-NetIPAddress -InterfaceIndex $ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                    Where-Object { $_.IPAddress -eq $ipServidor }

    if ($verificacion) {
        Write-Host "Verificacion exitosa - IP $ipServidor activa en $interfaz" -ForegroundColor $verde
        return $true
    }
    else {
        Write-Host "Advertencia: no se pudo verificar la IP asignada" -ForegroundColor $amarillo
        return $false
    }
}

function monitorear_Clientes {
    Write-Host "`n=== Monitoreo de Clientes DHCP ===" -ForegroundColor $amarillo

    if ((Get-Service DHCPServer -ErrorAction SilentlyContinue).Status -ne "Running") {
        Write-Host "El servicio DHCP no esta activo" -ForegroundColor $rojo
        return
    }

    Write-Host ""
    Write-Host "1. Ver todos los leases"       -ForegroundColor $amarillo
    Write-Host "2. Ver solo leases activos"    -ForegroundColor $amarillo
    Write-Host "3. Ver estadisticas"           -ForegroundColor $amarillo
    Write-Host "4. Exportar reporte a archivo" -ForegroundColor $amarillo
    Write-Host ""

    $opc = Read-Host "Opcion"

    switch ($opc) {
        "1" {
            Write-Host "`n=== Todos los Leases ===" -ForegroundColor $azul
            $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
            if (-not $scopes) { Write-Host "No hay scopes configurados" -ForegroundColor $amarillo; return }
            foreach ($scope in $scopes) {
                Write-Host "`nScope: $($scope.Name) - $($scope.ScopeId)" -ForegroundColor $verde
                Get-DhcpServerv4Lease -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue |
                    Select-Object IPAddress, ClientId, HostName, LeaseExpiryTime, AddressState |
                    Format-Table -AutoSize
            }
        }
        "2" {
            Write-Host "`n=== Leases Activos ===" -ForegroundColor $azul
            $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
            if (-not $scopes) { Write-Host "No hay scopes configurados" -ForegroundColor $amarillo; return }
            foreach ($scope in $scopes) {
                Write-Host "`nScope: $($scope.Name) - $($scope.ScopeId)" -ForegroundColor $verde
                Get-DhcpServerv4Lease -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue |
                    Where-Object { $_.AddressState -eq "Active" } |
                    Select-Object IPAddress, ClientId, HostName, LeaseExpiryTime |
                    Format-Table -AutoSize
            }
        }
        "3" {
            Write-Host "`n=== Estadisticas ===" -ForegroundColor $azul
            $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
            if (-not $scopes) { Write-Host "No hay scopes configurados" -ForegroundColor $amarillo; return }

            $totalLeases  = 0
            $activosTotal = 0

            foreach ($scope in $scopes) {
                $leases  = Get-DhcpServerv4Lease -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
                $activos = $leases | Where-Object { $_.AddressState -eq "Active" }
                $cTotal  = ($leases  | Measure-Object).Count
                $cActivo = ($activos | Measure-Object).Count

                $totalLeases  += $cTotal
                $activosTotal += $cActivo

                Write-Host "`nScope: $($scope.Name) ($($scope.ScopeId))" -ForegroundColor $verde
                Write-Host "  Rango  : $($scope.StartRange) - $($scope.EndRange)"
                Write-Host "  Leases : $cTotal"
                Write-Host "  Activos: $cActivo"
            }

            Write-Host "`nTotal leases  : $totalLeases"  -ForegroundColor $amarillo
            Write-Host "Total activos : $activosTotal"   -ForegroundColor $amarillo
            Write-Host "`nEstado del servicio:" -ForegroundColor $amarillo
            Get-Service DHCPServer | Select-Object Name, Status | Format-Table -AutoSize
        }
        "4" {
            $archivo = "reporte_dhcp_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"
            $scopes  = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
            if (-not $scopes) { Write-Host "No hay scopes configurados" -ForegroundColor $amarillo; return }

            $lineas = @()
            $lineas += "REPORTE DHCP - $(Get-Date)"
            $lineas += "=" * 60

            foreach ($scope in $scopes) {
                $leases  = Get-DhcpServerv4Lease -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
                $activos = $leases | Where-Object { $_.AddressState -eq "Active" }

                $lineas += ""
                $lineas += "Scope: $($scope.Name) - $($scope.ScopeId)"
                $lineas += "Rango: $($scope.StartRange) - $($scope.EndRange)"
                $lineas += "-" * 60
                $lineas += "{0,-17}{1,-18}{2,-17}{3}" -f "IP", "MAC", "Hostname", "Expira"
                $lineas += "-" * 60

                foreach ($lease in $activos) {
                    $lineas += "{0,-17}{1,-18}{2,-17}{3}" -f `
                        $lease.IPAddress, $lease.ClientId, $lease.HostName, $lease.LeaseExpiryTime
                }

                $lineas += ""
                $lineas += "Total  : $(($leases  | Measure-Object).Count)"
                $lineas += "Activos: $(($activos | Measure-Object).Count)"
            }

            $lineas | Out-File -FilePath $archivo -Encoding UTF8
            Write-Host "Reporte guardado en: $archivo" -ForegroundColor $verde
            Get-Content $archivo
        }
        default {
            Write-Host "Opcion invalida" -ForegroundColor $rojo
        }
    }
}

function configuracionDHCP {
    Write-Host "`n=== Configuracion de DHCP ===" -ForegroundColor $amarillo
    Write-Host "`nConfiguracion Dinamica`n" -ForegroundColor $azul

    $scope = Read-Host "Nombre descriptivo del Ambito"

    # Mascara opcional
    $usoMas     = $false
    $mascara    = ""
    $mascValida = $false
    do {
        $mascara = Read-Host "Mascara (Enter para calcular automaticamente)"
        if ($mascara -eq "") {
            $mascValida = $true
        }
        elseif (validar_Mascara -masc $mascara) {
            $usoMas     = $true
            $mascValida = $true
        }
    } while (-not $mascValida)

    # IP del servidor
    $ipServidor = ""
    $ipInicial  = ""
    $ipValida   = $false
    do {
        $input = Read-Host "IP del servidor (sera la IP estatica, el rango DHCP empieza en +1)"

        if ($input -notmatch '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$') {
            Write-Host "Formato invalido, use X.X.X.X" -ForegroundColor $rojo
            continue
        }

        $oct       = $input -split '\.'
        $ultimoOct = [int]$oct[3]

        if ($ultimoOct -ge 254) {
            Write-Host "El ultimo octeto no puede ser 254 ni 255" -ForegroundColor $rojo
            continue
        }

        $ipTest = "$($oct[0]).$($oct[1]).$($oct[2]).1"
        if (-not (validar_IP -ip $ipTest)) {
            continue
        }

        $ipServidor = $input
        $ipInicial  = "$($oct[0]).$($oct[1]).$($oct[2]).$($ultimoOct + 1)"
        $ipValida   = $true

        Write-Host "IP del servidor : $ipServidor" -ForegroundColor $verde
        Write-Host "Rango DHCP desde: $ipInicial"  -ForegroundColor $verde

    } while (-not $ipValida)

    # IP Final
    $ipValida = $false
    do {
        $ipFinal = Read-Host "Rango final de la IP"

        if (validar_IP -ip $ipFinal) {
            $rango = calcular_Rango -ip1 $ipInicial -ip2 $ipFinal

            if ($rango -le 2) {
                Write-Host "El rango debe ser mayor a 2 IPs" -ForegroundColor $rojo
            }
            elseif ($usoMas) {
                if (validar_IPMascara -ipIni $ipInicial -ipFin $ipFinal -masc $mascara) {
                    $ipValida = $true
                }
            }
            else {
                $mascara  = calcular_Mascara -ipIni $ipInicial -ipFin $ipFinal
                Write-Host "Mascara calculada: $mascara" -ForegroundColor $verde
                $ipValida = $true
            }
        }

        if (-not $ipValida) { Write-Host "Intentando nuevamente..." -ForegroundColor $amarillo }
    } while (-not $ipValida)

    # Tiempo de sesion
    $leaseTime       = 0
    $leaseTimeValido = $false
    do {
        $input        = Read-Host "Tiempo de la sesion (segundos)"
        $leaseTimeNum = $input -as [int]

        if ($null -eq $leaseTimeNum -or $leaseTimeNum -le 0) {
            Write-Host "Ingrese un numero positivo" -ForegroundColor $rojo
        }
        else {
            $leaseTime       = $leaseTimeNum
            $leaseTimeValido = $true
        }
    } while (-not $leaseTimeValido)

    # Gateway
    $oct             = $ipInicial -split '\.'
    $gatewaySugerido = if ([int]$oct[3] -eq 1) {
        "$($oct[0]).$($oct[1]).$($oct[2]).254"
    }
    else {
        "$($oct[0]).$($oct[1]).$($oct[2]).1"
    }

    $gateway  = ""
    $gwValido = $false
    do {
        Write-Host "Gateway sugerido: $gatewaySugerido" -ForegroundColor $amarillo
        $input = Read-Host "Gateway (Enter para usar sugerido, 'ninguno' para omitir)"

        if ($input -eq "") {
            $gateway  = $gatewaySugerido
            $gwValido = $true
        }
        elseif ($input -eq "ninguno") {
            $gateway  = ""
            $gwValido = $true
            Write-Host "Sin gateway - red aislada" -ForegroundColor $amarillo
        }
        elseif (validar_IP -ip $input) {
            $gateway  = $input
            $gwValido = $true
        }
    } while (-not $gwValido)

    # DNS Principal
    $dns       = ""
    $dnsAlt    = ""
    $dnsValido = $false
    do {
        $input = Read-Host "DNS principal (Enter para omitir)"
        if ($input -eq "") {
            $dnsValido = $true
        }
        elseif (validar_IP -ip $input) {
            $dns       = $input
            $dnsValido = $true
        }
    } while (-not $dnsValido)

    # DNS Alternativo
    if ($dns -ne "") {
        $dnsAltValido = $false
        do {
            $input = Read-Host "DNS alternativo (Enter para omitir)"
            if ($input -eq "") {
                $dnsAltValido = $true
            }
            elseif (validar_IP -ip $input) {
                $dnsAlt       = $input
                $dnsAltValido = $true
            }
        } while (-not $dnsAltValido)
    }

    # Resumen
    Write-Host "`nConfiguracion final:" -ForegroundColor $azul
    Write-Host "  Nombre del ambito  : $scope"              -ForegroundColor $verde
    Write-Host "  IP del servidor    : $ipServidor"         -ForegroundColor $verde
    Write-Host "  Rango DHCP inicial : $ipInicial"          -ForegroundColor $verde
    Write-Host "  Rango DHCP final   : $ipFinal"            -ForegroundColor $verde
    Write-Host "  Mascara            : $mascara"            -ForegroundColor $verde
    Write-Host "  Tiempo de concesion: $leaseTime segundos" -ForegroundColor $verde
    if ($gateway -eq "") { Write-Host "  Gateway            : (ninguno)" -ForegroundColor $verde }
    else                 { Write-Host "  Gateway            : $gateway"  -ForegroundColor $verde }
    if ($dns -eq "")     { Write-Host "  DNS primario       : (ninguno)" -ForegroundColor $verde }
    else                 { Write-Host "  DNS primario       : $dns"      -ForegroundColor $verde }
    if ($dnsAlt -eq "")  { Write-Host "  DNS alternativo    : (ninguno)" -ForegroundColor $verde }
    else                 { Write-Host "  DNS alternativo    : $dnsAlt"   -ForegroundColor $verde }

    $opc = Read-Host "`nAcepta esta configuracion? (y/n)"
    if ($opc -ne "y") {
        Write-Host "Cancelado, volviendo al menu..." -ForegroundColor $amarillo
        return
    }

    # Paso 1: IP estatica
    Write-Host "`n--- Paso 1/2: Configurar IP estatica ---" -ForegroundColor $azul
    $ok = configurar_IP_Estatica -ipServidor $ipServidor -mascara $mascara -gateway $gateway
    if (-not $ok) {
        Write-Host "No se pudo configurar la IP estatica. Abortando." -ForegroundColor $rojo
        return
    }

    # Paso 2: Crear scope DHCP
    Write-Host "`n--- Paso 2/2: Crear scope DHCP ---" -ForegroundColor $azul
    try {
        $oIP   = $ipInicial -split '\.'
        $oMasc = $mascara   -split '\.'

        $red = @()
        for ($i = 0; $i -lt 4; $i++) {
            $red += [int]$oIP[$i] -band [int]$oMasc[$i]
        }
        $redStr = $red -join '.'

        Write-Host "Red: $redStr" -ForegroundColor $amarillo

        Add-DhcpServerv4Scope `
            -Name       $scope `
            -StartRange $ipInicial `
            -EndRange   $ipFinal `
            -SubnetMask $mascara `
            -State      Active

        if ($gateway -ne "") {
            Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 3 -Value $gateway
        }

        if ($dns -ne "" -and $dnsAlt -ne "") {
            Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 6 -Value @($dns, $dnsAlt)
        }
        elseif ($dns -ne "") {
            Set-DhcpServerv4OptionValue -ScopeId $redStr -OptionId 6 -Value $dns
        }

        Set-DhcpServerv4Scope -ScopeId $redStr -LeaseDuration (New-TimeSpan -Seconds $leaseTime)

        Write-Host "Reiniciando servicio DHCP..." -ForegroundColor $amarillo
        Restart-Service DHCPServer
        Start-Sleep -Seconds 2

        if ((Get-Service DHCPServer).Status -eq "Running") {
            Write-Host "`nServidor DHCP configurado y funcionando correctamente!" -ForegroundColor $verde
            Get-DhcpServerv4Scope -ScopeId $redStr | Format-List
        }
        else {
            Write-Host "Error: el servicio no quedo activo" -ForegroundColor $rojo
        }
    }
    catch {
        Write-Host "Error durante la configuracion: $($_.Exception.Message)" -ForegroundColor $rojo
    }
}

function verificar_Instalacion {
    $dhcp = Get-WindowsFeature -Name DHCP

    if ($dhcp.InstallState -eq "Installed") {
        Write-Host "DHCP esta instalado" -ForegroundColor $verde

        $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
        if ($scopes) {
            Write-Host "`nScopes configurados:" -ForegroundColor $azul
            $scopes | Format-Table -AutoSize
        }

        $svc = Get-Service DHCPServer
        Write-Host "Estado del servicio: " -NoNewline
        if ($svc.Status -eq "Running") {
            Write-Host "Funcionando" -ForegroundColor $verde
        }
        else {
            Write-Host "Detenido" -ForegroundColor $rojo
        }
    }
    else {
        Write-Host "DHCP no esta instalado" -ForegroundColor $rojo
        $opc = Read-Host "Desea instalarlo? (s/N)"
        if ($opc -match '^[Ss]$') {
            instalar_DHCP
        }
    }
}

function instalar_DHCP {
    Write-Host "`n=== Instalacion de DHCP Server ===" -ForegroundColor $amarillo

    $dhcp = Get-WindowsFeature -Name DHCP

    if ($dhcp.InstallState -eq "Installed") {
        Write-Host "DHCP ya esta instalado" -ForegroundColor $azul
    }
    else {
        try {
            $job = Start-Job -ScriptBlock { Install-WindowsFeature -Name DHCP -IncludeManagementTools }

            Write-Host -NoNewline "Instalando DHCP"
            while ($job.State -eq "Running") {
                Write-Host -NoNewline "."
                Start-Sleep -Milliseconds 500
            }
            Write-Host ""

            $result = Receive-Job -Job $job
            Remove-Job -Job $job

            if ($result.Success) {
                Write-Host "DHCP instalado correctamente" -ForegroundColor $verde
            }
            else {
                Write-Host "Error en la instalacion" -ForegroundColor $rojo
                return
            }
        }
        catch {
            Write-Host "Error: $_" -ForegroundColor $rojo
            return
        }
    }

    $scopesExistentes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    if ($scopesExistentes) {
        Write-Host "`nSe encontro configuracion previa:" -ForegroundColor $amarillo
        $scopesExistentes | Format-Table -AutoSize

        $opc = Read-Host "Desea sobreescribirla? (s/N)"
        if ($opc -notmatch '^[Ss]$') {
            Write-Host "Manteniendo configuracion existente" -ForegroundColor $azul
            return
        }

        foreach ($s in $scopesExistentes) {
            Remove-DhcpServerv4Scope -ScopeId $s.ScopeId -Force
        }
    }

    configuracionDHCP
}

function mostrarMenu {
    Clear-Host
    Write-Host "=====================================" -ForegroundColor $azul
    Write-Host "   Gestion de Servidor DHCP"          -ForegroundColor $verde
    Write-Host "=====================================" -ForegroundColor $azul
    Write-Host ""
    Write-Host "1. Verificar instalacion"   -ForegroundColor $amarillo
    Write-Host "2. Instalar y configurar"   -ForegroundColor $amarillo
    Write-Host "3. Configurar DHCP"         -ForegroundColor $amarillo
    Write-Host "4. Monitorear clientes"     -ForegroundColor $amarillo
    Write-Host "5. Ver scopes activos"      -ForegroundColor $amarillo
    Write-Host "6. Salir"                   -ForegroundColor $amarillo
    Write-Host ""

    $opc = Read-Host "Selecciona una opcion"

    switch ($opc) {
        "1" {
            verificar_Instalacion
            Read-Host "`nEnter para continuar"
            mostrarMenu
        }
        "2" {
            instalar_DHCP
            Read-Host "`nEnter para continuar"
            mostrarMenu
        }
        "3" {
            if ((Get-WindowsFeature -Name DHCP).InstallState -eq "Installed") {
                configuracionDHCP
            }
            else {
                Write-Host "DHCP no esta instalado" -ForegroundColor $rojo
            }
            Read-Host "`nEnter para continuar"
            mostrarMenu
        }
        "4" {
            monitorear_Clientes
            Read-Host "`nEnter para continuar"
            mostrarMenu
        }
        "5" {
            $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
            if ($scopes) {
                $scopes | Format-Table -AutoSize
            }
            else {
                Write-Host "No hay scopes configurados" -ForegroundColor $amarillo
            }
            Read-Host "`nEnter para continuar"
            mostrarMenu
        }
        "6" {
            Write-Host "Saliendo..." -ForegroundColor $verde
            exit
        }
        default {
            Write-Host "Opcion invalida" -ForegroundColor $rojo
            Start-Sleep -Seconds 2
            mostrarMenu
        }
    }
}

# ---------- Main ----------
param(
    [switch]$v,
    [switch]$i,
    [switch]$c,
    [switch]$m
)

if      ($v) { verificar_Instalacion }
elseif  ($i) { instalar_DHCP         }
elseif  ($c) { configuracionDHCP     }
elseif  ($m) { monitorear_Clientes   }
else         { mostrarMenu           }