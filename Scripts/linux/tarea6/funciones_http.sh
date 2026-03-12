#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/validaciones.sh"

VERSION_ELEGIDA=""
PUERTO_ELEGIDO=""

# =============== HABILITAR PUERTO EN SELINUX ===============
habilitar_puerto_selinux() {
    local puerto="$1"
    local tipo="http_port_t"

    if ! command -v semanage &>/dev/null; then
        return 0
    fi

    if semanage port -l 2>/dev/null | grep "$tipo" | grep -qw "$puerto"; then
        print_info "Puerto $puerto ya permitido en SELinux."
        return 0
    fi

    if semanage port -a -t "$tipo" -p tcp "$puerto" 2>/dev/null; then
        print_completado "Puerto $puerto habilitado en SELinux."
    elif semanage port -m -t "$tipo" -p tcp "$puerto" 2>/dev/null; then
        print_completado "Puerto $puerto modificado en SELinux."
    else
        print_info "No se pudo configurar SELinux para puerto $puerto (puede ser normal)."
    fi
}

# =============== OBTENER VERSIONES ===============
obtener_versiones_zypper() {
    local paquete="$1"

    zypper --quiet se --match-exact --details "$paquete" 2>/dev/null \
        | awk -F'|' 'NF>=4 && $4~/[0-9]/ {gsub(/ /,"",$4); print $4}' \
        | grep -v "^$" \
        | sort -uV
}

obtener_versiones_tomcat() {
    local base_url="https://dlcdn.apache.org/tomcat/"
    local ramas

    print_info "Consultando versiones en dlcdn.apache.org..." >&2

    ramas=$(curl -s --max-time 8 "$base_url" 2>/dev/null \
        | grep -oP 'tomcat-\K[0-9]+(?=/)' \
        | sort -uV)

    if [[ -z "$ramas" ]]; then
        print_info "Sin acceso a internet. Usando versiones de referencia." >&2
        echo "9.0.102"
        echo "10.1.40"
        echo "11.0.7"
        return
    fi

    while IFS= read -r rama; do
        local latest
        latest=$(curl -s --max-time 8 "${base_url}tomcat-${rama}/" 2>/dev/null \
            | grep -oP "v\K[0-9]+\.[0-9]+\.[0-9]+" \
            | sort -V | tail -1)
        [[ -n "$latest" ]] && echo "$latest"
    done <<< "$ramas"
}

