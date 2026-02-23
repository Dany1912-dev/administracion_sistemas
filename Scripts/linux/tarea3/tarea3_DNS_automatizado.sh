# Tarea 2 - Automatizacion y gestion del servidor DNS (BIND9)
# ---------- Cargar libreria compartida ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/validaciones.sh"

# ---------- Variables globales ----------
server_ip=""
named_conf="/etc/named.conf"
zones_dir="/var/lib/named"

# ---------- Funciones ----------

ayuda() {
    echo "Uso del script: $0"
    echo "Opciones:"
    echo -e "  -v, --verify       Verifica si esta instalado BIND9"
    echo -e "  -i, --install      Instala y configura BIND9"
    echo -e "  -m, --monitor      Monitorear servidor DNS"
    echo -e "  -r, --restart      Reiniciar servidor DNS"
    echo -e "  -s, --status       Verificar estado del servidor DNS"
    echo -e "  -?, --help         Muestra esta ayuda"
}

verificar_Instalacion() {
    print_info "Verificando instalación de BIND9..."

    if rpm -q bind &>/dev/null; then
        local version=$(rpm -q bind --queryformat '%{VERSION}')
        print_completado "BIND9 ya está instalado (versión: $version)"
        return 0
    fi

    if command -v named &>/dev/null; then
        local version=$(named -v 2>&1 | head -1)
        print_completado "BIND9 encontrado: $version"
        return 0
    fi

    if systemctl list-unit-files 2>/dev/null | grep -q "^named.service"; then
        print_completado "Servicio named encontrado en systemd"
        return 0
    fi

    print_error "BIND9 no está instalado"
    return 1
}

