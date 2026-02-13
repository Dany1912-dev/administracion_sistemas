# ============================================================================
# Script de Configuración de Servidor DHCP - Windows Server 2025
# Administración de Sistemas
# PowerShell
# ============================================================================

#Requires -RunAsAdministrator

# Variables globales
$global:scope = ""
$global:ipInicial = ""
$global:ipFinal = ""
$global:mascara = ""
$global:tiempoSesion = 0
$global:gateway = ""
$global:dnsPrimario = ""
$global:dnsSecundario = ""
$global:broadcast = ""
$global:ipServidor = ""
$global:interfaz = ""

# ============================================================================
# FUNCIONES DE UTILIDAD
# ============================================================================

function Write-ColorOutput {
    param(
        [string]$Message,
        [string]$Type = "Info"
    )
    
    switch ($Type) {
        "Error"   { Write-Host "[ERROR] $Message" -ForegroundColor Red }
        "Success" { Write-Host "[OK] $Message" -ForegroundColor Green }
        "Warning" { Write-Host "[ADVERTENCIA] $Message" -ForegroundColor Yellow }
        default   { Write-Host "[INFO] $Message" -ForegroundColor Cyan }
    }
}

# ============================================================================
# FUNCIÓN: Convertir IP a número decimal
# ============================================================================
function ConvertTo-IpDecimal {
    param([string]$IpAddress)
    
    $octets = $IpAddress.Split('.')
    [int64]$decimal = ([int64]$octets[0] * 16777216) + 
                      ([int64]$octets[1] * 65536) + 
                      ([int64]$octets[2] * 256) + 
                      [int64]$octets[3]
    return $decimal
}

# ============================================================================
# FUNCIÓN: Convertir número decimal a IP
# ============================================================================
function ConvertFrom-IpDecimal {
    param([int64]$Decimal)
    
    $o1 = [Math]::Floor($Decimal / 16777216) % 256
    $o2 = [Math]::Floor($Decimal / 65536) % 256
    $o3 = [Math]::Floor($Decimal / 256) % 256
    $o4 = $Decimal % 256
    
    return "$o1.$o2.$o3.$o4"
}

# ============================================================================
# FUNCIÓN: Calcular máscara de subred automáticamente
# ============================================================================
function Calcular-Mascara {
    param(
        [string]$IpInicial,
        [string]$IpFinal
    )
    
    Write-ColorOutput "Calculando mascara de subred para el rango $IpInicial - $IpFinal..."
    
    $ip1Dec = ConvertTo-IpDecimal -IpAddress $IpInicial
    $ip2Dec = ConvertTo-IpDecimal -IpAddress $IpFinal
    
    if ($ip2Dec -lt $ip1Dec) {
        Write-ColorOutput "ERROR: IP final menor que IP inicial" "Error"
        return $null
    }
    
    $diferencia = $ip2Dec - $ip1Dec + 1
    Write-Host "IPs en el rango: $diferencia"
    
    $hostsNecesarios = $diferencia + 2
    Write-Host "Hosts necesarios: $hostsNecesarios"
    
    # Calcular CIDR por hosts necesarios
    $cidrHosts = 32
    for ($cidrHosts = 32; $cidrHosts -ge 8; $cidrHosts--) {
        $bits = 32 - $cidrHosts
        $hostsDisponibles = [Math]::Pow(2, $bits) - 2
        
        if ($hostsNecesarios -le $hostsDisponibles) {
            break
        }
    }
    
    # Calcular CIDR por misma subred
    $cidrSubred = 32
    for ($cidrSubred = 32; $cidrSubred -ge 8; $cidrSubred--) {
        $mascaraTmp = 0
        
        # Poner 1's en los primeros bits
        for ($i = 0; $i -lt $cidrSubred; $i++) {
            $mascaraTmp = ($mascaraTmp * 2) + 1
        }
        # Poner 0's en los bits restantes
        for ($i = $cidrSubred; $i -lt 32; $i++) {
            $mascaraTmp = $mascaraTmp * 2
        }
        
        $red1 = $ip1Dec -band $mascaraTmp
        $red2 = $ip2Dec -band $mascaraTmp
        
        if ($red1 -eq $red2) {
            break
        }
    }
    
    # Elegir el CIDR que cumpla AMBAS condiciones
    $cidrFinal = [Math]::Min($cidrHosts, $cidrSubred)
    
    Write-Host "CIDR necesario por hosts: /$cidrHosts"
    Write-Host "CIDR necesario por subred: /$cidrSubred"
    Write-Host "CIDR final seleccionado: /$cidrFinal"
    
    # Calcular máscara en formato decimal
    $mascaraDec = 0
    for ($i = 0; $i -lt $cidrFinal; $i++) {
        $mascaraDec = ($mascaraDec * 2) + 1
    }
    for ($i = $cidrFinal; $i -lt 32; $i++) {
        $mascaraDec = $mascaraDec * 2
    }
    
    $mascara = ConvertFrom-IpDecimal -Decimal $mascaraDec
    
    # Calcular hosts disponibles
    $bitsFinales = 32 - $cidrFinal
    $hostsFinales = [Math]::Pow(2, $bitsFinales) - 2
    
    Write-Host "Máscara calculada: $mascara (CIDR: /$cidrFinal)"
    Write-Host "Hosts disponibles: $hostsFinales"
    
    # Calcular broadcast
    $redBase = $ip1Dec -band $mascaraDec
    $global:broadcast = ConvertFrom-IpDecimal -Decimal ($redBase -bor (-bnot $mascaraDec -band 0xFFFFFFFF))
    
    Write-Host "Broadcast de la subred: $($global:broadcast)"
    Write-Host "Mascara de subred determinada: $mascara"
    
    return @{
        Mascara = $mascara
        CIDR = $cidrFinal
        Broadcast = $global:broadcast
    }
}

