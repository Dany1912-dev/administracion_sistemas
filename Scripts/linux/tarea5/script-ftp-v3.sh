#!/bin/bash

# ============================================================================
# Script de Automatización de Servidor FTP - openSUSE Leap
# Administración de Sistemas
# Servidor: vsftpd (Very Secure FTP Daemon)
# ============================================================================

# Cargar librerías compartidas
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/utils.sh"
source "$SCRIPT_DIR/../lib/validaciones.sh"

# Variables Globales
readonly PAQUETE="vsftpd"
readonly VSFTPD_CONF="/etc/vsftpd.conf"
readonly FTP_ROOT="/srv/ftp"
readonly GRUPO_REPROBADOS="reprobados"
readonly GRUPO_RECURSADORES="recursadores"
readonly INTERFAZ_RED="enp0s9"

# ============================================================================
# FUNCIÓN: Mostrar ayuda
# ============================================================================
ayuda() {
    echo "Uso del script: $0"
    echo "Opciones:"
    echo -e "  -v, --verify       Verifica si está instalado vsftpd"
    echo -e "  -i, --install      Instala y configura el servidor FTP"
    echo -e "  -u, --users        Gestionar usuarios FTP"
    echo -e "  -r, --restart      Reiniciar servidor FTP"
    echo -e "  -s, --status       Verificar estado del servidor FTP"
    echo -e "  -l, --list         Listar usuarios y estructura FTP"
    echo -e "  -?, --help         Muestra esta ayuda"
}

# ============================================================================
# FUNCIÓN: Verificar instalación de vsftpd
# ============================================================================
verificar_Instalacion() {
    print_info "Verificando instalación de vsftpd"
    
    if rpm -q $PAQUETE &>/dev/null; then
        local version=$(rpm -q $PAQUETE --queryformat '%{VERSION}')
        print_completado "vsftpd ya está instalado (versión: $version)"
        return 0
    fi
    
    if command -v vsftpd &>/dev/null; then
        local version=$(vsftpd -v 2>&1 | head -1)
        print_completado "vsftpd encontrado: $version"
        return 0
    fi
    
    print_error "vsftpd no está instalado"
    return 1
}

# ============================================================================
# FUNCIÓN: Crear estructura de directorios base
# ============================================================================
crear_Estructura_Base() {
    print_info "Creando estructura de directorios FTP..."
    
    # Crear directorio raíz FTP si no existe
    if [ ! -d "$FTP_ROOT" ]; then
        sudo mkdir -p "$FTP_ROOT"
        print_completado "Directorio raíz creado: $FTP_ROOT"
    fi
    
    # Crear directorio para homes de usuarios FTP
    if [ ! -d "/home/ftp_users" ]; then
        sudo mkdir -p "/home/ftp_users"
        sudo chmod 755 "/home/ftp_users"
        print_completado "Directorio para usuarios FTP creado"
    fi
    
    # Crear carpeta para datos personales de usuarios
    if [ ! -d "$FTP_ROOT/_users" ]; then
        sudo mkdir -p "$FTP_ROOT/_users"
        sudo chmod 755 "$FTP_ROOT/_users"
        print_completado "Directorio de datos personales creado"
    fi
    
    # Crear carpeta general (pública)
    if [ ! -d "$FTP_ROOT/general" ]; then
        sudo mkdir -p "$FTP_ROOT/general"
        print_completado "Carpeta 'general' creada"
    fi
    
    # Crear carpetas de grupos
    if [ ! -d "$FTP_ROOT/$GRUPO_REPROBADOS" ]; then
        sudo mkdir -p "$FTP_ROOT/$GRUPO_REPROBADOS"
        print_completado "Carpeta '$GRUPO_REPROBADOS' creada"
    fi
    
    if [ ! -d "$FTP_ROOT/$GRUPO_RECURSADORES" ]; then
        sudo mkdir -p "$FTP_ROOT/$GRUPO_RECURSADORES"
        print_completado "Carpeta '$GRUPO_RECURSADORES' creada"
    fi
    
    # Configurar permisos base
    sudo chmod 755 "$FTP_ROOT/general"
    sudo chown root:users "$FTP_ROOT/general"
    
    # Carpetas de grupo: solo accesibles por miembros del grupo
    sudo chmod 770 "$FTP_ROOT/$GRUPO_REPROBADOS"
    sudo chmod 770 "$FTP_ROOT/$GRUPO_RECURSADORES"
    
    print_completado "Estructura de directorios base configurada"
}