configurar_ip_estatica() {
    print_info "═══════════════════════════════════════"
    print_info "  Verificación de IP Estática"
    print_info "═══════════════════════════════════════"

    local interfaz="enp0s8"

    if [[ -z "$interfaz" ]]; then
        print_error "No se pudo detectar una interfaz de red activa"
        echo -ne "${azul}Ingrese el nombre de la interfaz (ej: eth0, ens33): ${nc}"
        read -r interfaz

        if ! ip link show "$interfaz" &>/dev/null; then
            print_error "La interfaz $interfaz no existe"
            return 1
        fi
    fi

    print_completado "Interfaz detectada: $interfaz"
    local ifcfg="/etc/sysconfig/network/ifcfg-$interfaz"

    if [[ ! -f "$ifcfg" ]]; then
        print_error "No existe archivo de configuración: $ifcfg"
        print_info "Se creará una nueva configuración"

        local IP_ACTUAL=$(ip addr show "$interfaz" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
        local GATEWAY=$(ip route | grep default | awk '{print $3}')

        if [[ -z "$IP_ACTUAL" ]]; then
            print_error "No se pudo detectar IP actual"
            print_info "Ingrese la IP fija deseada: "
            read -r server_ip
            validar_IP "$server_ip" || return 1

            print_info "Ingrese el Gateway: "
            read -r GATEWAY
            validar_IP "$GATEWAY" || return 1
        else
            print_info "IP actual: $IP_ACTUAL (DHCP)"
            print_info "Gateway: $GATEWAY"

            print_info "¿Usar estos valores como IP fija? [S/n]: "
            read -r respuesta

            if [[ -z "$respuesta" ]] || [[ "$respuesta" =~ ^[Ss]$ ]]; then
                server_ip=$IP_ACTUAL
            else
                print_info "Ingrese la IP fija deseada: "
                read -r server_ip
                validar_IP "$server_ip" || return 1

                print_info "Ingrese el Gateway: "
                read -r GATEWAY
                validar_IP "$GATEWAY" || return 1
            fi
        fi

        cat > "$ifcfg" <<EOF
BOOTPROTO='static'
IPADDR='$server_ip/24'
GATEWAY='$GATEWAY'
STARTMODE='auto'
EOF

        print_completado "Configuración creada en $ifcfg"
        print_info "Aplicando configuración de red..."
        wicked ifdown "$interfaz" &>/dev/null
        wicked ifup "$interfaz" &>/dev/null

        sleep 2
        if ping -c 1 "$GATEWAY" &>/dev/null; then
            print_completado "Conectividad verificada con el gateway"
        else
            print_error "No se pudo hacer ping al gateway, verifique la configuración"
        fi

        print_completado "IP estática configurada: $server_ip"
        export server_ip
        return 0
    fi

    if grep -q "BOOTPROTO=['\"]static['\"]" "$ifcfg" || grep -q "BOOTPROTO=static" "$ifcfg"; then
        local ip_raw=$(grep "IPADDR=" "$ifcfg" | cut -d= -f2 | tr -d "'\"")
        server_ip=${ip_raw%/*}

        print_completado "IP estática ya configurada: $server_ip"
        print_info "Interfaz: $interfaz"

        local gw=$(grep "GATEWAY=" "$ifcfg" | cut -d= -f2 | tr -d "'\"" 2>/dev/null)
        if [[ -n "$gw" ]]; then
            print_info "Gateway: $gw"
        fi

        export server_ip
        return 0
    else
        print_error "Configuración DHCP detectada en $interfaz"

        local IP_ACTUAL=$(ip addr show "$interfaz" | grep "inet " | awk '{print $2}' | cut -d/ -f1)
        local GATEWAY=$(ip route | grep default | awk '{print $3}')

        print_info "IP actual: $IP_ACTUAL"
        print_info "Gateway: $GATEWAY"

        print_info "¿Desea configurar IP estática? [S/n]: "
        read -r respuesta

        if [[ "$respuesta" =~ ^[Nn]$ ]]; then
            print_error "Se mantendrá la configuración DHCP"
            print_error "ADVERTENCIA: El servidor DNS necesita IP estática para funcionar correctamente"
            server_ip=$IP_ACTUAL
            export server_ip
            return 0
        fi

        print_info "¿Usar estos valores como IP fija? [S/n]: "
        read -r respuesta

        if [[ -z "$respuesta" ]] || [[ "$respuesta" =~ ^[Ss]$ ]]; then
            server_ip=$IP_ACTUAL
            GW=$GATEWAY
        else
            print_info "Ingrese la IP fija deseada: "
            read -r server_ip
            validar_IP "$server_ip" || return 1

            print_info "Ingrese el Gateway: "
            read -r GW
            validar_IP "$GW" || return 1
            GATEWAY=$GW
        fi

        cat > "$ifcfg" <<EOF
BOOTPROTO='static'
IPADDR='$server_ip/24'
GATEWAY='$GATEWAY'
STARTMODE='auto'
EOF

        print_completado "Configuración actualizada en $ifcfg"
        print_info "Aplicando configuración de red..."
        wicked ifdown "$interfaz" &>/dev/null
        sleep 1
        wicked ifup "$interfaz" &>/dev/null
        sleep 2

        if ping -c 1 "$GATEWAY" &>/dev/null; then
            print_completado "Conectividad verificada con el gateway"
        else
            print_error "No se pudo hacer ping al gateway"
        fi

        print_completado "IP estática configurada: $server_ip"
        export server_ip
    fi
}

install_bind9() {
    configurar_ip_estatica || {
        print_error "No se pudo configurar la IP estática"
        return 1
    }

    echo ""
    print_info "═══════════════════════════════════════"
    print_info "  Instalación de BIND9"
    print_info "═══════════════════════════════════════"

    if verificar_Instalacion; then
        print_info "BIND9 ya está instalado"
        print_info "¿Desea reconfigurar el servidor DNS? [s/N]: "
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
            print_completado "Paquete bind instalado correctamente"
        else
            print_error "Error al instalar bind"
            return 1
        fi

        print_info "Instalando paquete bind-utils..."
        if zypper install -y bind-utils &>/dev/null; then
            print_completado "Paquete bind-utils instalado correctamente"
        else
            print_error "Error al instalar bind-utils (no crítico)"
        fi
    fi

    print_info "Generando archivo de configuración $named_conf..."

    if [[ ! -d "$zones_dir" ]]; then
        mkdir -p "$zones_dir"
        print_completado "Directorio de zonas creado: $zones_dir"
    fi

    cat > "$named_conf" <<EOF
# Archivo de configuración de BIND9
# Generado automáticamente por dns.sh
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
        print_completado "Archivo named.conf generado correctamente"
    else
        print_error "Error en la sintaxis de named.conf"
        return 1
    fi

    print_info "Habilitando servicio named en el arranque..."
    if systemctl enable named 2>/dev/null; then
        print_completado "Servicio named habilitado"
    else
        print_error "No se pudo habilitar el servicio named"
        return 1
    fi

    print_info "Iniciando servicio named..."
    if systemctl is-active --quiet named; then
        print_info "Servicio ya estaba activo, reiniciando..."
        if systemctl restart named 2>/dev/null; then
            print_completado "Servicio named reiniciado"
        else
            print_error "Error al reiniciar el servicio named"
            return 1
        fi
    else
        if systemctl start named 2>/dev/null; then
            print_completado "Servicio named iniciado"
        else
            print_error "Error al iniciar el servicio named"
            print_error "Revise los logs: journalctl -u named"
            return 1
        fi
    fi

    print_info "Configurando firewall para DNS (puerto 53)..."
    if command -v firewall-cmd &>/dev/null; then
        if firewall-cmd --add-service=dns --permanent 2>/dev/null; then
            print_completado "Puerto 53 abierto en firewall (permanente)"
        else
            print_error "No se pudo configurar el firewall"
        fi

        if firewall-cmd --reload 2>/dev/null; then
            print_completado "Firewall recargado"
        else
            print_error "No se pudo recargar el firewall"
        fi
    else
        print_error "firewalld no encontrado, configure el firewall manualmente"
        print_error "Abra el puerto 53 TCP y UDP"
    fi

    print_info "Verificando estado del servidor DNS..."
    echo ""

    if systemctl is-active --quiet named; then
        print_completado "Servicio named: activo y corriendo"
    else
        print_error "Servicio named: NO está corriendo"
        return 1
    fi

    if ss -tulnp 2>/dev/null | grep -q ":53 "; then
        print_completado "Puerto 53: escuchando"
    else
        print_error "Puerto 53: NO está escuchando"
    fi

    if named-checkconf "$named_conf" 2>/dev/null; then
        print_completado "Configuración: sintaxis correcta"
    else
        print_error "Configuración: hay errores de sintaxis"
    fi

    echo ""
    print_completado "BIND9 instalado y configurado correctamente"
    echo ""
    print_info "IP del servidor DNS: $server_ip"
    print_info "Configure su DHCP con DNS: $server_ip"
    print_info "Siguiente paso: agregar dominios con $0 --monitor"
}

reiniciar_DNS() {
    print_info "Reiniciando servidor DNS..."

    if systemctl restart named 2>/dev/null; then
        print_completado "Servidor DNS reiniciado correctamente"

        if systemctl is-active --quiet named; then
            print_completado "Servicio named: activo"
        else
            print_error "El servicio no quedó activo después del reinicio"
        fi
    else
        print_error "Error al reiniciar el servidor DNS"
        print_error "Revise los logs: journalctl -u named"
        return 1
    fi
}

agregar_dominio() {
    print_info "═══ Agregar Dominio ═══"

    echo -ne "${azul}Ingrese el nombre del dominio (ej: reprobados.com): ${nc}"
    read -r nuevo_dominio

    if ! validar_Dominio "$nuevo_dominio"; then
        print_error "Dominio inválido, cancelando operación"
        return 1
    fi

    if grep -q "zone \"$nuevo_dominio\"" "$named_conf" 2>/dev/null; then
        print_error "El dominio $nuevo_dominio ya está configurado"
        return 1
    fi

    if [[ -n "$server_ip" ]]; then
        print_info "Ingrese la IP para $nuevo_dominio [$server_ip]: "
    else
        print_info "Ingrese la IP para $nuevo_dominio: "
    fi
    read -r nueva_ip

    if [[ -z "$nueva_ip" ]] && [[ -n "$server_ip" ]]; then
        nueva_ip=$server_ip
    fi

    if ! validar_IP "$nueva_ip"; then
        print_error "IP inválida, cancelando operación"
        return 1
    fi

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

    if ! named-checkzone "$nuevo_dominio" "$zone_file" &>/dev/null; then
        print_error "Error en la sintaxis del archivo de zona"
        rm -f "$zone_file"
        return 1
    fi

    print_completado "Archivo de zona creado correctamente"
    print_info "Agregando zona a $named_conf..."

    cat >> "$named_conf" <<EOF

zone "$nuevo_dominio" {
    type master;
    file "$zone_file";
};
EOF

    if ! named-checkconf "$named_conf" &>/dev/null; then
        print_error "Error en la sintaxis de named.conf"
        return 1
    fi

    print_completado "Zona agregada a named.conf correctamente"
    print_info "Recargando servicio BIND9..."

    if systemctl reload named 2>/dev/null; then
        print_completado "Servicio recargado correctamente"
    else
        print_error "reload falló, intentando restart..."
        if systemctl restart named 2>/dev/null; then
            print_completado "Servicio reiniciado correctamente"
        else
            print_error "No se pudo recargar el servicio"
        fi
    fi

    echo ""
    print_completado "Dominio $nuevo_dominio agregado exitosamente"
    print_info "  IP configurada: $nueva_ip"
    print_info "  Registro A: $nuevo_dominio → $nueva_ip"
    print_info "  Registro CNAME: www.$nuevo_dominio → $nuevo_dominio"
    print_info "  Archivo de zona: $zone_file"
}

eliminar_dominio() {
    print_info "═══ Eliminar Dominio ═══"

    listar_dominios
    echo ""

    echo -ne "${azul}Ingrese el dominio a eliminar: ${nc}"
    read -r dominio_eliminar

    if ! grep -q "zone \"$dominio_eliminar\"" "$named_conf" 2>/dev/null; then
        print_error "El dominio $dominio_eliminar no existe en la configuración"
        return 1
    fi

    echo ""
    echo -ne "${rojo}¿Está seguro de eliminar el dominio $dominio_eliminar? [s/N]: ${nc}"
    read -r confirmacion

    if [[ ! "$confirmacion" =~ ^[Ss]$ ]]; then
        print_info "Operación cancelada por el usuario"
        return 0
    fi

    local zone_file="$zones_dir/${dominio_eliminar}.zone"

    print_info "Eliminando entrada de named.conf..."
    sed -i "/zone \"$dominio_eliminar\"/,/^};/d" "$named_conf"

    if named-checkconf "$named_conf" 2>/dev/null; then
        print_completado "Entrada eliminada de named.conf"
    else
        print_error "Error en named.conf después de eliminar"
        return 1
    fi

    if [[ -f "$zone_file" ]]; then
        print_info "Eliminando archivo de zona: $zone_file"
        rm -f "$zone_file"
        print_completado "Archivo de zona eliminado"
    else
        print_error "Archivo de zona no encontrado: $zone_file"
    fi

    print_info "Recargando servicio BIND9..."
    if systemctl reload named 2>/dev/null; then
        print_completado "Servicio recargado correctamente"
    else
        print_error "reload falló, intentando restart..."
        if systemctl restart named 2>/dev/null; then
            print_completado "Servicio reiniciado correctamente"
        fi
    fi

    print_completado "Dominio $dominio_eliminar eliminado exitosamente"
}

listar_dominios() {
    print_info "═══ Dominios Configurados ═══"

    if [[ ! -f "$named_conf" ]]; then
        print_error "No se encontró el archivo $named_conf"
        return 1
    fi

    local dominios=($(grep "^zone " "$named_conf" | awk -F'"' '{print $2}' | grep -v "localhost\|0.in-addr\|127.in-addr"))

    if [[ ${#dominios[@]} -eq 0 ]]; then
        print_error "No hay dominios configurados"
        return 0
    fi

    echo ""
    printf "${azul}%-30s %-20s %-15s${nc}\n" "DOMINIO" "IP CONFIGURADA" "ESTADO"
    echo "──────────────────────────────────────────────────────────────"

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
                print_error "Opcion inválida: $opcion"
                ;;
        esac
    done
}

# ---------- Main ----------
case $1 in
    -v | --verify)  verificar_Instalacion ;;
    -i | --install) install_bind9 ;;
    -m | --monitor) monitoreo ;;
    -r | --restart) reiniciar_DNS ;;
    -? | --help)    ayuda ;;
    *)              ayuda ;;
esac