# ============================================================================
# FUNCIÓN: Validar formato de IP
# ============================================================================
function Validar-IP {
    param(
        [string]$IP,
        [string]$Tipo = "host"
    )
    
    # Verificar formato básico
    if ($IP -notmatch '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$') {
        Write-ColorOutput "Direccion IP invalida, debe tener formato X.X.X.X" "Error"
        return $false
    }
    
    $octetos = $IP.Split('.')
    
    if ($octetos.Count -ne 4) {
        Write-ColorOutput "ERROR: Debe tener exactamente 4 octetos." "Error"
        return $false
    }
    
    # Validar cada octeto
    foreach ($octeto in $octetos) {
        # Verificar ceros a la izquierda
        if ($octeto.Length -gt 1 -and $octeto.StartsWith('0')) {
            Write-ColorOutput "ERROR: Octeto '$octeto' no puede tener ceros a la izquierda" "Error"
            return $false
        }
        
        $num = [int]$octeto
        if ($num -lt 0 -or $num -gt 255) {
            Write-ColorOutput "ERROR: Octeto '$octeto' fuera de rango (0-255)." "Error"
            return $false
        }
    }
    
    $primerOcteto = [int]$octetos[0]
    $cuartoOcteto = [int]$octetos[3]
    
    # Validaciones específicas por tipo
    if ($Tipo -eq "host") {
        if ($primerOcteto -eq 0) {
            Write-ColorOutput "ERROR: El primer octeto no puede ser 0 para una direccion host." "Error"
            return $false
        }
        
        if ($cuartoOcteto -eq 0) {
            Write-ColorOutput "ERROR: El ultimo octeto no puede ser 0 para una direccion host." "Error"
            return $false
        }
        
        if ($cuartoOcteto -eq 255) {
            Write-ColorOutput "ERROR: El ultimo octeto no puede ser 255 para una direccion host." "Error"
            return $false
        }
        
        if ($primerOcteto -eq 127) {
            Write-ColorOutput "ERROR: 127.x.x.x es direccion loopback, no valida para host." "Error"
            return $false
        }
        
        if ($primerOcteto -ge 224 -and $primerOcteto -le 239) {
            Write-ColorOutput "ERROR: $IP es direccion multicast (224-239.x.x.x)." "Error"
            return $false
        }
        
        if ($primerOcteto -ge 240) {
            Write-ColorOutput "ERROR: $IP esta en rango reservado experimental (240-255.x.x.x)." "Error"
            return $false
        }
    }
    elseif ($Tipo -eq "gateway" -or $Tipo -eq "dns") {
        if ($primerOcteto -ge 224 -and $primerOcteto -le 239) {
            Write-ColorOutput "ERROR: $IP es direccion multicast, no valida para $Tipo." "Error"
            return $false
        }
        
        if ($primerOcteto -ge 240) {
            Write-ColorOutput "ERROR: $IP esta en rango reservado experimental, no valida para $Tipo." "Error"
            return $false
        }
        
        if ($IP -eq "0.0.0.0") {
            Write-ColorOutput "ADVERTENCIA: $IP puede no ser una direccion $Tipo valida en produccion." "Warning"
        }
    }
    
    return $true
}