# ============================================================================
# FUNCIÓN: Crear grupos del sistema
# ============================================================================
crear_Grupos() {
    print_info "Verificando grupos del sistema..."
    
    if ! getent group $GRUPO_REPROBADOS &>/dev/null; then
        sudo groupadd $GRUPO_REPROBADOS
        print_completado "Grupo '$GRUPO_REPROBADOS' creado"
    else
        print_info "Grupo '$GRUPO_REPROBADOS' ya existe"
    fi
    
    if ! getent group $GRUPO_RECURSADORES &>/dev/null; then
        sudo groupadd $GRUPO_RECURSADORES
        print_completado "Grupo '$GRUPO_RECURSADORES' creado"
    else
        print_info "Grupo '$GRUPO_RECURSADORES' ya existe"
    fi
    
    sudo chgrp $GRUPO_REPROBADOS "$FTP_ROOT/$GRUPO_REPROBADOS"
    sudo chgrp $GRUPO_RECURSADORES "$FTP_ROOT/$GRUPO_RECURSADORES"
    
    print_completado "Grupos configurados correctamente"
}

# ============================================================================
# FUNCIÓN: Configurar vsftpd
# ============================================================================
configurar_Vsftpd() {
    print_info "Configurando vsftpd..."
    
    # Validar que nologin sea una shell válida para PAM
    if ! grep -q "/usr/sbin/nologin" /etc/shells; then
        echo "/usr/sbin/nologin" | sudo tee -a /etc/shells > /dev/null
    fi
    
    # Backup del archivo de configuración original
    if [ -f "$VSFTPD_CONF" ]; then
        sudo cp "$VSFTPD_CONF" "${VSFTPD_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
        print_info "Backup de configuración creado"
    fi
    
    # Crear nueva configuración
    sudo tee "$VSFTPD_CONF" > /dev/null << 'EOF'
# Configuración vsftpd - Servidor FTP Seguro
# Generado automáticamente

# Configuración básica
listen=YES
listen_ipv6=NO

# Usuarios locales
local_enable=YES
write_enable=YES
local_umask=022

# Usuario anónimo
anonymous_enable=YES
anon_root=/srv/ftp/general
no_anon_password=YES
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO

# Enjaulado de usuarios (chroot)
chroot_local_user=YES
allow_writeable_chroot=YES
user_sub_token=$USER
local_root=/home/ftp_users/$USER/ftp

# Seguridad
seccomp_sandbox=NO
hide_ids=YES
use_localtime=YES

# Permisos de archivos
file_open_mode=0666

# Logging
xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
log_ftp_protocol=YES

# Configuración de conexión
connect_from_port_20=YES
idle_session_timeout=600
data_connection_timeout=120

# Banner
ftpd_banner=Bienvenido al servidor FTP - Acceso restringido

# Activar modo pasivo
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100

# Lista de usuarios permitidos
userlist_enable=YES
userlist_deny=NO
userlist_file=/etc/vsftpd.user_list

# Autenticación PAM (Añadido para solucionar error Puerto 21)
pam_service_name=login
EOF

    print_completado "Archivo de configuración vsftpd creado"
    
    if [ ! -f /etc/vsftpd.user_list ]; then
        sudo touch /etc/vsftpd.user_list

        echo "anonymous" | sudo tee -a /etc/vsftpd.user_list > /dev/null
        echo "ftp" | sudo tee -a /etc/vsftpd.user_list > /dev/null

        print_completado "Archivo de lista de usuarios creado"
    fi
}

