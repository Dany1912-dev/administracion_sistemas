#!/bin/bash

# ============================================================================
# Práctica 7 - Instalación Híbrida con SSL/TLS
# Combina: Descarga FTP + Instalación (funciones existentes) + SSL
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar funciones existentes
source "$SCRIPT_DIR/../tarea6/funciones_http.sh"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/validaciones.sh"

# Variables globales requeridas por funciones_http.sh
readonly INTERFAZ_RED="enp0s9"
readonly PUERTOS_RESERVADOS=(22 21 23 25 53 443 3306 5432 6379 27017)
readonly APACHE_WEBROOT="/srv/www/apache"
readonly NGINX_WEBROOT="/srv/www/nginx"
readonly TOMCAT_WEBROOT="/opt/tomcat/webapps/ROOT"

# Variables globales de Práctica 7
readonly FTP_SERVER="192.168.1.68"
readonly FTP_USER="ftprepo"
readonly FTP_PASS="Repo123!"
readonly FTP_BASE_PATH="/http/Linux"
readonly TMP_DIR="/tmp/practica7"
readonly SSL_DIR="/etc/ssl/practica7"

SERVICIO_ACTUAL=""
FUENTE_INSTALACION=""
CONFIGURAR_SSL="N"

# ============================================================================
# FUNCIÓN: Preparar entorno (crear directorios, verificar OpenSSL)
# ============================================================================
preparar_entorno() {
    mkdir -p "$TMP_DIR"
    mkdir -p "$SSL_DIR"/{certs,private}
    chmod 700 "$SSL_DIR/private"
    
    # Verificar OpenSSL
    if ! command -v openssl &>/dev/null; then
        print_info "Instalando OpenSSL..."
        zypper --non-interactive install openssl-3 &>/dev/null
    fi
}

# ============================================================================
# FUNCIÓN: Menú principal
# ============================================================================
menu_principal() {
    clear
    print_titulo "════════════════════════════════════════════════════"
    print_titulo "  Práctica 7 - Instalación Híbrida con SSL/TLS"
    print_titulo "════════════════════════════════════════════════════"
    echo ""
    print_info "Seleccione el servicio a instalar:"
    echo ""
    echo "  [1] Apache HTTP Server"
    echo "  [2] Nginx"
    echo "  [3] Apache Tomcat"
    echo "  [0] Salir"
    echo ""
    read -p "Opción: " opcion
    
    case $opcion in
        1) SERVICIO_ACTUAL="Apache" ;;
        2) SERVICIO_ACTUAL="Nginx" ;;
        3) SERVICIO_ACTUAL="Tomcat" ;;
        0) exit 0 ;;
        *) print_error "Opción inválida"; menu_principal ;;
    esac
}

# ============================================================================
# FUNCIÓN: Seleccionar fuente
# ============================================================================
seleccionar_fuente() {
    echo ""
    print_info "¿Desde dónde desea instalar $SERVICIO_ACTUAL?"
    echo ""
    echo "  [W] WEB - Repositorios oficiales (zypper)"
    echo "  [F] FTP - Repositorio privado"
    echo ""
    read -p "Seleccione [W/F]: " fuente
    
    case ${fuente^^} in
        W) FUENTE_INSTALACION="WEB" ;;
        F) FUENTE_INSTALACION="FTP" ;;
        *) print_error "Opción inválida"; seleccionar_fuente ;;
    esac
}

# ============================================================================
# FUNCIÓN: Descargar desde FTP (práctica 7)
# ============================================================================
descargar_desde_ftp() {
    local servicio="$1"
    local ftp_path="${FTP_BASE_PATH}/${servicio}/"
    
    print_titulo "Conectando al Repositorio FTP"
    
    # Listar versiones disponibles
    local archivos=$(curl -s -u "${FTP_USER}:${FTP_PASS}" \
        "ftp://${FTP_SERVER}${ftp_path}" --list-only | \
        grep -v ".sha256" | grep -E "\.(tar\.gz|zip)$")
    
    if [ -z "$archivos" ]; then
        print_error "No se encontraron instaladores en FTP"
        return 1
    fi
    
    print_completado "Versiones disponibles:"
    echo ""
    
    local i=1
    local -a opciones=()
    
    while IFS= read -r archivo; do
        opciones+=("$archivo")
        echo "  [$i] $archivo"
        ((i++))
    done <<< "$archivos"
    
    echo ""
    read -p "Seleccione versión [1-${#opciones[@]}]: " seleccion
    
    if [[ "$seleccion" =~ ^[0-9]+$ ]] && [ "$seleccion" -ge 1 ] && [ "$seleccion" -le "${#opciones[@]}" ]; then
        local archivo_elegido="${opciones[$((seleccion-1))]}"
        print_completado "Seleccionado: $archivo_elegido"
        
        # Descargar archivo
        cd "$TMP_DIR" || return 1
        
        print_info "Descargando $archivo_elegido..."
        curl -u "${FTP_USER}:${FTP_PASS}" -O "ftp://${FTP_SERVER}${ftp_path}${archivo_elegido}" --progress-bar
        
        # Descargar hash
        print_info "Descargando hash SHA256..."
        curl -u "${FTP_USER}:${FTP_PASS}" -O "ftp://${FTP_SERVER}${ftp_path}${archivo_elegido}.sha256" --silent
        
        # Verificar hash
        print_titulo "Verificando Integridad"
        local hash_calc=$(sha256sum "$archivo_elegido" | awk '{print $1}')
        local hash_esp=$(cat "${archivo_elegido}.sha256" | awk '{print $1}')
        
        if [ "$hash_calc" = "$hash_esp" ]; then
            print_completado "✓ Archivo íntegro (hash verificado)"
            return 0
        else
            print_error "✗ Archivo corrupto (hash no coincide)"
            return 1
        fi
    else
        print_error "Selección inválida"
        return 1
    fi
}