# ============================================================================
# FUNCIÓN: Comparar IPs
# ============================================================================
function Comparar-IPs {
    param(
        [string]$IP1,
        [string]$IP2
    )
    
    $num1 = ConvertTo-IpDecimal -IpAddress $IP1
    $num2 = ConvertTo-IpDecimal -IpAddress $IP2
    
    if ($num1 -ge $num2) {
        Write-ColorOutput "ERROR: La IP inicial ($IP1) debe ser menor que la IP final ($IP2)." "Error"
        return $false
    }
    
    return $true
}

# ============================================================================
# FUNCIÓN: Verificar instalación de rol DHCP
# ============================================================================
function Verificar-Instalacion {
    Write-Host ""
    Write-ColorOutput "VERIFICANDO INSTALACION DEL ROL DHCP"
    Write-Host ""
    
    $dhcpRole = Get-WindowsFeature -Name DHCP -ErrorAction SilentlyContinue
    
    if ($dhcpRole -and $dhcpRole.Installed) {
        Write-ColorOutput "El rol DHCP ya esta instalado." "Success"
        
        # Verificar si el servicio está corriendo
        $dhcpService = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue
        if ($dhcpService) {
            Write-Host "Estado del servicio: $($dhcpService.Status)"
        }
    }
    else {
        Write-ColorOutput "El rol DHCP NO esta instalado." "Warning"
    }
    
    Write-Host ""
    Read-Host "Presione Enter para continuar"
}

# ============================================================================
# FUNCIÓN: Instalar rol DHCP
# ============================================================================
function Instalar-DHCP {
    Write-Host ""
    Write-ColorOutput "INSTALANDO ROL DHCP"
    Write-Host ""
    
    $dhcpRole = Get-WindowsFeature -Name DHCP
    
    if ($dhcpRole.Installed) {
        Write-ColorOutput "El rol DHCP ya esta instalado." "Success"
    }
    else {
        Write-ColorOutput "Instalando rol DHCP..." "Info"
        
        try {
            Install-WindowsFeature -Name DHCP -IncludeManagementTools
            Write-ColorOutput "Instalacion completada exitosamente." "Success"
            
            # Configurar grupo de seguridad
            netsh dhcp add securitygroups
            Restart-Service DHCPServer
            
            Write-ColorOutput "Servicio DHCP iniciado." "Success"
        }
        catch {
            Write-ColorOutput "Error al instalar el rol DHCP: $_" "Error"
            return
        }
    }
    
    Configurar-DHCP
}