# ============================================================================
# FUNCIÓN: Instalar y configurar servidor FTP
# ============================================================================
instalar_FTP() {
    print_titulo "Instalación y Configuración de Servidor FTP"
    
    if verificar_Instalacion; then
        print_info "¿Desea reconfigurar el servidor FTP? [s/N]: "
        read -r reconf
        if [[ ! "$reconf" =~ ^[Ss]$ ]]; then
            print_info "Operación cancelada"
            return 0
        fi
    else
        print_info "Instalando vsftpd..."
        sudo zypper --non-interactive --quiet install $PAQUETE > /dev/null 2>&1 &
        pid=$!
        
        print_info "vsftpd se está instalando..."
        wait $pid
        
        if [ $? -eq 0 ]; then
            print_completado "vsftpd instalado correctamente"
        else
            print_error "Error en la instalación de vsftpd"
            return 1
        fi
    fi
    
    echo ""
    crear_Grupos
    echo ""
    crear_Estructura_Base
    echo ""
    configurar_Vsftpd
    echo ""
    
    print_info "Habilitando servicio vsftpd en el arranque..."
    if sudo systemctl enable vsftpd 2>/dev/null; then
        print_completado "Servicio vsftpd habilitado"
    else
        print_error "No se pudo habilitar el servicio vsftpd"
        return 1
    fi
    
    print_info "Iniciando servicio vsftpd..."
    if systemctl is-active --quiet vsftpd; then
        print_info "Servicio ya estaba activo, reiniciando..."
        sudo systemctl restart vsftpd 2>/dev/null
    else
        if ! sudo systemctl start vsftpd 2>/dev/null; then
            print_error "Error al iniciar el servicio vsftpd"
            return 1
        fi
    fi
    
    print_info "Configurando políticas de SELinux para FTP..."
    if command -v getenforce &>/dev/null && [ "$(getenforce)" != "Disabled" ]; then
        sudo setsebool -P allow_ftpd_full_access 1 2>/dev/null
        print_completado "SELinux: Permisos de lectura/escritura FTP concedidos"
    else
        print_info "SELinux inactivo, omitiendo configuración"
    fi

    print_info "Configurando firewall para FTP..."
    if command -v firewall-cmd &>/dev/null; then
        sudo firewall-cmd --add-service=ftp --permanent 2>/dev/null
        sudo firewall-cmd --add-port=40000-40100/tcp --permanent 2>/dev/null
        sudo firewall-cmd --reload 2>/dev/null
        print_completado "Reglas de firewall aplicadas"
    else
        print_error "firewalld no encontrado, configure el firewall manualmente"
    fi
    
    echo ""
    print_info "Verificando estado del servidor FTP..."
    
    if systemctl is-active --quiet vsftpd; then
        print_completado "Servicio vsftpd: activo y corriendo"
    else
        print_error "Servicio vsftpd: NO está corriendo"
        return 1
    fi
    
    local ip=$(ip addr show $INTERFAZ_RED 2>/dev/null | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
    
    if [ -z "$ip" ]; then
        ip=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -1)
    fi
    
    echo ""
    print_completado "══════════════════════════════════════"
    print_completado "  Servidor FTP listo"
    print_completado "══════════════════════════════════════"
    print_info "  IP del servidor : ${verde}$ip${nc}"
    print_info "  Puerto FTP      : ${verde}21${nc}"
    print_info "  Raíz FTP        : ${verde}$FTP_ROOT${nc}"
    print_completado "══════════════════════════════════════"
}

