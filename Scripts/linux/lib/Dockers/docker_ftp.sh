#!/bin/bash

iniciar_ftp() {
    print_info "[INFO] Verificando contenedor ftp_server..."

    if docker ps --format '{{.Names}}' | grep -q "^ftp_server$"; then
        print_completado "[OK] Contenedor ftp_server ya está corriendo"
        return
    fi

    if docker ps -a --format '{{.Names}}' | grep -q "^ftp_server$"; then
        print_info "[INFO] Contenedor ftp_server detenido, iniciando..."
        docker start ftp_server &>/dev/null
    else
        print_info "[INFO] Creando contenedor ftp_server..."
        docker run -d \
            --name ftp_server \
            --network infra_red \
            --volume web_content:/ftp/$FTP_USER \
            --memory 512m \
            --cpus 0.5 \
            --restart always \
            -p 21:21 \
            -p 21000-21010:21000-21010 \
            -e USERS="$FTP_USER|$FTP_PASS|/ftp/$FTP_USER" \
            -e ADDRESS="$(ip -4 addr show enp0s9 | awk '/inet /{split($2,a,"/"); print a[1]; exit}')" \
            -e MIN_PORT=21000 \
            -e MAX_PORT=21010 \
            delfer/alpine-ftp-server &>/dev/null
    fi

    if [ $? -eq 0 ]; then
        print_completado "[OK] Contenedor ftp_server iniciado"
    else
        print_error "[ERROR] No se pudo iniciar el contenedor ftp_server"
        exit 1
    fi
}

detener_ftp() {
    print_info "[INFO] Deteniendo contenedor ftp_server..."

    if docker ps --format '{{.Names}}' | grep -q "^ftp_server$"; then
        docker stop ftp_server &>/dev/null
        print_completado "[OK] Contenedor ftp_server detenido"
    else
        print_info "[INFO] Contenedor ftp_server no esta corriendo"
    fi
}

eliminar_ftp() {
    detener_ftp
    if docker ps -a --format '{{.Names}}' | grep -q "^ftp_server$"; then
        docker rm ftp_server &>/dev/null
        print_completado "[OK] Contenedor ftp_server eliminado"
    fi
}