# ============================================================================
# FUNCIÓN: Configurar servidor DHCP
# ============================================================================
function Configurar-DHCP {
    Write-Host ""
    Write-ColorOutput "CONFIGURACION DHCP DINAMICA"
    Write-Host ""
    
    # Nombre del ámbito
    $global:scope = Read-Host "Nombre descriptivo del ambito"
    
    # IP inicial (será la IP del servidor)
    do {
        $global:ipInicial = Read-Host "Rango inicial de la IP"
        $valido = Validar-IP -IP $global:ipInicial -Tipo "host"
        
        if ($valido) {
            $global:ipServidor = $global:ipInicial
            
            # Incrementar IP inicial para el rango DHCP
            $octetos = $global:ipInicial.Split('.')
            $octetos[3] = ([int]$octetos[3] + 1).ToString()
            $global:ipInicial = $octetos -join '.'
        }
    } while (-not $valido)
    
    # IP final
    do {
        $global:ipFinal = Read-Host "Rango final de la IP"
        $valido = (Validar-IP -IP $global:ipFinal -Tipo "host") -and 
                  (Comparar-IPs -IP1 $global:ipInicial -IP2 $global:ipFinal)
    } while (-not $valido)
    
    # Calcular máscara automáticamente
    Write-Host ""
    $resultadoMascara = Calcular-Mascara -IpInicial $global:ipInicial -IpFinal $global:ipFinal
    
    if ($null -eq $resultadoMascara) {
        Write-ColorOutput "ERROR: No se pudo calcular una mascara. Usando valor por defecto." "Error"
        $global:mascara = "255.255.255.0"
    }
    else {
        $global:mascara = $resultadoMascara.Mascara
        Write-Host "Mascara de subred determinada: $($global:mascara)"
    }
    Write-Host ""
    
    # Tiempo de sesión (en segundos para Windows)
    do {
        $tiempoMinutos = Read-Host "Tiempo de la sesion (en minutos)"
        
        if ([string]::IsNullOrWhiteSpace($tiempoMinutos)) {
            Write-ColorOutput "ERROR: El tiempo de sesion no puede estar vacio." "Error"
            $valido = $false
        }
        elseif ($tiempoMinutos -notmatch '^\d+$') {
            Write-ColorOutput "ERROR: El tiempo de sesion debe ser un numero positivo." "Error"
            $valido = $false
        }
        elseif ([int]$tiempoMinutos -le 0) {
            Write-ColorOutput "ERROR: El tiempo de sesion debe ser mayor a 0." "Error"
            $valido = $false
        }
        elseif ([int]$tiempoMinutos -gt 43200) {
            Write-ColorOutput "ERROR: El tiempo de sesion no puede ser mayor a 43200 minutos (30 dias)." "Error"
            $valido = $false
        }
        else {
            $global:tiempoSesion = [int]$tiempoMinutos
            $valido = $true
        }
    } while (-not $valido)
    
    # Gateway (opcional)
    do {
        $global:gateway = Read-Host "Gateway (OPCIONAL, presiona Enter para omitir)"
        
        if ([string]::IsNullOrWhiteSpace($global:gateway) -or $global:gateway -eq "none") {
            $global:gateway = ""
            $valido = $true
        }
        else {
            $valido = Validar-IP -IP $global:gateway -Tipo "gateway"
        }
    } while (-not $valido)
    
    # DNS primario (opcional)
    do {
        $global:dnsPrimario = Read-Host "DNS primario (OPCIONAL, presiona Enter para omitir)"
        
        if ([string]::IsNullOrWhiteSpace($global:dnsPrimario) -or $global:dnsPrimario -eq "none") {
            $global:dnsPrimario = ""
            $valido = $true
        }
        else {
            $valido = Validar-IP -IP $global:dnsPrimario -Tipo "dns"
        }
    } while (-not $valido)
    
    # DNS secundario (si se proporcionó primario)
    if (-not [string]::IsNullOrWhiteSpace($global:dnsPrimario)) {
        do {
            $respuesta = Read-Host "¿Desea agregar un DNS secundario? (s/n)"
            
            if ($respuesta -eq 's') {
                do {
                    $global:dnsSecundario = Read-Host "DNS secundario"
                    $valido = Validar-IP -IP $global:dnsSecundario -Tipo "dns"
                } while (-not $valido)
                break
            }
            elseif ($respuesta -eq 'n') {
                $global:dnsSecundario = ""
                break
            }
            else {
                Write-ColorOutput "Por favor ingrese 's' o 'n'." "Warning"
            }
        } while ($true)
    }
    else {
        Write-Host "No se agrego un DNS primario."
    }
    
    # Mostrar interfaces disponibles
    Write-Host ""
    Write-ColorOutput "Interfaces de red disponibles:"
    $interfaces = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
    $interfaces | Format-Table -Property InterfaceIndex, Name, InterfaceDescription, Status
    
    do {
        $interfaceIndex = Read-Host "Ingrese el numero de indice de la interfaz (InterfaceIndex)"
        $global:interfaz = $interfaces | Where-Object { $_.InterfaceIndex -eq $interfaceIndex }
        
        if ($null -eq $global:interfaz) {
            Write-ColorOutput "Interfaz no valida. Intente de nuevo." "Error"
        }
    } while ($null -eq $global:interfaz)
    
    # Mostrar configuración final
    Write-Host ""
    Write-ColorOutput "LA CONFIGURACION FINAL ES:"
    Write-Host "Nombre del ambito: $($global:scope)"
    Write-Host "Mascara: $($global:mascara)"
    Write-Host "IP del servidor: $($global:ipServidor)"
    Write-Host "IP inicial (rango DHCP): $($global:ipInicial)"
    Write-Host "IP final (rango DHCP): $($global:ipFinal)"
    Write-Host "Tiempo de sesion: $($global:tiempoSesion) minutos"
    
    if ([string]::IsNullOrWhiteSpace($global:gateway)) {
        Write-Host "Gateway: [No configurado]"
    } else {
        Write-Host "Gateway: $($global:gateway)"
    }
    
    if ([string]::IsNullOrWhiteSpace($global:dnsPrimario)) {
        Write-Host "DNS primario: [No configurado]"
    } else {
        Write-Host "DNS primario: $($global:dnsPrimario)"
    }
    
    if ([string]::IsNullOrWhiteSpace($global:dnsSecundario)) {
        Write-Host "DNS alternativo: [No configurado]"
    } else {
        Write-Host "DNS alternativo: $($global:dnsSecundario)"
    }
    
    Write-Host "Interfaz: $($global:interfaz.Name) (Index: $($global:interfaz.InterfaceIndex))"
    Write-Host ""
    
    # Advertencia si la IP del servidor está en el rango DHCP
    $servidorNum = ConvertTo-IpDecimal -IpAddress $global:ipServidor
    $inicioNum = ConvertTo-IpDecimal -IpAddress $global:ipInicial
    $finalNum = ConvertTo-IpDecimal -IpAddress $global:ipFinal
    
    if ($servidorNum -ge $inicioNum -and $servidorNum -le $finalNum) {
        Write-ColorOutput "ADVERTENCIA: La IP del servidor ($($global:ipServidor)) esta dentro del rango DHCP." "Warning"
        Write-Host "   Esto puede causar conflictos. Se recomienda usar una IP fuera del rango."
        Write-Host ""
    }
    
    $confirmacion = Read-Host "¿Acepta esta configuracion? (s/n)"
    
    if ($confirmacion -eq 's') {
        Aplicar-Configuracion
    }
    else {
        Write-ColorOutput "Volviendo a configurar..." "Info"
        Configurar-DHCP
    }
}

