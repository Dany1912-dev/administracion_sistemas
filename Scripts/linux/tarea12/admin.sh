#!/bin/bash

DOMINIO="reprobados.com"

# ── Fail2ban ──────────────────────────────────────────────────────────────────

menu_fail2ban() {
    while true; do
        echo ""
        echo "======================================================"
        echo "  Fail2ban — $DOMINIO"
        echo "======================================================"
        echo "  1) Ver IPs baneadas"
        echo "  2) Desbanear una IP"
        echo "  3) Volver"
        echo "======================================================"
        read -rp "  Opción: " OPCION
        echo ""

        case "$OPCION" in
            1)
                echo "  Jails activas:"
                docker exec mailserver fail2ban-client status 2>/dev/null | \
                    grep "Jail list" | sed 's/.*Jail list:\s*//' | tr ',' '\n' | \
                    sed 's/^\s*/    /'
                echo ""
                echo "  Detalle — dovecot:"
                docker exec mailserver fail2ban-client status dovecot 2>/dev/null | \
                    sed 's/^/    /'
                echo ""
                echo "  Detalle — postfix:"
                docker exec mailserver fail2ban-client status postfix 2>/dev/null | \
                    sed 's/^/    /'
                echo ""
                ;;
            2)
                echo "  IPs baneadas actualmente:"
                docker exec mailserver fail2ban-client status dovecot 2>/dev/null | \
                    grep "Banned IP" | sed 's/.*Banned IP list:\s*//' | tr ' ' '\n' | \
                    sed '/^$/d' | sed 's/^/    /'
                echo ""
                read -rp "  IP a desbanear: " IP
                if [[ -z "$IP" ]]; then
                    echo "  [ERROR] IP no puede estar vacía"
                    continue
                fi
                echo "  Desbaneando en todas las jails..."
                for JAIL in dovecot postfix; do
                    docker exec mailserver fail2ban-client set "$JAIL" unbanip "$IP" 2>/dev/null && \
                        echo "  [OK] $IP desbaneada en $JAIL" || \
                        echo "  [INFO] $IP no estaba baneada en $JAIL"
                done
                ;;
            3) return ;;
            *) echo "  [ERROR] Opción inválida" ;;
        esac
    done
}

# ── Logs ──────────────────────────────────────────────────────────────────────

menu_logs() {
    while true; do
        echo ""
        echo "======================================================"
        echo "  Logs — $DOMINIO"
        echo "======================================================"
        echo "  1) Últimas 50 líneas del log de correo"
        echo "  2) Buscar logs por usuario"
        echo "  3) Ver estado de los contenedores"
        echo "  4) Volver"
        echo "======================================================"
        read -rp "  Opción: " OPCION
        echo ""

        case "$OPCION" in
            1)
                docker exec mailserver tail -n 50 /var/log/mail/mail.log 2>/dev/null || \
                    tail -n 50 logs/mail.log 2>/dev/null || \
                    echo "  [ERROR] No se pudo leer el log"
                ;;
            2)
                read -rp "  Usuario a buscar (sin @$DOMINIO): " USUARIO
                if [[ -z "$USUARIO" ]]; then
                    echo "  [ERROR] Usuario no puede estar vacío"
                    continue
                fi
                docker exec mailserver grep "${USUARIO}@${DOMINIO}" /var/log/mail/mail.log 2>/dev/null | \
                    tail -n 30 | sed 's/^/  /' || \
                    echo "  [ERROR] No se pudo leer el log"
                ;;
            3)
                docker compose ps
                ;;
            4) return ;;
            *) echo "  [ERROR] Opción inválida" ;;
        esac
    done
}

# ── Menú principal ────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

while true; do
    echo ""
    echo "======================================================"
    echo "  Administración — $DOMINIO"
    echo "======================================================"
    echo "  1) Gestionar correos"
    echo "  2) Fail2ban (IPs baneadas / desbanear)"
    echo "  3) Logs y estado"
    echo "  4) Regenerar certificados SSL"
    echo "  5) Salir"
    echo "======================================================"
    read -rp "  Opción: " OPCION
    echo ""

    case "$OPCION" in
        1) bash "$SCRIPT_DIR/gestionar-correos.sh" ;;
        2) menu_fail2ban ;;
        3) menu_logs ;;
        4) bash "$SCRIPT_DIR/generar-certs.sh" ;;
        5) echo "  Hasta luego."; exit 0 ;;
        *) echo "  [ERROR] Opción inválida" ;;
    esac
done
