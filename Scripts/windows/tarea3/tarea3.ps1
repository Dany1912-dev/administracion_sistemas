# ---------- Funciones ----------
function agregarRegistro {
    param(
        [string]$name,
        [string]$zoneName,
        [string]$ip
    )

    try {
        # -ErrorAction Stop es para que el 'catch' funcione
         Add-DNSServerResourceRecordA -Name $name -ZoneName $zoneName  -AllowUpdateAny -IPv4Address $ip  -ErrorAction Stop
        Write-Host "El registro '$name' se ha creado correctamente."
    }
    catch {
        Write-Host "No se pudo crear el registro. Detalles: $($_.Exception.Message)"
    }
}

function agregarZonaPrimaria {
    param([string]$name)

    Add-DnsServerPrimaryZone -Name $name -ReplicationScope "Forest" -PassThru
}

function agregarZonaPrimaria2 {
    param([string]$name, [string]$zoneFile)

    try {
        # -ErrorAction Stop es para que el 'catch' funcione
        Add-DnsServerPrimaryZone -Name $name -ZoneFile $zoneFile -ErrorAction Stop
        Write-Host "La zona '$name' se ha creado correctamente."
    }
    catch {
        Write-Host "No se pudo crear la zona. Detalles: $($_.Exception.Message)"
    }
}

function agregarZonaSecundaria {
    param(
        [string]$name,
        [string]$zoneFile,
        [string]$ipMS
    )

    try {
        Add-DnsServerSecondaryZone -Name $name -ZoneFile $zoneFile -MasterServers $ipMS -ErrorAction Stop
        Write-Host "La zona '$name' se ha creado correctamente."
    }
    catch {
        Write-Host "No se pudo crear la zona. Detalles: $($_.Exception.Message)"
    }
}

function actualizarRegistro{
    param(
        [string]$name,
        [string]$zoneName,
        [string]$ip
    )
    try {
        $registro = Get-DnsServerResourceRecord -Name $name -ZoneName $zoneName
        $registro.RecordData.IPv4Address = $ip
        Set-DnsServerResourceRecord -NewInputObject $registro -OldInputObject $registro -ZoneName $name  -ErrorAction Stop

        Write-Host "El registro '$name' se ha actualizado correctamente."
    }
    catch {
        Write-Host "No se pudo actualizar el registro. Detalles: $($_.Exception.Message)"
    }
}

function eliminarZona {
    param([string]$name)
    $cf = Read-Host "Deseas eliminar la zona '$name'? (S/N)"

    if ($cf -match '^[Ss]$'){
        try {
            Remove-DnsServerZone -Name $name -Force -ErrorAction Stop
            Write-Host "La zona '$name' se ha eliminado correctamente."
        }
        catch {
            Write-Host "No se pudo eliminar la zona. Detalles: $($_.Exception.Message)"
        }
    }
    else {
        Write-Host "Entendido, regresando..."
        return
    }
}

function eliminarRegistro {
    param(
        [string]$name,
        [string]$zoneName
    )

    try {
        Remove-DnsServerResourceRecord -ZoneName $zoneName -RRType A -Name $name -Force  -ErrorAction Stop
        Write-Host "El registro '$name' se ha eliminado correctamente."
    }
    catch {
        Write-Host "No se pudo eliminar el registro. Detalles: $($_.Exception.Message)"
    }

      
}

function modificarRegistro{
    param(
        [string]$zn,
        [string]$nomViejo,
        [string]$nomNuevo,
        [string]$nvIP
    )

    try {
        # 1. Obtener el registro actual
        $oldObj = Get-DnsServerResourceRecord -Name $nomViejo -ZoneName $zn -RRType "A" -ErrorAction Stop
        
        # 2. Crear una copia con los datos nuevos
        $newObj = $oldObj.Clone()
        $newObj.HostName = $nomNuevo
        $newObj.RecordData.IPv4Address = [System.Net.IPAddress]::Parse($nvIP)
        
        # 3. Reemplazar el viejo por el nuevo
        Set-DnsServerResourceRecord -OldInputObject $oldObj -NewInputObject $newObj -ZoneName $zn -ErrorAction Stop
        
        Write-Host "Registro actualizado con exito."
    }
    catch {
        Write-Host "Error al intentar editar: $($_.Exception.Message)"
    }
}

function configuracionDNS{
    Get-DnsServer
}