# ============================================================================
# FUNCIÓN: Generar certificado SSL
# ============================================================================
generar_certificado_ssl() {
    local servicio="$1"
    local cert_file="${SSL_DIR}/certs/${servicio,,}.crt"
    local key_file="${SSL_DIR}/private/${servicio,,}.key"
    
    print_titulo "Generando Certificado SSL Autofirmado"
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$key_file" \
        -out "$cert_file" \
        -subj "/C=MX/ST=BajaCalifornia/L=Tijuana/O=Reprobados/OU=IT/CN=www.reprobados.com" \
        >/dev/null 2>&1
    
    if [ -f "$cert_file" ] && [ -f "$key_file" ]; then
        chmod 600 "$key_file"
        chmod 644 "$cert_file"
        print_completado "✓ Certificado SSL generado"
        print_info "  Certificado: $cert_file"
        print_info "  Clave: $key_file"
    else
        print_error "Error al generar certificado"
        return 1
    fi
}

# ============================================================================
# FUNCIÓN: Configurar Apache con SSL
# ============================================================================
configurar_apache_ssl() {
    generar_certificado_ssl "Apache"
    
    local cert_file="${SSL_DIR}/certs/apache.crt"
    local key_file="${SSL_DIR}/private/apache.key"
    
    # Habilitar módulo SSL
    a2enmod ssl &>/dev/null
    
    # Eliminar VirtualHost HTTP si existe (evitar conflicto)
    rm -f /etc/apache2/vhosts.d/tarea6.conf
    
    # Configurar puerto HTTPS en listen.conf
    if ! grep -q "Listen ${PUERTO_ELEGIDO}" /etc/apache2/listen.conf 2>/dev/null; then
        echo "Listen ${PUERTO_ELEGIDO}" >> /etc/apache2/listen.conf
    fi
    
    # Crear VirtualHost SSL
    cat > /etc/apache2/vhosts.d/tarea7-ssl.conf <<EOF
<VirtualHost *:${PUERTO_ELEGIDO}>
    ServerName www.reprobados.com
    DocumentRoot "${APACHE_WEBROOT}"
    
    SSLEngine on
    SSLCertificateFile $cert_file
    SSLCertificateKeyFile $key_file
    
    <Directory "${APACHE_WEBROOT}">
        Options -Indexes -FollowSymLinks
        AllowOverride None
        Require all granted
    </Directory>
</VirtualHost>
EOF

    print_completado "✓ Apache configurado con HTTPS en puerto $PUERTO_ELEGIDO"
}

# ============================================================================
# FUNCIÓN: Configurar Nginx con SSL
# ============================================================================
configurar_nginx_ssl() {
    generar_certificado_ssl "Nginx"
    
    local cert_file="${SSL_DIR}/certs/nginx.crt"
    local key_file="${SSL_DIR}/private/nginx.key"
    
    # Agregar configuración SSL al nginx.conf existente
    # (Ya está configurado por funciones_http.sh, solo agregamos SSL)
    
    # Modificar el servidor existente para usar SSL
    sed -i "s/listen      ${PUERTO_ELEGIDO};/listen      ${PUERTO_ELEGIDO} ssl;/" /etc/nginx/nginx.conf
    
    # Agregar certificados dentro del bloque server
    sed -i "/listen.*${PUERTO_ELEGIDO} ssl;/a\\    ssl_certificate $cert_file;\\n    ssl_certificate_key $key_file;\\n    ssl_protocols TLSv1.2 TLSv1.3;\\n    ssl_ciphers HIGH:!aNULL:!MD5;" /etc/nginx/nginx.conf
    
    print_completado "✓ Nginx configurado con HTTPS en puerto $PUERTO_ELEGIDO"
}