# ============================================================================
# FUNCIÓN: Validar nombre de usuario
# ============================================================================
validar_Usuario() {
    local usuario="$1"
    if [ -z "$usuario" ]; then
        print_error "El nombre de usuario no puede estar vacío"
        return 1
    fi
    if [ ${#usuario} -lt 3 ] || [ ${#usuario} -gt 32 ]; then
        print_error "El nombre de usuario debe tener entre 3 y 32 caracteres"
        return 1
    fi
    if [[ ! "$usuario" =~ ^[a-z][a-z0-9_-]*$ ]]; then
        print_error "El nombre de usuario debe comenzar con letra minúscula"
        return 1
    fi
    if id "$usuario" &>/dev/null; then
        print_error "El usuario '$usuario' ya existe en el sistema"
        return 1
    fi
    return 0
}

# ============================================================================
# FUNCIÓN: Validar contraseña
# ============================================================================
validar_Contrasena() {
    local password="$1"
    if [ ${#password} -lt 6 ]; then
        print_error "La contraseña debe tener al menos 6 caracteres"
        return 1
    fi
    return 0
}

# ============================================================================
# FUNCIÓN: Crear usuario FTP
# ============================================================================
crear_Usuario_FTP() {
    local usuario="$1"
    local password="$2"
    local grupo="$3"
    
    print_info "Creando usuario '$usuario' en grupo '$grupo'..."
    local user_home="/home/ftp_users/$usuario"
    
    # Crear usuario del sistema sin acceso a shell (Bloquea puerto 22)
    if sudo useradd -m -d "$user_home" -s /usr/sbin/nologin -g "$grupo" "$usuario" 2>/dev/null; then
        print_completado "Usuario del sistema creado"
    else
        print_error "Error al crear usuario del sistema"
        return 1
    fi
    
    echo "$usuario:$password" | sudo chpasswd
    
    print_info "Creando estructura de directorios y montajes..."
    
    # Crear carpeta personal real en FTP_ROOT
    local carpeta_personal="$FTP_ROOT/_users/$usuario"
    sudo mkdir -p "$carpeta_personal"
    sudo chown "$usuario:$grupo" "$carpeta_personal"
    sudo chmod 700 "$carpeta_personal"
    
    # Crear carpetas vacías para los puntos de montaje (Reemplaza symlinks)
    sudo mkdir -p "$user_home/ftp/$usuario"
    sudo mkdir -p "$user_home/ftp/general"
    sudo mkdir -p "$user_home/ftp/$grupo"
    
    # Montar los directorios reales en el home del usuario (bind mounts)
    sudo mount --bind "$carpeta_personal" "$user_home/ftp/$usuario"
    sudo mount --bind "$FTP_ROOT/general" "$user_home/ftp/general"
    sudo mount --bind "$FTP_ROOT/$grupo" "$user_home/ftp/$grupo"
    
    # Hacer los montajes persistentes en fstab
    echo "$carpeta_personal $user_home/ftp/$usuario none bind 0 0" | sudo tee -a /etc/fstab > /dev/null
    echo "$FTP_ROOT/general $user_home/ftp/general none bind 0 0" | sudo tee -a /etc/fstab > /dev/null
    echo "$FTP_ROOT/$grupo $user_home/ftp/$grupo none bind 0 0" | sudo tee -a /etc/fstab > /dev/null
    
    # Configurar permisos en el home
    sudo chown root:root "$user_home"
    sudo chmod 755 "$user_home"
    sudo chown root:root "$user_home/ftp"
    sudo chmod 755 "$user_home/ftp"
    
    if ! grep -q "^$usuario$" /etc/vsftpd.user_list 2>/dev/null; then
        echo "$usuario" | sudo tee -a /etc/vsftpd.user_list > /dev/null
    fi
    
    if command -v setfacl &>/dev/null; then
        sudo setfacl -m u:${usuario}:rwx "$FTP_ROOT/general" 2>/dev/null
        sudo setfacl -m u:${usuario}:rwx "$FTP_ROOT/$grupo" 2>/dev/null
    fi
    
    print_completado "Usuario '$usuario' creado exitosamente"
    return 0
}

# ============================================================================
# FUNCIÓN: Cambiar usuario de grupo
# ============================================================================
cambiar_Grupo_Usuario() {
    local usuario="$1"
    
    if ! id "$usuario" &>/dev/null; then
        print_error "El usuario '$usuario' no existe"
        return 1
    fi
    
    local grupo_actual=$(id -gn "$usuario")
    print_info "Grupo actual de '$usuario': $grupo_actual"
    
    echo ""
    echo "Grupos disponibles:"
    echo "  1) $GRUPO_REPROBADOS"
    echo "  2) $GRUPO_RECURSADORES"
    read -p "Seleccione el nuevo grupo [1-2]: " opcion
    
    local nuevo_grupo
    case $opcion in
        1) nuevo_grupo="$GRUPO_REPROBADOS" ;;
        2) nuevo_grupo="$GRUPO_RECURSADORES" ;;
        *) print_error "Opción inválida"; return 1 ;;
    esac
    
    if [ "$grupo_actual" == "$nuevo_grupo" ]; then
        print_info "El usuario ya pertenece al grupo '$nuevo_grupo'"
        return 0
    fi
    
    if sudo usermod -g "$nuevo_grupo" "$usuario"; then
        print_completado "Usuario '$usuario' movido al grupo '$nuevo_grupo'"
        
        local user_home="/home/ftp_users/$usuario"
        local ftp_dir="$user_home/ftp"
        
        # Desmontar grupo anterior y quitar de fstab
        if mountpoint -q "$ftp_dir/$grupo_actual"; then
            sudo umount "$ftp_dir/$grupo_actual"
            sudo rmdir "$ftp_dir/$grupo_actual"
        fi
        sudo sed -i "\|$FTP_ROOT/$grupo_actual $ftp_dir/$grupo_actual|d" /etc/fstab
        
        # Crear nuevo punto de montaje y montar
        sudo mkdir -p "$ftp_dir/$nuevo_grupo"
        sudo mount --bind "$FTP_ROOT/$nuevo_grupo" "$ftp_dir/$nuevo_grupo"
        echo "$FTP_ROOT/$nuevo_grupo $ftp_dir/$nuevo_grupo none bind 0 0" | sudo tee -a /etc/fstab > /dev/null
        
        if command -v setfacl &>/dev/null; then
            sudo setfacl -m u:${usuario}:rwx "$FTP_ROOT/$nuevo_grupo" 2>/dev/null
            sudo setfacl -x u:${usuario} "$FTP_ROOT/$grupo_actual" 2>/dev/null
        fi
        print_completado "Montajes y permisos actualizados"
    else
        print_error "Error al cambiar el grupo del usuario"
        return 1
    fi
}

# ============================================================================
# FUNCIÓN: Gestionar usuarios FTP
# ============================================================================
gestionar_Usuarios() {
    print_titulo "Gestión de Usuarios FTP"
    
    if ! verificar_Instalacion &>/dev/null; then
        print_error "vsftpd no está instalado. Ejecute primero: $0 -i"
        return 1
    fi
    
    echo "Opciones:"
    echo "  1) Crear nuevos usuarios"
    echo "  2) Cambiar grupo de un usuario"
    echo "  3) Eliminar usuario"
    echo "  4) Volver"
    echo ""
    read -p "Seleccione una opción [1-4]: " opcion
    
    case $opcion in
        1)
            echo ""
            read -p "¿Cuántos usuarios desea crear?: " num_usuarios
            
            if ! [[ "$num_usuarios" =~ ^[0-9]+$ ]] || [ "$num_usuarios" -lt 1 ]; then
                print_error "Número de usuarios inválido"
                return 1
            fi
            
            for ((i=1; i<=num_usuarios; i++)); do
                echo ""
                print_titulo "Usuario $i de $num_usuarios"
                
                while true; do
                    read -p "Nombre de usuario: " usuario
                    if validar_Usuario "$usuario"; then break; fi
                done
                
                while true; do
                    read -s -p "Contraseña: " password
                    echo ""
                    if validar_Contrasena "$password"; then
                        read -s -p "Confirmar contraseña: " password2
                        echo ""
                        if [ "$password" == "$password2" ]; then break
                        else print_error "Las contraseñas no coinciden"; fi
                    fi
                done
                
                echo ""
                echo "¿A qué grupo pertenece?"
                echo "  1) $GRUPO_REPROBADOS"
                echo "  2) $GRUPO_RECURSADORES"
                read -p "Seleccione el grupo [1-2]: " grupo_opcion
                
                local grupo
                case $grupo_opcion in
                    1) grupo="$GRUPO_REPROBADOS" ;;
                    2) grupo="$GRUPO_RECURSADORES" ;;
                    *) grupo="$GRUPO_REPROBADOS" ;;
                esac
                
                crear_Usuario_FTP "$usuario" "$password" "$grupo"
            done
            
            echo ""
            print_info "Reiniciando servicio vsftpd..."
            sudo systemctl restart vsftpd
            ;;
            
        2)
            echo ""
            listar_Usuarios_FTP
            echo ""
            read -p "Ingrese el nombre del usuario: " usuario
            cambiar_Grupo_Usuario "$usuario"
            
            if [ $? -eq 0 ]; then
                sudo systemctl restart vsftpd
            fi
            ;;
            
        3)
            echo ""
            listar_Usuarios_FTP
            echo ""
            read -p "Ingrese el nombre del usuario a eliminar: " usuario
            
            if ! id "$usuario" &>/dev/null; then
                print_error "El usuario '$usuario' no existe"
                return 1
            fi
            
            read -p "¿Está seguro de eliminar el usuario '$usuario'? [s/N]: " confirmar
            if [[ "$confirmar" =~ ^[Ss]$ ]]; then
                local user_home="/home/ftp_users/$usuario"
                local grupo_actual=$(id -gn "$usuario")
                
                # 1. Desmontar carpetas
                sudo umount "$user_home/ftp/$usuario" 2>/dev/null
                sudo umount "$user_home/ftp/general" 2>/dev/null
                sudo umount "$user_home/ftp/$grupo_actual" 2>/dev/null
                
                # 2. Limpiar referencias de este usuario en fstab
                sudo sed -i "\|$user_home/ftp|d" /etc/fstab
                
                # 3. Eliminar de la lista de vsftpd
                sudo sed -i "/^$usuario$/d" /etc/vsftpd.user_list
                
                # 4. Eliminar directorio personal real en /srv/ftp
                sudo rm -rf "$FTP_ROOT/_users/$usuario"
                
                # 5. Eliminar usuario del sistema (y su home virtual)
                sudo userdel -r "$usuario" 2>/dev/null || sudo userdel "$usuario"
                
                print_completado "Usuario '$usuario' eliminado limpiamente"
                sudo systemctl restart vsftpd
            fi
            ;;
            
        4) return 0 ;;
        *) print_error "Opción inválida" ;;
    esac
}