function ValidarIPFija {
    # Obtenemos la interfaz principal (ignora Bluetooth y Loopback)
    # Buscamos específicamente el Ethernet 2 que es el de nuestra red interna
    $interfaz = Get-NetAdapter | Where-Object { $_.Name -eq "Ethernet 2" -and $_.Status -eq "Up" }

    # Si por alguna razón el nombre es distinto, buscamos cualquiera que NO sea el de internet (opcional)
    if ($null -eq $interfaz) {
        $interfaz = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Name -notlike "*Bluetooth*" } | Select-Object -First 1
    }

    $ipActual = Get-NetIPAddress -InterfaceAlias $interfaz.Name -AddressFamily IPv4 | Select-Object -First 1

    if ($ipActual.PrefixOrigin -eq "Dhcp" -or $ipActual.IPAddress -like "169.254.*") {
        Write-Host "IP Dinamica (DHCP) detectada."
        $confirmar = Read-Host "Se detecto que no tiene IP fija, y se requiere tenerla. ¿Deseas configurarla ahora? (S/N)"
        
        if ($confirmar -eq "S") {
            $nuevaIP = Read-Host "IP Estatica (ej. 192.168.1.10)"
            $prefijo = Read-Host "Mascara en prefijo (ej. 24)"
            $gateway  = Read-Host "Puerta de enlace o gateway (ej. 192.168.1.1)"
            
            # Cambiamos de DHCP a Estática
            # El parámetro -Confirm:$false evita que pida permiso por cada paso
            New-NetIPAddress -InterfaceAlias $interfaz.Name -IPAddress $nuevaIP -PrefixLength $prefijo -DefaultGateway $gateway -Confirm:$false
            
            Write-Host "IP configurada con exito"
        }
    } else {
        Write-Host "Estado: IP Estatica ya configurada ($($ipActual.IPAddress))."
        Start-Sleep -Seconds 4 
    }
}

function configurarEscenario {
    $dom =  Read-Host "Ingresa el nombre del dominio (Ej: reprobados.com)"
    $ipDestino = Read-Host "Introduce la IP a la que apuntara (200.200.200.x)"
    $ipServidor = "200.200.200.1" 
    
    try {
        # Creamos la zona como un archivo simple (.dns), no integrada en el Forest
        Add-DnsServerPrimaryZone -Name $dom -ZoneFile "$dom.dns" -ErrorAction Stop 
        
        # Agregamos el registro para el dominio raíz (@) y para www
        Add-DnsServerResourceRecordA -Name "@" -ZoneName $dom -IPv4Address $ipDestino -ErrorAction Stop
        Add-DnsServerResourceRecordA -Name "www" -ZoneName $dom -IPv4Address $ipDestino -ErrorAction Stop
        
        Write-Host "Dominio $dom configurado con exito apuntando a $ipDestino"
        
        $pr = Read-Host "Deseas hacer una prueba? (S/N)"
        if ($pr -match '^[Ss]$'){
            Write-Host "Iniciando prueba..."
            pruebasDNS -zona $dom
        }
        else {
            Write-Host "Entendido, regresando..."
            return
        }
    }
    catch {
        Write-Host "Error: $($_.Exception.Message)"
    }
}

function pruebasDNS {
    param([string]$zona)

    Write-Host "1. Probando nslookup para $zona..."
    nslookup $zona 127.0.0.1
    
    Write-Host "`n2. Probando ping a www.$zona..."
    ping "www.$zona" -n 2
    
    Read-Host "`nPresiona Enter para finalizar las pruebas"
}

function verRegistroPorZonas{
    param([string]$name)

    try {
        Write-Host " ------------------------ "
        Write-Host " Registros existentes"
        Write-Host " ------------------------ "
        Get-DnsServerResourceRecord -ZoneName $name -RRType "A"  -ErrorAction Stop | Format-Table -AutoSize
    }
    catch {
        Write-Host "La zona '$name' no tiene registros."
    }
}

function verZonas {
    Write-Host " ------------------------ "
    Write-Host " Zonas existentes"
    Write-Host " ------------------------ "
    Get-DnsServerZone   
}