# ============================================================================
# FUNCIÓN: Configurar Tomcat con SSL
# ============================================================================
configurar_tomcat_ssl() {
    generar_certificado_ssl "Tomcat"
    
    local cert_file="${SSL_DIR}/certs/tomcat.crt"
    local key_file="${SSL_DIR}/private/tomcat.key"
    local keystore_file="/opt/tomcat/conf/tomcat.p12"
    local keystore_pass="tomcat123"
    
    print_titulo "Configurando SSL en Tomcat"
    
    # Convertir certificado a formato PKCS12
    print_info "Creando keystore PKCS12..."
    openssl pkcs12 -export \
        -in "$cert_file" \
        -inkey "$key_file" \
        -out "$keystore_file" \
        -name tomcat \
        -passout pass:"$keystore_pass" \
        >/dev/null 2>&1
    
    if [ ! -f "$keystore_file" ]; then
        print_error "Error al crear keystore"
        return 1
    fi
    
    chown tomcat:tomcat "$keystore_file"
    chmod 600 "$keystore_file"
    print_completado "✓ Keystore creado: $keystore_file"
    
    # Modificar server.xml para agregar conector HTTPS
    print_info "Configurando conector HTTPS en server.xml..."
    
    # Backup del server.xml
    cp /opt/tomcat/conf/server.xml /opt/tomcat/conf/server.xml.ssl-backup
    
    # Buscar el cierre de Service y agregar conector HTTPS antes
    sed -i "/<\/Service>/i\\
    <!-- Conector HTTPS con SSL -->\\
    <Connector port=\"${PUERTO_ELEGIDO}\" protocol=\"org.apache.coyote.http11.Http11NioProtocol\"\\
               maxThreads=\"150\" SSLEnabled=\"true\">\\
        <SSLHostConfig>\\
            <Certificate certificateKeystoreFile=\"conf/tomcat.p12\"\\
                         certificateKeystorePassword=\"${keystore_pass}\"\\
                         type=\"RSA\" />\\
        </SSLHostConfig>\\
    </Connector>" /opt/tomcat/conf/server.xml
    
    # Deshabilitar el conector HTTP original (puerto que eligió el usuario)
    # Ya que ahora usamos HTTPS en ese puerto
    sed -i "s/<Connector port=\"${PUERTO_ELEGIDO}\" protocol=\"HTTP\/1.1\"/<\!-- Conector HTTP deshabilitado, usando HTTPS\\
    <Connector port=\"${PUERTO_ELEGIDO}\" protocol=\"HTTP\/1.1\"/" /opt/tomcat/conf/server.xml
    
    sed -i "s/redirectPort=\"8443\"/redirectPort=\"${PUERTO_ELEGIDO}\" -->/" /opt/tomcat/conf/server.xml
    
    print_completado "✓ Tomcat configurado con HTTPS en puerto $PUERTO_ELEGIDO"
    print_info "Keystore password: $keystore_pass"
}

# ============================================================================
# MAIN - Flujo principal
# ============================================================================

if [[ $EUID -ne 0 ]]; then
    print_error "Este script debe ejecutarse como root"
    exit 1
fi

preparar_entorno
menu_principal
seleccionar_fuente

# Preguntar por SSL
echo ""
read -p "¿Desea activar SSL/TLS? [S/N]: " ssl_resp
case ${ssl_resp^^} in
    S|SI|YES|Y) CONFIGURAR_SSL="S" ;;
esac

# Si elige FTP, descargar primero
if [ "$FUENTE_INSTALACION" = "FTP" ]; then
    descargar_desde_ftp "$SERVICIO_ACTUAL" || exit 1
fi

# Pedir puerto (SIEMPRE, antes de instalar)
pedir_puerto