# ============================================================================
# FUNCIÓN: Aplicar configuración DHCP
# ============================================================================
function Aplicar-Configuracion {
    Write-Host ""
    Write-ColorOutput "APLICANDO CONFIGURACION"
    Write-Host ""
    
    try {
        # Calcular dirección de red
        $octetos = $global:ipInicial.Split('.')
        $mascaraOctetos = $global:mascara.Split('.')
        
        $red = @()
        for ($i = 0; $i -lt 4; $i++) {
            $red += ([int]$octetos[$i] -band [int]$mascaraOctetos[$i])
        }
        $redCalculada = $red -join '.'
        
        Write-Host "Red calculada: $redCalculada"
        Write-Host "Broadcast calculado: $($global:broadcast)"
        Write-Host ""
        
        # Configurar IP estática en la interfaz
        Write-ColorOutput "Configurando IP estatica en la interfaz..." "Info"
        Configurar-InterfazRed
        
        # Verificar si el ámbito ya existe
        $scopeExistente = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | 
                         Where-Object { $_.Name -eq $global:scope -or $_.ScopeId -eq $redCalculada }
        
        if ($scopeExistente) {
            Write-ColorOutput "El ambito '$($global:scope)' ya existe. Eliminando para recrear..." "Warning"
            Remove-DhcpServerv4Scope -ScopeId $scopeExistente.ScopeId -Force
        }
        
        # Crear ámbito DHCP
        Write-ColorOutput "Creando ambito DHCP..." "Info"
        
        $scopeParams = @{
            Name = $global:scope
            StartRange = $global:ipInicial
            EndRange = $global:ipFinal
            SubnetMask = $global:mascara
            LeaseDuration = New-TimeSpan -Minutes $global:tiempoSesion
            State = 'Active'
        }
        
        Add-DhcpServerv4Scope @scopeParams
        Write-ColorOutput "Ambito DHCP creado exitosamente." "Success"
        
        # Configurar opciones del ámbito
        if (-not [string]::IsNullOrWhiteSpace($global:gateway)) {
            Write-ColorOutput "Configurando Gateway: $($global:gateway)" "Info"
            Set-DhcpServerv4OptionValue -ScopeId $redCalculada -Router $global:gateway
        }
        
        if (-not [string]::IsNullOrWhiteSpace($global:dnsPrimario)) {
            if (-not [string]::IsNullOrWhiteSpace($global:dnsSecundario)) {
                Write-ColorOutput "Configurando servidores DNS: $($global:dnsPrimario), $($global:dnsSecundario)" "Info"
                Set-DhcpServerv4OptionValue -ScopeId $redCalculada -DnsServer $global:dnsPrimario, $global:dnsSecundario
            }
            else {
                Write-ColorOutput "Configurando servidor DNS: $($global:dnsPrimario)" "Info"
                Set-DhcpServerv4OptionValue -ScopeId $redCalculada -DnsServer $global:dnsPrimario
            }
        }
        
        # Reiniciar servicio DHCP
        Write-ColorOutput "Reiniciando servicio DHCP..." "Info"
        Restart-Service DHCPServer
        
        Write-Host ""
        Write-ColorOutput "═══════════════════════════════════════════" "Success"
        Write-ColorOutput "  ✓ Servidor DHCP configurado exitosamente!" "Success"
        Write-ColorOutput "═══════════════════════════════════════════" "Success"
        Write-Host ""
        Write-Host "Resumen de configuracion:"
        Write-Host "  • Red: $redCalculada"
        Write-Host "  • Rango DHCP: $($global:ipInicial) - $($global:ipFinal)"
        Write-Host "  • IP del servidor: $($global:ipServidor)"
        Write-Host "  • Interfaz: $($global:interfaz.Name)"
        Write-Host "  • Gateway: $(if ([string]::IsNullOrWhiteSpace($global:gateway)) { '[No configurado]' } else { $global:gateway })"
        Write-Host "  • DNS: $(if ([string]::IsNullOrWhiteSpace($global:dnsPrimario)) { '[No configurado]' } else { $global:dnsPrimario })"
        Write-Host ""
        
        # Mostrar estado del servicio
        Get-Service DHCPServer | Format-List
        
        # Mostrar ámbitos configurados
        Write-ColorOutput "Ambitos DHCP configurados:" "Info"
        Get-DhcpServerv4Scope | Format-Table -Property ScopeId, Name, State, StartRange, EndRange
    }
    catch {
        Write-ColorOutput "═══════════════════════════════════════════" "Error"
        Write-ColorOutput "  ✗ Error al configurar el servidor DHCP" "Error"
        Write-ColorOutput "═══════════════════════════════════════════" "Error"
        Write-Host ""
        Write-ColorOutput "Detalles del error: $_" "Error"
    }
    
    Write-Host ""
    Read-Host "Presione Enter para continuar"
}

