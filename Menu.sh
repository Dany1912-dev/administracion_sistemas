ayuda() {
    # Todas las opciones
    echo "Uso del script: $0"
    echo "Opciones:"
    echo -e "  -sh, --dhcp       Entrar al entorno DHCP"
    echo -e "  -dn, --dns      Entrar al entorno DNS"
    echo -e "  -?, --help         Muestra esta ayuda/menu"
}

entorno_dhcp() {
    echo "Entrando al entorno DHCP..."
    source "$SCRIPT_DIR/Scripts/linux/tarea2/tarea2_DHCP_automatizado.sh"
}

entorno_dns() {
    echo "Entrando al entorno DNS..."
    source "$SCRIPT_DIR/Scripts/linux/tarea3/tarea3_DNS_automatizado.sh"

case $1 in
    -dh | --dhcp) entorno_dhcp ;;
    -dn | --dns) entorno_dns ;;
    -? | --help) ayuda ;;
esac