# ============================================================================
# FUNCIÓN: Listar usuarios FTP
# ============================================================================
listar_Usuarios_FTP() {
    print_titulo "Usuarios FTP Configurados"
    
    if [ ! -s /etc/vsftpd.user_list ]; then
        print_info "No hay usuarios FTP configurados"
        return 0
    fi
    
    printf "%-20s %-20s %-30s\n" "USUARIO" "GRUPO" "HOME VIRTUAL"
    echo "----------------------------------------------------------------------"
    
    while IFS= read -r usuario; do
        if id "$usuario" &>/dev/null; then
            local grupo=$(id -gn "$usuario")
            local dir="/home/ftp_users/$usuario/ftp"
            printf "%-20s %-20s %-30s\n" "$usuario" "$grupo" "$dir"
        fi
    done < /etc/vsftpd.user_list
    echo ""
}

# ============================================================================
# FUNCIÓN: Listar estructura FTP
# ============================================================================
listar_Estructura() {
    print_titulo "Estructura del Servidor FTP"
    if [ ! -d "$FTP_ROOT" ]; then
        print_error "El directorio FTP no existe: $FTP_ROOT"
        return 1
    fi
    
    print_info "Raíz FTP: $FTP_ROOT"
    if command -v tree &>/dev/null; then
        sudo tree -L 2 -p -u -g "$FTP_ROOT"
    else
        sudo find "$FTP_ROOT" -maxdepth 2 -type d -exec ls -ld {} \;
    fi
    echo ""
    listar_Usuarios_FTP
}