# ============================================================================
# FUNCIÓN: Configurar interfaz de red con IP estática
# ============================================================================
function Configurar-InterfazRed {
    Write-Host ""
    Write-ColorOutput "Configurando IP estatica $($global:ipServidor) en interfaz $($global:interfaz.Name)..." "Info"
    Write-Host ""
    
    # Calcular prefijo CIDR
    $cidr = 0
    $mascaraOctetos = $global:mascara.Split('.')
    foreach ($octeto in $mascaraOctetos) {
        $bits = [Convert]::ToString([int]$octeto, 2)
        $cidr += ($bits.ToCharArray() | Where-Object { $_ -eq '1' }).Count
    }
    
    Write-Host "Configuracion actual:"
    Get-NetIPAddress -InterfaceIndex $global:interfaz.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue | 
        Format-Table -Property IPAddress, PrefixLength
    Write-Host ""
    
    # Eliminar configuraciones IP existentes
    Write-ColorOutput "Eliminando configuraciones IP anteriores..." "Info"
    $ipExistentes = Get-NetIPAddress -InterfaceIndex $global:interfaz.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue
    
    foreach ($ip in $ipExistentes) {
        try {
            Remove-NetIPAddress -InterfaceIndex $global:interfaz.InterfaceIndex -IPAddress $ip.IPAddress -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "  Eliminada IP: $($ip.IPAddress)"
        }
        catch {
            # Ignorar errores al eliminar
        }
    }
    
    # Asignar nueva IP estática
    Write-ColorOutput "Asignando nueva IP estatica: $($global:ipServidor)/$cidr" "Info"
    
    try {
        New-NetIPAddress -InterfaceIndex $global:interfaz.InterfaceIndex `
                        -IPAddress $global:ipServidor `
                        -PrefixLength $cidr `
                        -DefaultGateway $null `
                        -ErrorAction Stop
        
        Write-ColorOutput "IP estatica configurada exitosamente." "Success"
    }
    catch {
        if ($_.Exception.Message -like "*already exists*") {
            Write-ColorOutput "La IP ya existe en la interfaz. Continuando..." "Warning"
        }
        else {
            Write-ColorOutput "Error al configurar IP: $_" "Error"
        }
    }
    
    # Verificación final
    Write-Host ""
    Write-ColorOutput "Configuracion final de la interfaz:" "Info"
    Get-NetIPAddress -InterfaceIndex $global:interfaz.InterfaceIndex -AddressFamily IPv4 | 
        Format-Table -Property IPAddress, PrefixLength, InterfaceAlias
    Write-Host ""
}

