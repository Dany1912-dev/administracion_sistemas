#!/bin/bash

verificar_docker() {
    print_info "[INFO] Verificando instalacion de Docker..."
    if command -v docker &>/dev/null; then
        print_completado "[OK] Docker ya esta instalado: $(docker --version)"
    else
        print_info "[INFO] Docker no encontrado, instalando..."
        sudo zypper install -y docker &>/dev/null
        if [ $? -eq 0 ]; then
            print_completado "[OK] Docker instalado correctamente"
        else
            print_error "[ERROR] Fallo la instalacion de Docker"
            exit 1
        fi
    fi
}

verificar_cron() {
    print_info "[INFO] Verificando cron..."
    if command -v crontab &>/dev/null; then
        print_completado "[OK] Cron ya esta instalado"
        return
    fi
    print_info "[INFO] Instalando cronie..."
    if sudo zypper install -y cronie &>/dev/null; then
        sudo systemctl enable cron &>/dev/null
        sudo systemctl start cron &>/dev/null
        print_completado "[OK] Cronie instalado y activo"
    else
        print_error "[ERROR] No se pudo instalar cronie"
    fi
}

verificar_servicio_docker() {
    print_info "[INFO] Verificando servicio Docker..."
    if systemctl is-active --quiet docker; then
        print_completado "[OK] Servicio Docker activo"
    else
        print_info "[INFO] Iniciando servicio Docker..."
        sudo systemctl enable docker &>/dev/null
        sudo systemctl start docker
        if systemctl is-active --quiet docker; then
            print_completado "[OK] Servicio Docker iniciado"
        else
            print_error "[ERROR] No se pudo iniciar Docker"
            exit 1
        fi
    fi
}

verificar_grupo_docker() {
    print_info "[INFO] Verificando grupo docker..."
    if groups | grep -q docker; then
        print_completado "[OK] Usuario ya pertenece al grupo docker"
    else
        sudo usermod -aG docker $USER
        print_info "[INFO] Usuario agregado al grupo docker"
        print_error "[AVISO] Ejecuta: newgrp docker y vuelve a correr el script"
        exit 0
    fi
}

abrir_puertos_firewall() {
    print_info "[INFO] Configurando firewall..."
    if command -v firewall-cmd &>/dev/null; then
        sudo firewall-cmd --permanent --add-port=8080/tcp --add-port=21/tcp --add-port=21000-21010/tcp &>/dev/null
        sudo firewall-cmd --reload &>/dev/null
        print_completado "[OK] Puertos abiertos en firewall: 8080, 21, 21000-21010"
    else
        print_info "[INFO] firewalld no encontrado, omitiendo configuracion de firewall"
    fi
}

instalar_docker() {
    verificar_docker
    verificar_cron
    verificar_servicio_docker
    verificar_grupo_docker
    abrir_puertos_firewall
}
