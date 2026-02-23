SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/validaciones.sh"

# Variables Globales
ssh-conf="/etc/ssh/sshd_config"
ssh_conf_dir="/etc/ssh/sshd_config.d"

ayuda() {
    echo "Uso del script: $0"
    echo "Opciones:"
    echo -e "  -v, --verify       Verifica si esta instalado SSH"
    echo -e "  -i, --install      Instala y configura SSH"
    echo -e "  -r, --restart      Reiniciar servidor SSH"
    echo -e "  -s, --status       Verificar estado del servidor SSH"
    echo -e "  -?, --help         Muestra esta ayuda"
}

verificar_Instalacion() {
    print_info "Verificando instalación de SSH"

    if rpm -q openssh-server &>/dev/null; then
        local version=$(rpm -q openssh-server --queryformat '%{VERSION}')
        print_completado "SSH ya está instalado (versión: $version)"
        return 0
    fi

    if command -v sshd &>/dev/null; then
        local version=$(sshd -v 2>&1 | head -1)
        print_completado "SSH encontrado: $version"
        return 0
    fi

    print_error "SSH no está instalado"
    return 1
}

instalar_SSH() {
    print_titulo "=== Instalación y Configuración de SSH ==="
    echo ""

    # 1. Verificar si SSH ya está instalado
    if verificar_Instalacion; then
        print_info "¿Desea reconfigurar el servidor SSH? [s/N]: "
        read -r reconf
        if [[ ! "$reconf" =~ ^[Ss]$ ]]; then
            print_info "Operación cancelada"
            return 0
        fi
    else
        print_info "Instalando openssh-server..."

        sudo zypper --non-interactive --quiet install openssh-server > /dev/null 2>&1 &
        pid=$!

        print_info "SSH se está instalando..."
        wait $pid

        if [ $? -eq 0 ]; then
            print_completado "SSH instalado correctamente"
        else
            print_error "Error en la instalación de SSH"
            return 1
        fi
    fi

    echo ""

    # 2. Activar y habilitar el servicio
    print_info "Habilitando servicio SSH en el arranque..."
    if sudo systemctl enable sshd 2>/dev/null; then
        print_completado "Servicio sshd habilitado"
    else
        print_error "No se pudo habilitar el servicio sshd"
        return 1
    fi

    print_info "Iniciando servicio SSH..."
    if systemctl is-active --quiet sshd; then
        print_info "Servicio ya estaba activo, reiniciando..."
        if sudo systemctl restart sshd 2>/dev/null; then
            print_completado "Servicio sshd reiniciado"
        else
            print_error "Error al reiniciar el servicio sshd"
            return 1
        fi
    else
        if sudo systemctl start sshd 2>/dev/null; then
            print_completado "Servicio sshd iniciado"
        else
            print_error "Error al iniciar el servicio sshd"
            print_error "Revise los logs: journalctl -u sshd"
            return 1
        fi
    fi

    # 3. Obtener el puerto configurado
    local puerto=$(grep -rE "^Port " "$ssh_conf" "$sshd_conf_dir"/*.conf 2>/dev/null | awk '{print $NF}' | head -1)
    puerto=${puerto:-22}

    print_info "Puerto SSH configurado: $puerto"

    # 4. Abrir puerto en el firewall
    print_info "Configurando firewall para SSH (puerto $puerto)..."
    if command -v firewall-cmd &>/dev/null; then
        if sudo firewall-cmd --add-port="$puerto"/tcp --permanent 2>/dev/null; then
            print_completado "Puerto $puerto/tcp abierto en firewall (permanente)"
        else
            print_error "No se pudo configurar el firewall"
        fi

        if sudo firewall-cmd --reload 2>/dev/null; then
            print_completado "Firewall recargado"
        else
            print_error "No se pudo recargar el firewall"
        fi
    else
        print_error "firewalld no encontrado, configure el firewall manualmente"
        print_error "Abra el puerto $puerto TCP"
    fi

    # 5. Verificacion final
    echo ""
    print_info "Verificando estado del servidor SSH..."
    echo ""

    if systemctl is-active --quiet sshd; then
        print_completado "Servicio sshd: activo y corriendo"
    else
        print_error "Servicio sshd: NO está corriendo"
        return 1
    fi

    if ss -tulnp 2>/dev/null | grep -q ":$puerto "; then
        print_completado "Puerto $puerto: escuchando"
    else
        print_error "Puerto $puerto: NO está escuchando"
    fi

    # 6. Resumen
    local ip=$(ip addr show enp0s8 | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    echo ""
    print_completado "══════════════════════════════════════"
    print_completado "  SSH listo para conexiones remotas"
    print_completado "══════════════════════════════════════"
    print_info "  IP del servidor : ${verde}$ip${nc}"
    print_info "  Puerto          : ${verde}$puerto${nc}"
    print_info "  Comando SSH     : ${verde}ssh usuario@$ip -p $puerto${nc}"
    print_completado "══════════════════════════════════════"
}

reiniciar_SSH() {
    print_info "Reiniciando servidor SSH..."

    if ! systemctl is-active --quiet sshd; then
        print_error "El servicio SSH no está activo"
        read -p "¿Desea iniciarlo en lugar de reiniciarlo? (y/n): " opc
        if [[ "$opc" = "y" ]]; then
            sudo systemctl start sshd
        else
            return 1
        fi
    else
        sudo systemctl restart sshd
    fi

    if systemctl is-active --quiet sshd; then
        print_completado "Servidor SSH reiniciado correctamente"
        sudo systemctl status sshd --no-pager
    else
        print_error "Error al reiniciar el servidor SSH"
        print_info "Ejecute: sudo journalctl -xeu sshd.service"
    fi
}

ver_Estado() {
    print_titulo "=== ESTADO DEL SERVIDOR SSH ==="
    sudo systemctl status sshd --no-pager
}

case $1 in
    -v | --verify)  verificar_Instalacion ;;
    -i | --install) instalar_SSH ;;
    -m | --status) ver_Estado ;;
    -r | --restart) reiniciar_ssh ;;
    -? | --help)    ayuda ;;
    *)              ayuda ;;
esac