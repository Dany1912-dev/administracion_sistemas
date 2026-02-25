ayuda() {
    # Todas las opciones
    echo "Uso del script: $0"
    echo "Opciones:"
    echo -e "  -dh, --dhcp       Entrar al entorno DHCP"
    echo -e "  -dn, --dns      Entrar al entorno DNS"
    echo -e "  -?, --help         Muestra esta ayuda/menu"
}

entorno_dhcp() {
    echo "Entrando al entorno DHCP..."
    bash "/home/dleyva/administracion_sistemas/Scripts/linux/tarea2/tarea2_DHCP_automatizado.sh" "$2"

}

entorno_dns() {
    echo "Entrando al entorno DNS..."
    bash "/home/dleyva/administracion_sistemas/Scripts/linux/tarea3/tarea3_DNS_automatizado.sh" "$2"

}
case $1 in
    -dh | --dhcp) entorno_dhcp ;;
    -dn | --dns) entorno_dns ;;
    -? | --help) ayuda ;;
esac