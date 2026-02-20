#!/bin/bash

# ----------Colores para que sea mas intuitivo ----------
rojo='\033[0;31m'
amarillo='\033[1;33m'
verde='\033[0;32m'
azul='\033[1;34m'
cyan='\033[0;36m'
nc='\033[0m'

# Variables globales
domain=""
ip=""
interface=""
mode=""
server_ip=""
named_conf="/etc/named.conf"
zones_dir="/var/lib/named"
named_service="named"
log_dir="/var/log/named"
force=false
BACKUP=false
DRY_RUN=false
CONFIGURE_DNS=false
EVIDENCE_FILE="/tmp/dns-test-evidence-$(date +%Y%m%d-%H%M%S).log"

# ---------- Funciones ----------

ayuda() {
    echo "Uso del script: $0"
    echo "Opciones:"
    echo -e "  ${azul}-v, --verify       ${nc}Verifica si esta instalado BIND9"
    echo -e "  ${azul}-i, --install      ${nc}Instala y configura BIND9"
    echo -e "  ${azul}-m, --monitor      ${nc}Monitorear servidor DNS"
    echo -e "  ${azul}-r, --restart      ${nc}Reiniciar servidor DNS"
    echo -e "  ${azul}-?, --help         ${nc}Muestra esta ayuda"
}

print_warning(){
    echo -e "${rojo}$1${nc}"
}

print_success(){
    echo -e "${verde}$1${nc}"
}

print_info(){
    echo -e "${amarillo}$1${nc}"
}

validate_domain() {
    local domain="$1"
    local domain_regex='^([a-zA-Z0-9]([-a-zA-Z0-9]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$'
    
    if [[ ! $domain =~ $domain_regex ]]; then
        print_warning "Formato de dominio inválido: $domain"
        return 1
    fi
    
    return 0
}