function configuracionZona {
    Clear-Host
    Write-Host "----------------------------------"
    Write-Host "   Menu configuracion de zona "
    Write-Host "----------------------------------"
    Write-Host "1. Ver zonas existentes" 
    Write-Host "2. Ver registros por zona" 
    Write-Host "3. Agregar zona" 
    Write-Host "4. Agregar registro" 
    Write-Host "5. Modificar registro"  
    Write-Host "6. Eliminar registro"
    Write-Host "7. Eliminar zona"   
    Write-Host "8. Volver al menu principal" 
    Write-Host "----------------------------------"
    
    $opc = Read-Host "Selecciona una opcion"
    switch ($opc) {
        "1" {
            verZonas
            Read-Host "`nPresiona Enter para continuar"
            configuracionZona
        }

        "2" {
            $zn = Read-Host "Dame el nombre de la zona"
            verRegistroPorZonas -name $zn
            Read-Host "`nPresiona Enter para continuar"
            configuracionZona
        }

        "3" {
            $opc = Read-Host "Desea agregar una zona? (s/n)"
            if ($opc -eq "s") { 
                $n = Read-Host "Dame el nombre de la zona"
                # Esto toma el nombre y le pega ".dns" al final automáticamente
                $zf = "$n.dns"

                agregarZonaPrimaria2 -name $n -zoneFile $zf
            }
            else {
                Write-Host "Entendido, regresando..."
                configuracionZona
            }
        }

        "4" {
                $n = Read-Host "Dame el nombre del registro"
                $zn = Read-Host "Dame el nombre de la zona"
                $i = Read-Host "Dame la IP para el registro"
                agregarRegistro -name $n -zoneName $zn -ip $i

            Read-Host "`nPresiona Enter para continuar"
            configuracionZona
        }

        "5"{
            $n = Read-Host "Dame el nombre actual del registro"
            $zn = Read-Host "Dame el nombre de la zona"
            
            $nn = Read-Host "Dame el nuevo nombre para el registro"
            $nip = Read-Host "Dame la nueva IP para el registro"

            modificarRegistro -zn $zn -nomViejo $n -nomNuevo $nn -nvIP $nip
            configuracionZona
        }

        "6"{
            $n = Read-Host "Dame el nombre del registro a eliminar"
            $z = Read-Host "Dame el nombre de la zona del registro a eliminar"
            eliminarRegistro -name $n -zoneName $z
            configuracionZona
        }

        "7" {
            $n = Read-Host "Dame el nombre de la zona a eliminar"
            eliminarZona -name $n
            Read-Host "`nPresiona Enter para continuar"
            configuracionZona 
        }

        "8"{
            Write-Host "`nSaliendo..."
            return
        }
        
        default {
            Write-Host "Opcion no valida"
            Start-Sleep -Seconds 1
            configuracionZona
        }
    }

}

function instalacionDNS {
  Write-Host " ---------------------------- "
  Write-Host "Instalacion de DNS Server" 
  Write-Host " ---------------------------- " 
    
    # Verificar si ya está instalado
    $dnsEstado = Get-WindowsFeature -Name *DNS*
    
    if ($DNSEstado.InstallState -eq "Installed") {
        Write-Host "DNS server ya esta instalado"
    }
    else {
        Write-Host "DNS server no esta instalado, iniciando instalacion..."
        
        try {
            $job = Start-Job -ScriptBlock {
                Install-WindowsFeature -Name DNS -IncludeManagementTools
            }
            
            Write-Host -NoNewline "DNS se esta instalando"
            while ($job.State -eq "Running") {
                Write-Host -NoNewline "."
                Start-Sleep -Milliseconds 500
            }
            
            $result = Receive-Job -Job $job
            Remove-Job -Job $job
            
            if ($result.Success) {
                Write-Host "DNS server instalado correctamente"
                Get-WindowsFeature -Name *DNS*
                Start-Sleep -Seconds 2
            }
            else {
                Write-Host "Error en la instalacion de DNS"
                return
            }
        }
        catch {
            Write-Host "Error durante la instalacion: $_"
            return
        }
    }
}

function verificarInstalacion {
    $DNSEstado = Get-WindowsFeature -Name *DNS*

    if ($DNSEstado.InstallState -eq "Installed") {
        Write-Host "DNS ya se encuentra instalado"
    }
    else {
        Write-Host "DNS no se encuentra instalado"
        $opcc = Read-Host "`nDesea instalarlo? (S/N)"
        
        if ($opcc -match '^[Ss]$') {
            instalacionDNS
        }
        else {
            Write-Host "Entendido, regresando al menu..."
            Start-Sleep -Seconds 2
        }
    }
}

function mostrarMenu {
    ValidarIPFija
    Clear-Host
    Write-Host "----------------------------------"
    Write-Host "   Menu  "
    Write-Host "----------------------------------"
    Write-Host "1. Verificar Instalacion DNS" 
    Write-Host "2. Instalar DNS" 
    Write-Host "3. Configuracion avanzada de zonas y registros"
    Write-Host "4. Configurar dominios"
    Write-Host "5. Realizar pruebas DNS" 
    Write-Host "6. Salir" 
    Write-Host "----------------------------------"
    
    $opcion = Read-Host "Selecciona una opcion"
    
    switch ($opcion) {
        "1" {
            verificarInstalacion
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "2" {
            instalacionDNS
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "3" {
            $DNSEstado = Get-WindowsFeature -Name *DNS*
            if ($DNSEstado.InstallState -eq "Installed") {
                configuracionZona
            }
            else {
                Write-Host "DNS no esta instalado. Instalelo primero."
            }
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "4" {
            configurarEscenario
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "5" {
            $dom =  Read-Host "Ingresa el nombre del dominio (Ej: reprobados.com)"
            pruebasDNS -zona $dom
            Read-Host "`nPresiona Enter para continuar"
            mostrarMenu
        }
        "6" {
            Write-Host "`nSaliendo..."
            exit
        }
        default {
            Write-Host "Opcion no valida"
            Start-Sleep -Seconds 2
            mostrarMenu
        }
    }
}

# ---------- Main ----------
mostrarMenu