# ============================================================================
# FUNCIÓN: Reiniciar servicio FTP
# ============================================================================
reiniciar_FTP() {
    print_info "Reiniciando servidor FTP..."
    sudo systemctl restart vsftpd
    if systemctl is-active --quiet vsftpd; then
        print_completado "Servidor vsftpd reiniciado correctamente"
    else
        print_error "Error al reiniciar. Ejecute: sudo journalctl -xeu vsftpd.service"
    fi
}

# ============================================================================
# FUNCIÓN: Ver estado del servidor
# ============================================================================
ver_Estado() {
    print_titulo "ESTADO DEL SERVIDOR FTP"
    sudo systemctl status vsftpd --no-pager
    echo ""
    print_info "Conexiones FTP activas:"
    sudo ss -tnp | grep :21 || echo "  No hay conexiones activas"
}

# ============================================================================
# VERIFICAR PERMISOS DE ROOT
# ============================================================================
if [[ $EUID -ne 0 ]]; then
    print_error "Este script debe ejecutarse como root o con sudo"
    exit 1
fi

# ============================================================================
# PROCESAMIENTO DE ARGUMENTOS
# ============================================================================
case $1 in
    -v | --verify)  verificar_Instalacion ;;
    -i | --install) instalar_FTP ;;
    -u | --users)   gestionar_Usuarios ;;
    -s | --status)  ver_Estado ;;
    -r | --restart) reiniciar_FTP ;;
    -l | --list)    listar_Estructura ;;
    -? | --help)    ayuda ;;
    *)              ayuda ;;
esac