validar_IP(){
    local ip="$1"

    if ! [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        print_warning "Direccion IP invalida, tiene que contener un formato X.X.X.X unicamente con numeros positivos"
        return 1
    fi
    
    IFS='.' read -r a b c d <<< "$ip"
    if [[ "$a" -eq 0  || "$d" -eq 0 ]]; then
        print_warning "Direccion IP invalida, no puede ser 0.X.X.X ni X.X.X.0"
        return 1
    fi
    
    for octeto in $a $b $c $d; do
        if [[ "$octeto" =~ ^0[0-9]+ ]]; then
            print_warning "Direccion IP invalida, no se pueden poner 0 a la izquierda a menos que sea 0"
            return 1
        fi
        if [[ "$octeto" -lt 0 || "$octeto" -gt 255 ]]; then
            print_warning "Direccion IP invalida, no puede ser mayor a 255 ni menor a 0"
            return 1
        fi
    done

    if [[ "$ip" = "0.0.0.0" || "$ip" = "255.255.255.255" ]]; then
        print_warning "Direccion IP invalida, no puede ser 0.0.0.0 ni 255.255.255.255"
        return 1
    fi

    if [[ "$a" -eq 127 ]]; then
        print_warning "Direccion IP invalida, las direcciones del rango 127.0.0.1 al 127.255.255.255 estan reservadas para host local"
        return 1
    fi

    if [[ "$a" -ge 224 && "$a" -le 239 ]]; then
        print_warning "Direccion IP invalida, las direcciones del rango 224.0.0.0 al 239.255.255.255 estan reservadas para multicast"
        return 1
    fi

    if [[ "$a" -ge 240 && "$a" -lt 255 ]]; then
        print_warning "Direccion IP invalida, las direcciones del rango 240.0.0.0 al 255.255.255.254 estan reservadas para usos experimentales"
        return 1
    fi
    
    return 0
}

verificar_Instalacion() {
    print_info "Verificando instalación de BIND9..."
    
    if rpm -q bind &>/dev/null; then
        local version=$(rpm -q bind --queryformat '%{VERSION}')
        print_success "BIND9 ya está instalado (versión: $version)"
        return 0
    fi
    
    if command -v named &>/dev/null; then
        local version=$(named -v 2>&1 | head -1)
        print_success "BIND9 encontrado: $version"
        return 0
    fi
    
    if systemctl list-unit-files 2>/dev/null | grep -q "^named.service"; then
        print_success "Servicio named encontrado en systemd"
        return 0
    fi
    
    print_warning "BIND9 no está instalado"
    return 1
}

# ---------- Configurar IP estática ----------

configurar_ip_estatica() {
    print_info "═══════════════════════════════════════"
    print_info "  Verificación de IP Estática"
    print_info "═══════════════════════════════════════"
    
    # 1. Detectar interfaz activa
    local interfaz=$(ip route | grep default | awk '{print $5}' | head -1)
    
    # Validar que se detectó una interfaz
    if [[ -z "$interfaz" ]]; then
        print_warning "No se pudo detectar una interfaz de red activa"
        echo -ne "${azul}Ingrese el nombre de la interfaz (ej: eth0, ens33): ${nc}"
        read -r interfaz
        
        # Verificar que la interfaz existe
        if ! ip link show "$interfaz" &>/dev/null; then
            print_warning "La interfaz $interfaz no existe"
            return 1
        fi
    fi
    
    print_success "Interfaz detectada: $interfaz"
    
    # 2. Ruta del archivo de configuración
    local ifcfg="/etc/sysconfig/network/ifcfg-$interfaz"
    
    # Verificar si existe el archivo de configuración
    if [[ ! -f "$ifcfg" ]]; then
        print_warning "No existe archivo de configuración: $ifcfg"
        print_info "Se creará una nueva configuración"
        
        # Detectar valores actuales
        local IP_ACTUAL=$(ip addr show "$interfaz" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
        local GATEWAY=$(ip route | grep default | awk '{print $3}')
        
        if [[ -z "$IP_ACTUAL" ]]; then
            print_warning "No se pudo detectar IP actual"
            echo -ne "${azul}Ingrese la IP fija deseada: ${nc}"
            read -r server_ip
            validar_IP "$server_ip" || return 1
            
            echo -ne "${azul}Ingrese el Gateway: ${nc}"
            read -r GATEWAY
            validar_IP "$GATEWAY" || return 1
        else
            print_info "IP actual: $IP_ACTUAL (DHCP)"
            print_info "Gateway: $GATEWAY"
            
            echo -ne "${amarillo}¿Usar estos valores como IP fija? [S/n]: ${nc}"
            read -r respuesta
            
            if [[ -z "$respuesta" ]] || [[ "$respuesta" =~ ^[Ss]$ ]]; then
                server_ip=$IP_ACTUAL
            else
                echo -ne "${azul}Ingrese la IP fija deseada: ${nc}"
                read -r server_ip
                validar_IP "$server_ip" || return 1
                
                echo -ne "${azul}Ingrese el Gateway: ${nc}"
                read -r GATEWAY
                validar_IP "$GATEWAY" || return 1
            fi
        fi
        
        # Crear configuración estática
        cat > "$ifcfg" <<EOF
BOOTPROTO='static'
IPADDR='$server_ip/24'
GATEWAY='$GATEWAY'
STARTMODE='auto'
EOF
        
        print_success "Configuración creada en $ifcfg"
        
        # Aplicar cambios
        print_info "Aplicando configuración de red..."
        wicked ifdown "$interfaz" &>/dev/null
        wicked ifup "$interfaz" &>/dev/null
        
        # Verificar conectividad
        sleep 2
        if ping -c 1 "$GATEWAY" &>/dev/null; then
            print_success "Conectividad verificada con el gateway"
        else
            print_warning "No se pudo hacer ping al gateway, verifique la configuración"
        fi
        
        print_success "IP estática configurada: $server_ip"
        export server_ip
        return 0
    fi
    
    # 3. El archivo existe, verificar si tiene IP estática
    if grep -q "BOOTPROTO=['\"]static['\"]" "$ifcfg" || grep -q "BOOTPROTO=static" "$ifcfg"; then
        # SÍ tiene IP fija
        local ip_raw=$(grep "IPADDR=" "$ifcfg" | cut -d= -f2 | tr -d "'\"")
        # Quitar /24 si existe
        server_ip=${ip_raw%/*}
        
        print_success "IP estática ya configurada: $server_ip"
        print_info "Interfaz: $interfaz"
        
        # Mostrar gateway
        local gw=$(grep "GATEWAY=" "$ifcfg" | cut -d= -f2 | tr -d "'\"" 2>/dev/null)
        if [[ -n "$gw" ]]; then
            print_info "Gateway: $gw"
        fi
        
        export server_ip
        return 0
    else
        # NO tiene IP fija → PROCESO DE ASIGNACIÓN
        print_warning "Configuración DHCP detectada en $interfaz"
        
        # Detectar valores actuales
        local IP_ACTUAL=$(ip addr show "$interfaz" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
        local GATEWAY=$(ip route | grep default | awk '{print $3}')
        
        print_info "IP actual: $IP_ACTUAL"
        print_info "Gateway: $GATEWAY"
        
        echo -ne "${amarillo}¿Desea configurar IP estática? [S/n]: ${nc}"
        read -r respuesta
        
        if [[ "$respuesta" =~ ^[Nn]$ ]]; then
            print_warning "Se mantendrá la configuración DHCP"
            print_warning "ADVERTENCIA: El servidor DNS necesita IP estática para funcionar correctamente"
            server_ip=$IP_ACTUAL
            export server_ip
            return 0
        fi
        
        echo -ne "${amarillo}¿Usar estos valores como IP fija? [S/n]: ${nc}"
        read -r respuesta
        
        if [[ -z "$respuesta" ]] || [[ "$respuesta" =~ ^[Ss]$ ]]; then
            server_ip=$IP_ACTUAL
            GW=$GATEWAY
        else
            echo -ne "${azul}Ingrese la IP fija deseada: ${nc}"
            read -r server_ip
            validar_IP "$server_ip" || return 1
            
            echo -ne "${azul}Ingrese el Gateway: ${nc}"
            read -r GW
            validar_IP "$GW" || return 1
            GATEWAY=$GW
        fi
        
        # Escribir configuración estática
        cat > "$ifcfg" <<EOF
BOOTPROTO='static'
IPADDR='$server_ip/24'
GATEWAY='$GATEWAY'
STARTMODE='auto'
EOF
        
        print_success "Configuración actualizada en $ifcfg"
        
        # Aplicar cambios
        print_info "Aplicando configuración de red..."
        wicked ifdown "$interfaz" &>/dev/null
        sleep 1
        wicked ifup "$interfaz" &>/dev/null
        sleep 2
        
        # Verificar conectividad
        if ping -c 1 "$GATEWAY" &>/dev/null; then
            print_success "Conectividad verificada con el gateway"
        else
            print_warning "No se pudo hacer ping al gateway"
        fi
        
        print_success "IP estática configurada: $server_ip"
        export server_ip
    fi
}

# ---------- Instalar BIND9 ----------

install_bind9() {
    
    configurar_ip_estatica || {
        print_warning "No se pudo configurar la IP estática"
        return 1
    }
    
    echo ""
    print_info "═══════════════════════════════════════"
    print_info "  Instalación de BIND9"
    print_info "═══════════════════════════════════════"
    
    if verificar_Instalacion; then
        print_info "BIND9 ya está instalado"
        echo -ne "${amarillo}¿Desea reconfigurar el servidor DNS? [s/N]: ${nc}"
        read -r reconf
        if [[ ! "$reconf" =~ ^[Ss]$ ]]; then
            print_info "Operación cancelada"
            return 0
        fi
    else
        print_info "Instalando BIND9 y utilidades..."

        print_info "Actualizando repositorios..."
        zypper refresh &>/dev/null

        print_info "Instalando paquete bind..."
        if zypper install -y bind &>/dev/null; then
            print_success "Paquete bind instalado correctamente"
        else
            print_warning "Error al instalar bind"
            return 1
        fi

        print_info "Instalando paquete bind-utils..."
        if zypper install -y bind-utils &>/dev/null; then
            print_success "Paquete bind-utils instalado correctamente"
        else
            print_warning "Error al instalar bind-utils (no crítico)"
        fi
    fi

    print_info "Generando archivo de configuración $named_conf..."

    if [[ ! -d "$zones_dir" ]]; then
        mkdir -p "$zones_dir"
        print_success "Directorio de zonas creado: $zones_dir"
    fi

    cat > "$named_conf" <<EOF
# Archivo de configuración de BIND9
# Generado automáticamente por dns-setup.sh
# $(date)

options {
    directory "$zones_dir";
    listen-on { any; };
    allow-query { any; };
    recursion no;
    forwarders { };
    allow-transfer { none; };
};

zone "localhost" {
    type master;
    file "localhost.zone";
};

zone "0.in-addr.arpa" {
    type master;
    file "0.in-addr.arpa.zone";
};

zone "127.in-addr.arpa" {
    type master;
    file "127.in-addr.arpa.zone";
};
EOF

    if named-checkconf "$named_conf" 2>/dev/null; then
        print_success "Archivo named.conf generado correctamente"
    else
        print_warning "Error en la sintaxis de named.conf"
        return 1
    fi

    print_info "Habilitando servicio named en el arranque..."
    if systemctl enable named 2>/dev/null; then
        print_success "Servicio named habilitado"
    else
        print_warning "No se pudo habilitar el servicio named"
        return 1
    fi

    print_info "Iniciando servicio named..."

    if systemctl is-active --quiet named; then
        print_info "Servicio ya estaba activo, reiniciando..."
        if systemctl restart named 2>/dev/null; then
            print_success "Servicio named reiniciado"
        else
            print_warning "Error al reiniciar el servicio named"
            return 1
        fi
    else
        if systemctl start named 2>/dev/null; then
            print_success "Servicio named iniciado"
        else
            print_warning "Error al iniciar el servicio named"
            print_warning "Revise los logs: journalctl -u named"
            return 1
        fi
    fi

    print_info "Configurando firewall para DNS (puerto 53)..."

    if command -v firewall-cmd &>/dev/null; then
        if firewall-cmd --add-service=dns --permanent 2>/dev/null; then
            print_success "Puerto 53 abierto en firewall (permanente)"
        else
            print_warning "No se pudo configurar el firewall"
        fi

        if firewall-cmd --reload 2>/dev/null; then
            print_success "Firewall recargado"
        else
            print_warning "No se pudo recargar el firewall"
        fi
    else
        print_warning "firewalld no encontrado, configure el firewall manualmente"
        print_warning "Abra el puerto 53 TCP y UDP"
    fi

    print_info "Verificando estado del servidor DNS..."
    echo ""

    if systemctl is-active --quiet named; then
        print_success "Servicio named: activo y corriendo"
    else
        print_warning "Servicio named: NO está corriendo"
        return 1
    fi

    if ss -tulnp 2>/dev/null | grep -q ":53 "; then
        print_success "Puerto 53: escuchando"
    else
        print_warning "Puerto 53: NO está escuchando"
    fi

    if named-checkconf "$named_conf" 2>/dev/null; then
        print_success "Configuración: sintaxis correcta"
    else
        print_warning "Configuración: hay errores de sintaxis"
    fi

    echo ""
    print_success " BIND9 instalado y configurado correctamente"
    echo ""
    print_info "IP del servidor DNS: $server_ip"
    print_info ""
    print_info "Configure su DHCP con:"
    print_info "  DNS: $server_ip"
    print_info ""
    print_info "Siguiente paso: agregar dominios con"
    print_info "  $0 --monitor"
}

# ---------- Reiniciar servidor ----------

reiniciar_DNS() {
    print_info "Reiniciando servidor DNS..."

    if systemctl restart named 2>/dev/null; then
        print_success "Servidor DNS reiniciado correctamente"

        if systemctl is-active --quiet named; then
            print_success "Servicio named: activo"
        else
            print_warning "El servicio no quedó activo después del reinicio"
        fi
    else
        print_warning "Error al reiniciar el servidor DNS"
        print_warning "Revise los logs: journalctl -u named"
        return 1
    fi
}

# ---------- Menú de Monitoreo ----------

agregar_dominio() {
    print_info "═══ Agregar Dominio ═══"

    # Pedir nombre del dominio
    echo -ne "${azul}Ingrese el nombre del dominio (ej: reprobados.com): ${nc}"
    read -r nuevo_dominio

    # Validar dominio
    if ! validate_domain "$nuevo_dominio"; then
        print_warning "Dominio inválido, cancelando operación"
        return 1
    fi

    # Verificar si el dominio ya existe
    if grep -q "zone \"$nuevo_dominio\"" "$named_conf" 2>/dev/null; then
        print_warning "El dominio $nuevo_dominio ya está configurado"
        return 1
    fi

    # Sugerir IP del servidor si está configurada
    if [[ -n "$server_ip" ]]; then
        echo -ne "${azul}Ingrese la IP para $nuevo_dominio [$server_ip]: ${nc}"
    else
        echo -ne "${azul}Ingrese la IP para $nuevo_dominio: ${nc}"
    fi
    read -r nueva_ip

    # Si está vacío y hay server_ip, usarla
    if [[ -z "$nueva_ip" ]] && [[ -n "$server_ip" ]]; then
        nueva_ip=$server_ip
    fi

    # Validar IP
    if ! validar_IP "$nueva_ip"; then
        print_warning "IP inválida, cancelando operación"
        return 1
    fi

    # Crear archivo de zona
    local zone_file="$zones_dir/${nuevo_dominio}.zone"
    local serial=$(date +%Y%m%d01)

    print_info "Creando archivo de zona: $zone_file"

    cat > "$zone_file" <<EOF
\$TTL 86400
@   IN  SOA ns1.$nuevo_dominio. admin.$nuevo_dominio. (
            $serial ; Serial
            3600        ; Refresh
            1800        ; Retry
            604800      ; Expire
            86400 )     ; Minimum TTL

; Name Server
@           IN  NS      ns1.$nuevo_dominio.

; Registros A
@           IN  A       $nueva_ip
ns1         IN  A       $nueva_ip

; Registro CNAME
www         IN  CNAME   $nuevo_dominio.
EOF

    # Verificar sintaxis del archivo de zona
    if ! named-checkzone "$nuevo_dominio" "$zone_file" &>/dev/null; then
        print_warning "Error en la sintaxis del archivo de zona"
        rm -f "$zone_file"
        return 1
    fi

    print_success "Archivo de zona creado correctamente"

    # Agregar zona a named.conf
    print_info "Agregando zona a $named_conf..."

    cat >> "$named_conf" <<EOF

zone "$nuevo_dominio" {
    type master;
    file "$zone_file";
};
EOF

    # Verificar sintaxis de named.conf
    if ! named-checkconf "$named_conf" &>/dev/null; then
        print_warning "Error en la sintaxis de named.conf"
        return 1
    fi

    print_success "Zona agregada a named.conf correctamente"

    # Recargar BIND9
    print_info "Recargando servicio BIND9..."
    if systemctl reload named 2>/dev/null; then
        print_success "Servicio recargado correctamente"
    else
        print_warning "reload falló, intentando restart..."
        if systemctl restart named 2>/dev/null; then
            print_success "Servicio reiniciado correctamente"
        else
            print_warning "No se pudo recargar el servicio"
        fi
    fi

    echo ""
    print_success "Dominio $nuevo_dominio agregado exitosamente"
    print_info "  IP configurada: $nueva_ip"
    print_info "  Registro A: $nuevo_dominio → $nueva_ip"
    print_info "  Registro CNAME: www.$nuevo_dominio → $nuevo_dominio"
    print_info "  Archivo de zona: $zone_file"
}

eliminar_dominio() {
    print_info "═══ Eliminar Dominio ═══"

    # Listar dominios disponibles
    listar_dominios
    echo ""

    # Pedir dominio a eliminar
    echo -ne "${azul}Ingrese el dominio a eliminar: ${nc}"
    read -r dominio_eliminar

    # Verificar que el dominio existe
    if ! grep -q "zone \"$dominio_eliminar\"" "$named_conf" 2>/dev/null; then
        print_warning "El dominio $dominio_eliminar no existe en la configuración"
        return 1
    fi

    # Pedir confirmación
    echo ""
    echo -ne "${rojo}¿Está seguro de eliminar el dominio $dominio_eliminar? [s/N]: ${nc}"
    read -r confirmacion

    if [[ ! "$confirmacion" =~ ^[Ss]$ ]]; then
        print_info "Operación cancelada por el usuario"
        return 0
    fi

    local zone_file="$zones_dir/${dominio_eliminar}.zone"

    # Eliminar entrada de named.conf
    print_info "Eliminando entrada de named.conf..."
    sed -i "/zone \"$dominio_eliminar\"/,/^};/d" "$named_conf"

    # Verificar sintaxis
    if named-checkconf "$named_conf" 2>/dev/null; then
        print_success "Entrada eliminada de named.conf"
    else
        print_warning "Error en named.conf después de eliminar"
        return 1
    fi

    # Eliminar archivo de zona
    if [[ -f "$zone_file" ]]; then
        print_info "Eliminando archivo de zona: $zone_file"
        rm -f "$zone_file"
        print_success "Archivo de zona eliminado"
    else
        print_warning "Archivo de zona no encontrado: $zone_file"
    fi

    # Recargar BIND9
    print_info "Recargando servicio BIND9..."
    if systemctl reload named 2>/dev/null; then
        print_success "Servicio recargado correctamente"
    else
        print_warning "reload falló, intentando restart..."
        if systemctl restart named 2>/dev/null; then
            print_success "Servicio reiniciado correctamente"
        fi
    fi

    print_success "Dominio $dominio_eliminar eliminado exitosamente"
}

listar_dominios() {
    print_info "═══ Dominios Configurados ═══"

    # Verificar que named.conf existe
    if [[ ! -f "$named_conf" ]]; then
        print_warning "No se encontró el archivo $named_conf"
        return 1
    fi

    # Extraer zonas configuradas
    local dominios=($(grep "^zone " "$named_conf" | awk -F'"' '{print $2}' | grep -v "localhost\|0.in-addr\|127.in-addr"))

    if [[ ${#dominios[@]} -eq 0 ]]; then
        print_warning "No hay dominios configurados"
        return 0
    fi

    # Encabezado de tabla
    echo ""
    printf "${azul}%-30s %-20s %-15s${nc}\n" "DOMINIO" "IP CONFIGURADA" "ESTADO"
    echo "──────────────────────────────────────────────────────────────"

    # Mostrar cada dominio
    for dominio in "${dominios[@]}"; do
        local zone_file="$zones_dir/${dominio}.zone"
        local ip="N/A"
        local estado="${rojo}Sin archivo${nc}"

        if [[ -f "$zone_file" ]]; then
            ip=$(grep "^@[[:space:]]*IN[[:space:]]*A" "$zone_file" 2>/dev/null | awk '{print $NF}')
            [[ -z "$ip" ]] && ip="N/A"
            estado="${verde}Activo${nc}"
        fi

        printf "%-30s %-20s " "$dominio" "$ip"
        echo -e "$estado"
    done

    echo ""
    print_info "Total de dominios: ${#dominios[@]}"
}

monitoreo() {
    while true; do
        echo ""
        echo -e "${cyan}"
        echo "╔════════════════════════════════════════════════════════════╗"
        echo "║              Menú de Monitoreo DNS                        ║"
        echo "╚════════════════════════════════════════════════════════════╝"
        echo -e "${nc}"

        echo -e "  ${verde}1)${nc} Agregar dominio"
        echo -e "  ${rojo}2)${nc} Eliminar dominio"
        echo -e "  ${azul}3)${nc} Listar dominios"
        echo -e "  ${amarillo}0)${nc} Salir"
        echo ""
        echo -ne "Opcion: "
        read -r opcion

        case $opcion in
            1) agregar_dominio ;;
            2) eliminar_dominio ;;
            3) listar_dominios ;;
            0)
                print_info "Saliendo del menú de monitoreo"
                break
                ;;
            *)
                print_warning "Opcion inválida: $opcion"
                ;;
        esac
    done
}

# ---------- Main ----------
case $1 in
    -v | --verify)   verificar_Instalacion ;;
    -i | --install)  install_bind9 ;;
    -m | --monitor)  monitoreo ;;
    -r | --restart)  reiniciar_DNS ;;
    -? | --help)     ayuda ;;
    *)               ayuda ;;
esac