# Instalar usando funciones existentes (funciones_http.sh)
case $SERVICIO_ACTUAL in
    Apache)
        # Si es desde web, usar función normal con selección de versión
        if [ "$FUENTE_INSTALACION" = "WEB" ]; then
            vers=($(obtener_versiones_zypper apache2))
            elegir_version "apache2" "${vers[@]}"
        fi
        instalar_apache
        
        # Configurar SSL si se solicitó
        if [ "$CONFIGURAR_SSL" = "S" ]; then
            configurar_apache_ssl
            systemctl restart apache2
        fi
        ;;
        
    Nginx)
        if [ "$FUENTE_INSTALACION" = "WEB" ]; then
            vers=($(obtener_versiones_zypper nginx))
            elegir_version "nginx" "${vers[@]}"
        fi
        instalar_nginx
        
        if [ "$CONFIGURAR_SSL" = "S" ]; then
            configurar_nginx_ssl
            systemctl restart nginx
        fi
        ;;
        
    Tomcat)
        if [ "$FUENTE_INSTALACION" = "WEB" ]; then
            vers=($(obtener_versiones_tomcat))
            elegir_version "tomcat" "${vers[@]}"
        else
            # Desde FTP: extraer versión del archivo descargado
            archivo_tomcat=$(ls "$TMP_DIR"/apache-tomcat-*.tar.gz 2>/dev/null | head -1)
            if [ -n "$archivo_tomcat" ]; then
                # Extraer versión del nombre: apache-tomcat-10.1.34.tar.gz -> 10.1.34
                VERSION_ELEGIDA=$(basename "$archivo_tomcat" .tar.gz | sed 's/apache-tomcat-//')
                print_info "Versión detectada desde FTP: $VERSION_ELEGIDA"
                
                # Mover el archivo a donde instalar_tomcat() lo espera
                cp "$archivo_tomcat" "/tmp/apache-tomcat-${VERSION_ELEGIDA}.tar.gz"
            else
                print_error "No se encontró archivo de Tomcat descargado"
                print_info "Archivos en $TMP_DIR:"
                ls -lh "$TMP_DIR"
                exit 1
            fi
        fi
        instalar_tomcat
        
        # Configurar permisos para puertos < 1024
        if [ "$PUERTO_ELEGIDO" -lt 1024 ] 2>/dev/null; then
            print_titulo "Configurando Permisos para Puerto < 1024"
            
            # 1. Instalar libcap-progs si no está
            if ! command -v setcap &>/dev/null; then
                print_info "Instalando libcap-progs..."
                zypper --non-interactive install libcap-progs &>/dev/null
                print_completado "✓ libcap-progs instalado"
            else
                print_completado "✓ libcap-progs ya instalado"
            fi
            
            # 2. Obtener ruta real de Java
            java_bin=$(readlink -f "$(command -v java)")
            print_info "Binario de Java: $java_bin"
            
            # 3. Dar permisos CAP_NET_BIND_SERVICE
            print_info "Aplicando cap_net_bind_service a Java..."
            setcap 'cap_net_bind_service=+ep' "$java_bin"
            
            # Verificar que se aplicó
            if getcap "$java_bin" | grep -q cap_net_bind_service; then
                print_completado "✓ Permisos cap_net_bind_service aplicados"
            else
                print_error "Error al aplicar permisos"
            fi
            
            # 4. Configurar SELinux si está activo
            if command -v semanage &>/dev/null; then
                print_info "Configurando SELinux para puerto $PUERTO_ELEGIDO..."
                habilitar_puerto_selinux "$PUERTO_ELEGIDO"
            fi
            
            # 5. Reiniciar Tomcat para aplicar cambios
            print_info "Reiniciando Tomcat para aplicar permisos..."
            systemctl restart tomcat
            sleep 5
        fi
        
        if [ "$CONFIGURAR_SSL" = "S" ]; then
            configurar_tomcat_ssl
            print_info "Reiniciando Tomcat con configuración SSL..."
            systemctl restart tomcat
            sleep 5
        fi
        
        # Verificación final
        print_titulo "Verificación de Tomcat"
        
        if systemctl is-active --quiet tomcat; then
            print_completado "✓ Tomcat está activo"
            
            # Esperar a que el puerto esté escuchando
            intentos=0
            puerto_real=""
            while [ $intentos -lt 10 ]; do
                puerto_real=$(ss -tulnp 2>/dev/null | grep java | grep LISTEN | grep ":$PUERTO_ELEGIDO" | awk '{print $5}' | cut -d: -f2 | head -1)
                if [ -n "$puerto_real" ]; then
                    print_completado "✓ Tomcat escuchando en puerto: $puerto_real"
                    break
                fi
                sleep 2
                ((intentos++))
            done
            
            if [ -z "$puerto_real" ]; then
                print_error "Tomcat activo pero no escucha en puerto $PUERTO_ELEGIDO"
                print_info "Revisar logs: journalctl -u tomcat -n 30"
            fi
        else
            print_error "Tomcat no está activo"
            print_info "Revisar logs: journalctl -u tomcat -n 30"
        fi
        ;;
esac

# Resumen final
ip_addr=$(ip addr show enp0s9 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)

echo ""
print_completado "════════════════════════════════════════════════════"
print_completado "  Instalación Completada"
print_completado "════════════════════════════════════════════════════"
echo ""

if [ "$CONFIGURAR_SSL" = "S" ]; then
    print_info "Servicio: $SERVICIO_ACTUAL"
    print_info "URL: https://${ip_addr}:${PUERTO_ELEGIDO}"
    print_info "Certificados en: $SSL_DIR"
else
    print_info "Servicio: $SERVICIO_ACTUAL"
    print_info "URL: http://${ip_addr}:${PUERTO_ELEGIDO}"
fi

echo ""