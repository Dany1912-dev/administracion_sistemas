#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/validaciones.sh"
source "$SCRIPT_DIR/funciones_http.sh"

readonly INTERFAZ_RED="enp0s9"
readonly PUERTOS_RESERVADOS=(22 21 23 25 53 443 3306 5432 6379 27017)
readonly APACHE_WEBROOT="/srv/www/apache"
readonly NGINX_WEBROOT="/srv/www/nginx"
readonly TOMCAT_WEBROOT="/opt/tomcat/webapps/ROOT"

if [[ "$1" == "-i" || "$1" == "--instalar" ]]; then
    instalar_HTTP
elif [[ "$1" == "-v" || "$1" == "--verificar" ]]; then
    verificar_HTTP
elif [[ "$1" == "-r" || "$1" == "--revisar" ]]; then
    revisar_HTTP
else
    echo ""
    echo -e "  ${amarillo}-i${nc}  Instalar servidor HTTP"
    echo -e "  ${amarillo}-v${nc}  Ver estado de servidores"
    echo -e "  ${amarillo}-r${nc}  Revisar respuesta HTTP (curl)"
    echo ""
fi