# =============== MENU VERSIONES ===============
elegir_version() {
    clear
    local paquete="$1"
    shift
    local versiones=("$@")

    if [[ ${#versiones[@]} -eq 0 ]]; then
        print_error "No se encontraron versiones para '$paquete'."
        print_info  "Verifica los repositorios: zypper repos"
        print_info  "Actualiza si es necesario:  zypper refresh"
        return 1
    fi

    echo ""
    echo -e "${azul}=== Versiones disponibles: $paquete ===${nc}"
    echo ""

    local i=1
    local total=${#versiones[@]}
    for ver in "${versiones[@]}"; do
        local etiqueta=""
        [[ $i -eq 1      ]] && etiqueta="  ${verde}[LTS / Estable]${nc}"
        [[ $i -eq $total ]] && etiqueta="  ${naranja}[Latest / Desarrollo]${nc}"
        echo -e "  ${amarillo}[$i]${nc} $ver$etiqueta"
        (( i++ ))
    done
    echo ""

    local sel
    while true; do
        echo -en "${cyan}Elige una version [1-$total]: ${nc}"
        read -r sel
        sel="${sel//[^0-9]/}"
        if [[ "$sel" =~ ^[0-9]+$ ]] && (( sel >= 1 && sel <= total )); then
            VERSION_ELEGIDA="${versiones[$((sel - 1))]}"
            print_completado "Version elegida: $VERSION_ELEGIDA"
            break
        fi
        print_error "Opcion invalida. Elige entre 1 y $total."
    done
}

# =============== PEDIR PUERTO ================
pedir_puerto() {
    clear
    echo ""
    echo -e "${azul}=== Configuracion de Puerto ===${nc}"
    echo ""
    print_info "Puerto por defecto : 80"
    print_info "Otros comunes      : 8080, 8888"
    print_info "Bloqueados         : ${PUERTOS_RESERVADOS[*]}"
    echo ""

    local input
    while true; do
        echo -en "${cyan}Ingresa el puerto [Enter = 80]: ${nc}"
        read -r input

        [[ -z "$input" ]] && input="80"
        input="${input//[^0-9]/}"

        if [[ -z "$input" ]]; then
            print_error "Ingresa un numero"
            continue
        fi

        if validar_puerto "$input" "${PUERTOS_RESERVADOS[@]}"; then
            PUERTO_ELEGIDO="$input"
            print_completado "Puerto $PUERTO_ELEGIDO aceptado"
            sleep 1
            break
        fi
    done
}

# =============== INSTALAR APACHE2 ===============
instalar_apache() {
    print_titulo "Instalando Apache2..."

    if ! zypper --non-interactive install apache2 apache2-utils &>/dev/null; then
        print_error "Fallo la instalacion de Apache2."
        return 1
    fi
    print_completado "Apache2 instalado."

    local listen_conf="/etc/apache2/listen.conf"
    cp "$listen_conf" "${listen_conf}.bak" 2>/dev/null
    sed -i "s/^Listen 80$/Listen ${PUERTO_ELEGIDO}/" "$listen_conf"
    print_completado "Puerto configurado -> Listen $PUERTO_ELEGIDO"

    cat > /etc/apache2/vhosts.d/tarea6.conf << EOF
<VirtualHost *:${PUERTO_ELEGIDO}>
    DocumentRoot "${APACHE_WEBROOT}"
    ServerName localhost
    <Directory "${APACHE_WEBROOT}">
        Options -Indexes -FollowSymLinks
        AllowOverride None
        Require all granted
        <LimitExcept GET POST HEAD OPTIONS>
            Require all denied
        </LimitExcept>
    </Directory>
    ErrorLog  /var/log/apache2/tarea6-error.log
    CustomLog /var/log/apache2/tarea6-access.log combined
</VirtualHost>
EOF
    print_completado "VirtualHost creado."

    local sec_conf="/etc/apache2/conf.d/security.conf"
    cp "$sec_conf" "${sec_conf}.bak" 2>/dev/null
    cat > "$sec_conf" << 'EOF'
ServerTokens Prod
ServerSignature Off

<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
</IfModule>
EOF
    command -v a2enmod &>/dev/null && a2enmod headers &>/dev/null
    print_completado "Seguridad configurada."

    mkdir -p "$APACHE_WEBROOT"
    cat > "${APACHE_WEBROOT}/index.html" << EOF
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>Apache2</title></head>
<body>
<h1>Servidor: Apache2</h1>
<p>Version: ${VERSION_ELEGIDA}</p>
<p>Puerto: ${PUERTO_ELEGIDO}</p>
</body>
</html>
EOF
    print_completado "index.html creado."

    chown -R wwwrun:www "$APACHE_WEBROOT"
    chmod 750 "$APACHE_WEBROOT"
    print_completado "Permisos aplicados -> wwwrun:www (chmod 750)."

    if systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-port="${PUERTO_ELEGIDO}/tcp" &>/dev/null
        [[ "$PUERTO_ELEGIDO" -ne 80 ]] && firewall-cmd --permanent --remove-port=80/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null
        print_completado "Firewall: puerto $PUERTO_ELEGIDO abierto."
    fi

    habilitar_puerto_selinux "$PUERTO_ELEGIDO"

    systemctl enable apache2 &>/dev/null
    systemctl restart apache2 &>/dev/null
    sleep 2

    if systemctl is-active --quiet apache2; then
        local ip
        ip=$(ip addr show "$INTERFAZ_RED" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
        print_completado "Apache2 activo en puerto $PUERTO_ELEGIDO"
        print_info "Prueba: curl -I http://${ip}:${PUERTO_ELEGIDO}"
    else
        print_error "Apache2 no arranco."
        print_info  "Revisa: journalctl -u apache2 -n 20"
        return 1
    fi
}

# =============== INSTALAR NGINX ===============
instalar_nginx() {
    print_titulo "Instalando Nginx..."

    if ! zypper --non-interactive install nginx &>/dev/null; then
        print_error "Fallo la instalacion de Nginx."
        return 1
    fi
    print_completado "Nginx instalado."

    if ! id "www-nginx" &>/dev/null; then
        useradd -r -s /sbin/nologin -d "$NGINX_WEBROOT" -M www-nginx
        print_completado "Usuario www-nginx creado."
    else
        print_info "Usuario www-nginx: ok."
    fi

    mkdir -p /etc/systemd/system/nginx.service.d/
    cat > /etc/systemd/system/nginx.service.d/override.conf << 'OVERRIDE'
[Service]
ProtectSystem=off
OVERRIDE
    systemctl daemon-reload
    print_completado "Override de systemd configurado."

    cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak 2>/dev/null
    cat > /etc/nginx/nginx.conf << NGINXEOF
user www-nginx;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include      /etc/nginx/mime.types;
    default_type application/octet-stream;

    server_tokens off;

    add_header X-Frame-Options        "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff"    always;

    sendfile on;
    keepalive_timeout 65;

    server {
        listen      ${PUERTO_ELEGIDO};
        server_name localhost;
        root        ${NGINX_WEBROOT};
        index       index.html;

        if (\$request_method !~ ^(GET|POST|HEAD|OPTIONS)$) {
            return 405;
        }

        location / {
            try_files \$uri \$uri/ =404;
            autoindex off;
        }

        access_log /var/log/nginx/access.log;
        error_log  /var/log/nginx/error.log;
    }
}
NGINXEOF
    print_completado "nginx.conf configurado con puerto $PUERTO_ELEGIDO"

    touch /run/nginx.pid
    chown www-nginx:www-nginx /run/nginx.pid
    restorecon -v /run/nginx.pid &>/dev/null
    print_completado "Contexto SELinux de nginx.pid configurado."

    if ! nginx -t &>/dev/null; then
        print_error "Error de sintaxis en nginx.conf."
        nginx -t
        return 1
    fi
    print_completado "Sintaxis verificada."

    mkdir -p "$NGINX_WEBROOT"
    cat > "${NGINX_WEBROOT}/index.html" << EOF
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>Nginx</title></head>
<body>
<h1>Servidor: Nginx</h1>
<p>Version: ${VERSION_ELEGIDA}</p>
<p>Puerto: ${PUERTO_ELEGIDO}</p>
</body>
</html>
EOF
    print_completado "index.html creado."

    chown -R www-nginx:www-nginx "$NGINX_WEBROOT"
    chmod 750 "$NGINX_WEBROOT"
    print_completado "Permisos aplicados -> www-nginx:www-nginx (chmod 750)."

    if systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-port="${PUERTO_ELEGIDO}/tcp" &>/dev/null
        [[ "$PUERTO_ELEGIDO" -ne 80 ]] && firewall-cmd --permanent --remove-port=80/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null
        print_completado "Firewall: puerto $PUERTO_ELEGIDO abierto."
    fi

    habilitar_puerto_selinux "$PUERTO_ELEGIDO"

    systemctl enable nginx &>/dev/null
    systemctl restart nginx &>/dev/null
    sleep 2

    if systemctl is-active --quiet nginx; then
        local ip
        ip=$(ip addr show "$INTERFAZ_RED" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
        print_completado "Nginx activo en puerto $PUERTO_ELEGIDO"
        print_info "Prueba: curl -I http://${ip}:${PUERTO_ELEGIDO}"
    else
        print_error "Nginx no arranco."
        print_info  "Revisa: journalctl -u nginx -n 20"
        return 1
    fi
}

# =============== INSTALAR TOMCAT ===============
instalar_tomcat() {
    print_titulo "Instalando Apache Tomcat $VERSION_ELEGIDA..."

    local rama="${VERSION_ELEGIDA%%.*}"
    local url="https://dlcdn.apache.org/tomcat/tomcat-${rama}/v${VERSION_ELEGIDA}/bin/apache-tomcat-${VERSION_ELEGIDA}.tar.gz"
    local tarball="/tmp/apache-tomcat-${VERSION_ELEGIDA}.tar.gz"

    if ! command -v java &>/dev/null; then
        print_info "Java no encontrado. Instalando OpenJDK 21..."
        if ! zypper --non-interactive install java-21-openjdk java-21-openjdk-headless &>/dev/null; then
            print_error "No se pudo instalar Java."
            return 1
        fi
        print_completado "Java instalado."
    else
        print_completado "Java: $(java -version 2>&1 | head -1)"
    fi

    print_info "Descargando Tomcat $VERSION_ELEGIDA..."
    if ! curl -L --progress-bar -o "$tarball" "$url" 2>&1; then
        print_error "Fallo la descarga."
        print_info  "URL: $url"
        return 1
    fi

    print_info "Extrayendo en /opt/tomcat..."
    mkdir -p /opt/tomcat
    if ! tar xzf "$tarball" -C /opt/tomcat --strip-components=1; then
        print_error "Fallo la extraccion."
        rm -f "$tarball"
        return 1
    fi
    rm -f "$tarball"
    print_completado "Tomcat extraido en /opt/tomcat"

    cp /opt/tomcat/conf/server.xml /opt/tomcat/conf/server.xml.bak
    sed -i "s/port=\"8080\"/port=\"${PUERTO_ELEGIDO}\"/" /opt/tomcat/conf/server.xml
    sed -i 's/port="8009"/port="-1"/' /opt/tomcat/conf/server.xml
    print_completado "Puerto configurado en server.xml -> $PUERTO_ELEGIDO"
    print_completado "Conector AJP deshabilitado."

    sed -i 's|</web-app>||' /opt/tomcat/conf/web.xml
    cat >> /opt/tomcat/conf/web.xml << 'WEBXMLEOF'
    <filter>
        <filter-name>httpHeaderSecurity</filter-name>
        <filter-class>org.apache.catalina.filters.HttpHeaderSecurityFilter</filter-class>
        <init-param>
            <param-name>antiClickJackingOption</param-name>
            <param-value>SAMEORIGIN</param-value>
        </init-param>
        <init-param>
            <param-name>blockContentTypeSniffingEnabled</param-name>
            <param-value>true</param-value>
        </init-param>
    </filter>
    <filter-mapping>
        <filter-name>httpHeaderSecurity</filter-name>
        <url-pattern>/*</url-pattern>
    </filter-mapping>
</web-app>
WEBXMLEOF
    print_completado "Headers de seguridad configurados en web.xml."

    if ! id "tomcat" &>/dev/null; then
        useradd -r -s /sbin/nologin -d /opt/tomcat -M tomcat
        print_completado "Usuario tomcat creado."
    else
        print_info "Usuario tomcat ya existe."
    fi

    mkdir -p "$TOMCAT_WEBROOT"
    cat > "${TOMCAT_WEBROOT}/index.html" << EOF
<!DOCTYPE html>
<html lang="es">
<head><meta charset="UTF-8"><title>Tomcat</title></head>
<body>
<h1>Servidor: Apache Tomcat</h1>
<p>Version: ${VERSION_ELEGIDA}</p>
<p>Puerto: ${PUERTO_ELEGIDO}</p>
</body>
</html>
EOF
    print_completado "index.html creado."

    chown -R tomcat:tomcat /opt/tomcat
    chmod 750 /opt/tomcat
    chmod 750 /opt/tomcat/conf
    print_completado "Permisos aplicados -> tomcat:tomcat (chmod 750)."

    local java_home
    java_home=$(dirname "$(dirname "$(readlink -f "$(command -v java)")")")

    cat > /etc/systemd/system/tomcat.service << SVCEOF
[Unit]
Description=Apache Tomcat ${VERSION_ELEGIDA}
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment="JAVA_HOME=${java_home}"
Environment="CATALINA_HOME=/opt/tomcat"
Environment="CATALINA_BASE=/opt/tomcat"
Environment="CATALINA_PID=/opt/tomcat/temp/tomcat.pid"
Environment="CATALINA_OPTS=-Xms256M -Xmx512M"
ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SVCEOF

    systemctl daemon-reload
    print_completado "Servicio systemd registrado."

    if systemctl is-active --quiet firewalld 2>/dev/null; then
        firewall-cmd --permanent --add-port="${PUERTO_ELEGIDO}/tcp" &>/dev/null
        [[ "$PUERTO_ELEGIDO" -ne 8080 ]] && firewall-cmd --permanent --remove-port=8080/tcp &>/dev/null
        firewall-cmd --reload &>/dev/null
        print_completado "Firewall: puerto $PUERTO_ELEGIDO abierto."
    fi

    systemctl enable tomcat &>/dev/null
    systemctl start tomcat &>/dev/null
    print_info "Esperando que Tomcat inicie..."
    sleep 10

    if systemctl is-active --quiet tomcat; then
        local ip
        ip=$(ip addr show "$INTERFAZ_RED" 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)
        print_completado "Tomcat activo en puerto $PUERTO_ELEGIDO"
        print_info "Prueba: curl -I http://${ip}:${PUERTO_ELEGIDO}"
    else
        print_error "Tomcat no arranco."
        print_info  "Revisa: journalctl -u tomcat -n 20"
        print_info  "O bien: cat /opt/tomcat/logs/catalina.out"
        return 1
    fi
}

# =============== MENU INSTALACION ===============
instalar_HTTP() {
    clear
    echo ""
    echo -e "${azul}=== Instalacion de Servidor HTTP ===${nc}"
    echo ""
    echo -e "  ${amarillo}[1]${nc} Apache2"
    echo -e "  ${amarillo}[2]${nc} Nginx"
    echo -e "  ${amarillo}[3]${nc} Apache Tomcat"
    echo ""

    local opcion
    while true; do
        echo -en "${cyan}Selecciona un servidor [1-3]: ${nc}"
        read -r opcion
        opcion="${opcion//[^0-9]/}"
        [[ "$opcion" =~ ^[123]$ ]] && break
        print_error "Opcion invalida"
    done

    local versiones=()

    case $opcion in
        1)
            print_info "Consultando versiones de Apache2..."
            mapfile -t versiones < <(obtener_versiones_zypper "apache2")
            elegir_version "Apache2" "${versiones[@]}" || return 1
            pedir_puerto
            instalar_apache
            ;;
        2)
            print_info "Consultando versiones de Nginx..."
            mapfile -t versiones < <(obtener_versiones_zypper "nginx")
            elegir_version "Nginx" "${versiones[@]}" || return 1
            pedir_puerto
            instalar_nginx
            ;;
        3)
            mapfile -t versiones < <(obtener_versiones_tomcat)
            elegir_version "Apache Tomcat" "${versiones[@]}" || return 1
            pedir_puerto
            instalar_tomcat
            ;;
    esac
}

# =============== VERIFICAR ESTADO ===============
verificar_HTTP() {
    clear
    echo ""
    echo -e "${azul}=== Estado de Servidores HTTP ===${nc}"
    echo ""

    echo -en "  ${amarillo}Apache2  :${nc} "
    if rpm -q apache2 &>/dev/null; then
        local ver_apache
        ver_apache=$(rpm -q apache2 --queryformat '%{VERSION}')
        if systemctl is-active --quiet apache2; then
            local puerto_apache
            puerto_apache=$(ss -tulnp | grep -E 'httpd|apache2' | grep -oP ':\K[0-9]+' | head -1)
            echo -e "${verde}Instalado y activo${nc} — version: $ver_apache — puerto: ${puerto_apache:-?}"
        else
            echo -e "${amarillo}Instalado pero detenido${nc} — version: $ver_apache"
        fi
    else
        echo -e "${rojo}No instalado${nc}"
    fi

    echo -en "  ${amarillo}Nginx    :${nc} "
    if rpm -q nginx &>/dev/null; then
        local ver_nginx
        ver_nginx=$(rpm -q nginx --queryformat '%{VERSION}')
        if systemctl is-active --quiet nginx; then
            local puerto_nginx
            puerto_nginx=$(ss -tulnp | grep nginx | grep -oP ':\K[0-9]+' | head -1)
            echo -e "${verde}Instalado y activo${nc} — version: $ver_nginx — puerto: ${puerto_nginx:-?}"
        else
            echo -e "${amarillo}Instalado pero detenido${nc} — version: $ver_nginx"
        fi
    else
        echo -e "${rojo}No instalado${nc}"
    fi

    echo -en "  ${amarillo}Tomcat   :${nc} "
    if [[ -f /opt/tomcat/bin/startup.sh ]]; then
        local ver_tomcat
        ver_tomcat=$(/opt/tomcat/bin/version.sh 2>/dev/null | grep "Server version" | grep -oP 'Tomcat/\K[0-9]+\.[0-9]+\.[0-9]+')
        if systemctl is-active --quiet tomcat 2>/dev/null; then
            local puerto_tomcat
            puerto_tomcat=$(ss -tulnp | grep java | grep '\*:' | grep -oP '\*:\K[0-9]+' | head -1)
            echo -e "${verde}Instalado y activo${nc} — version: ${ver_tomcat:-?} — puerto: ${puerto_tomcat:-?}"
        else
            echo -e "${amarillo}Instalado pero detenido${nc} — version: ${ver_tomcat:-?}"
        fi
    else
        echo -e "${rojo}No instalado${nc}"
    fi

    echo ""
}

# =============== REVISAR CURL ===============
revisar_HTTP() {
    clear
    echo ""
    echo -e "${azul}=== Revision de Servidores HTTP ===${nc}"
    echo ""
    echo -e "  ${amarillo}[1]${nc} Apache2"
    echo -e "  ${amarillo}[2]${nc} Nginx"
    echo -e "  ${amarillo}[3]${nc} Apache Tomcat"
    echo -e "  ${amarillo}[4]${nc} Todos"
    echo ""

    local opcion
    while true; do
        echo -en "${cyan}Selecciona [1-4]: ${nc}"
        read -r opcion
        opcion="${opcion//[^0-9]/}"
        [[ "$opcion" =~ ^[1234]$ ]] && break
        print_error "Opcion invalida"
    done

    echo ""

    _curl_apache() {
        local puerto
        puerto=$(ss -tulnp | grep -E 'httpd|apache2' | grep -oP ':\K[0-9]+' | head -1)
        puerto="${puerto:-80}"
        echo -e "${azul}--- Apache2 (puerto $puerto) ---${nc}"
        echo -e "${amarillo}Headers:${nc}"
        curl -sI http://localhost:"$puerto"
        echo -e "${amarillo}Index:${nc}"
        curl -s http://localhost:"$puerto"
        echo ""
    }

    _curl_nginx() {
        local puerto
        puerto=$(ss -tulnp | grep nginx | grep -oP ':\K[0-9]+' | head -1)
        puerto="${puerto:-8080}"
        echo -e "${azul}--- Nginx (puerto $puerto) ---${nc}"
        echo -e "${amarillo}Headers:${nc}"
        curl -sI http://localhost:"$puerto"
        echo -e "${amarillo}Index:${nc}"
        curl -s http://localhost:"$puerto"
        echo ""
    }

    _curl_tomcat() {
        local puerto
        puerto=$(ss -tulnp | grep java | grep '\*:' | grep -oP '\*:\K[0-9]+' | head -1)
        puerto="${puerto:-8888}"
        echo -e "${azul}--- Apache Tomcat (puerto $puerto) ---${nc}"
        echo -e "${amarillo}Headers:${nc}"
        curl -sI http://localhost:"$puerto"
        echo -e "${amarillo}Index:${nc}"
        curl -s http://localhost:"$puerto"
        echo ""
    }

    case $opcion in
        1) _curl_apache ;;
        2) _curl_nginx ;;
        3) _curl_tomcat ;;
        4) _curl_apache; _curl_nginx; _curl_tomcat ;;
    esac
}