# ============================================================================
# FUNCIÓN: Reiniciar servicio DHCP
# ============================================================================
function Reiniciar-DHCP {
    Write-Host ""
    Write-ColorOutput "Reiniciando servidor DHCP..." "Info"
    
    $servicio = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue
    
    if ($null -eq $servicio) {
        Write-ColorOutput "El servicio DHCP no esta instalado." "Error"
        Read-Host "Presione Enter para continuar"
        return
    }
    
    if ($servicio.Status -ne 'Running') {
        Write-ColorOutput "El servicio DHCP no esta activo." "Warning"
        $respuesta = Read-Host "¿Desea iniciarlo? (y/n)"
        
        if ($respuesta -eq 'y') {
            Start-Service DHCPServer
            Write-ColorOutput "Servicio DHCP iniciado." "Success"
        }
    }
    else {
        Restart-Service DHCPServer
        Write-ColorOutput "Servicio DHCP reiniciado correctamente." "Success"
    }
    
    Write-Host ""
    Get-Service DHCPServer | Format-List
    
    Read-Host "Presione Enter para continuar"
}

# ============================================================================
# FUNCIÓN: Detener servicio DHCP
# ============================================================================
function Detener-DHCP {
    Write-Host ""
    Write-ColorOutput "Deteniendo servidor DHCP..." "Info"
    
    $servicio = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue
    
    if ($null -eq $servicio) {
        Write-ColorOutput "El servicio DHCP no esta instalado." "Error"
        Read-Host "Presione Enter para continuar"
        return
    }
    
    if ($servicio.Status -ne 'Running') {
        Write-ColorOutput "El servicio DHCP ya esta detenido." "Info"
    }
    else {
        Stop-Service DHCPServer
        Write-ColorOutput "Servidor DHCP detenido correctamente." "Success"
    }
    
    Write-Host ""
    Get-Service DHCPServer | Format-List
    
    Read-Host "Presione Enter para continuar"
}

