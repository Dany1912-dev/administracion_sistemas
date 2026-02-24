# lib/commons.ps1
# Libreria compartida entre tarea2_DHCP.ps1 y tarea3.ps1

# ---------- Colores ----------
$verde    = "Green"
$amarillo = "Yellow"
$azul     = "Cyan"
$rojo     = "Red"
$nc       = "White"
$rosa     = "Magenta"

# ---------- Validacion de IP ----------
# Valida formato X.X.X.X, rangos reservados y octetos correctos
# Uso: validar_IP -ip "192.168.1.1"  -> retorna $true o $false
function validar_IP {
    param([string]$ip)

    if ($ip -notmatch '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$') {
        Write-Host "IP invalida: formato incorrecto, use X.X.X.X" -ForegroundColor $rojo
        return $false
    }

    $oct = $ip -split '\.'
    $a   = [int]$oct[0]

    foreach ($o in $oct) {
        if ($o.Length -gt 1 -and $o.StartsWith("0")) {
            Write-Host "IP invalida: no se permiten ceros a la izquierda" -ForegroundColor $rojo
            return $false
        }
        if ([int]$o -lt 0 -or [int]$o -gt 255) {
            Write-Host "IP invalida: cada octeto debe estar entre 0 y 255" -ForegroundColor $rojo
            return $false
        }
    }

    if ($ip -eq "0.0.0.0" -or $ip -eq "255.255.255.255") {
        Write-Host "IP invalida: no puede ser 0.0.0.0 ni 255.255.255.255" -ForegroundColor $rojo
        return $false
    }

    if ($a -eq 127) {
        Write-Host "IP invalida: rango 127.x.x.x reservado para localhost" -ForegroundColor $rojo
        return $false
    }

    if ($a -ge 224 -and $a -le 239) {
        Write-Host "IP invalida: rango 224-239 reservado para multicast" -ForegroundColor $rojo
        return $false
    }

    if ($a -ge 240 -and $a -lt 255) {
        Write-Host "IP invalida: rango 240-254 reservado para usos experimentales" -ForegroundColor $rojo
        return $false
    }

    return $true
}