# ============================================================================
# FUNCIÓN: Monitorear servidor DHCP
# ============================================================================
function Monitorear-DHCP {
    Clear-Host
    Write-Host "═══════════════════════════════════════════"
    Write-Host "   MONITOR DEL SERVIDOR DHCP"
    Write-Host "═══════════════════════════════════════════"
    Write-Host ""
    
    # Verificar si el servicio está activo
    $servicio = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue
    
    if ($null -eq $servicio) {
        Write-ColorOutput "El servicio DHCP no esta instalado." "Error"
        Read-Host "Presione Enter para volver al menu"
        return
    }
    
    if ($servicio.Status -ne 'Running') {
        Write-ColorOutput "⚠ El servicio DHCP NO esta activo" "Warning"
        Write-Host ""
        Read-Host "Presione Enter para volver al menu"
        return
    }
    
    Write-ColorOutput "✓ Estado del servicio: ACTIVO" "Success"
    Write-Host ""
    
    # Mostrar ámbitos configurados
    Write-ColorOutput "--- AMBITOS CONFIGURADOS ---" "Info"
    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue
    
    if ($scopes) {
        $scopes | Format-Table -Property ScopeId, Name, State, StartRange, EndRange, LeaseDuration -AutoSize
    }
    else {
        Write-Host "No hay ambitos configurados."
    }
    Write-Host ""
    
    # Mostrar IPs asignadas (leases)
    Write-ColorOutput "--- IPS ASIGNADAS (LEASES) ---" "Info"
    
    foreach ($scope in $scopes) {
        Write-Host "Ambito: $($scope.Name) ($($scope.ScopeId))"
        
        $leases = Get-DhcpServerv4Lease -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
        
        if ($leases) {
            $leases | Format-Table -Property IPAddress, ClientId, HostName, AddressState, LeaseExpiryTime -AutoSize
            Write-Host "Total de leases activos en este ambito: $($leases.Count)"
        }
        else {
            Write-Host "  No hay leases activos en este ambito."
        }
        Write-Host ""
    }
    
    # Estadísticas del servidor
    Write-ColorOutput "--- ESTADISTICAS DEL SERVIDOR ---" "Info"
    
    foreach ($scope in $scopes) {
        Write-Host "Estadisticas del ambito: $($scope.Name)"
        
        $stats = Get-DhcpServerv4ScopeStatistics -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
        
        if ($stats) {
            Write-Host "  Direcciones en uso: $($stats.AddressesInUse)"
            Write-Host "  Direcciones libres: $($stats.AddressesFree)"
            Write-Host "  Direcciones pendientes: $($stats.PendingOffers)"
            Write-Host "  Porcentaje en uso: $($stats.PercentageInUse)%"
        }
        Write-Host ""
    }
    
    # Estado del servicio
    Write-ColorOutput "--- ESTADO DEL SERVICIO ---" "Info"
    Get-Service DHCPServer | Format-List
    
    Write-Host ""
    Read-Host "Presione Enter para volver al menu"
}

# ============================================================================
# FUNCIÓN: Mostrar menú principal
# ============================================================================
function Mostrar-Menu {
    Clear-Host
    Write-Host "═══════════════════════════════════════════"
    Write-Host "   SERVIDOR DHCP - WINDOWS SERVER 2025"
    Write-Host "═══════════════════════════════════════════"
    Write-Host " 1. Verificar instalacion"
    Write-Host " 2. Instalacion completa (rol + configuracion)"
    Write-Host " 3. Solo configurar/reconfigurar DHCP"
    Write-Host " 4. Monitorear (IPs asignadas)"
    Write-Host " 5. Reiniciar servicio"
    Write-Host " 6. Detener servicio"
    Write-Host " 7. Salir"
    Write-Host "═══════════════════════════════════════════"
    
    $opcion = Read-Host " Seleccione una opcion [1-7]"
    
    switch ($opcion) {
        "1" { Verificar-Instalacion; Mostrar-Menu }
        "2" { Instalar-DHCP; Mostrar-Menu }
        "3" { Configurar-DHCP; Mostrar-Menu }
        "4" { Monitorear-DHCP; Mostrar-Menu }
        "5" { Reiniciar-DHCP; Mostrar-Menu }
        "6" { Detener-DHCP; Mostrar-Menu }
        "7" { 
            Write-Host ""
            Write-ColorOutput "Saliendo del script..." "Info"
            exit 
        }
        default {
            Write-ColorOutput "Opcion invalida" "Error"
            Start-Sleep -Seconds 2
            Mostrar-Menu
        }
    }
}

# ============================================================================
# INICIO DEL SCRIPT
# ============================================================================

# Verificar que se ejecuta como administrador
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-ColorOutput "Este script debe ejecutarse como Administrador." "Error"
    Write-Host ""
    Write-Host "Haga clic derecho en PowerShell y seleccione 'Ejecutar como administrador'"
    Read-Host "Presione Enter para salir"
    exit
}

# Mostrar menú principal
Mostrar-Menu
