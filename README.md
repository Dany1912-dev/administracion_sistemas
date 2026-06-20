# Administración de Sistemas

Repositorio de prácticas y scripts del curso de Administración de Sistemas. Cubre automatización de servicios de red, contenedores Docker y administración de Active Directory, implementado sobre una infraestructura de tres nodos con VirtualBox.

---

## Infraestructura

| Nodo | Sistema Operativo | Rol | IP |
|------|-------------------|-----|----|
| Nodo 1 | openSUSE Leap 16.0 | Servidor Linux | `192.168.10.100/24` |
| Nodo 2 | Windows Server 2025 Standard | Servidor Windows | `192.168.10.150/24` |
| Nodo 3 | Linux Mint Cinnamon 22.3 | Cliente de pruebas | `192.168.10.200/24` |

> Gateway: `192.168.10.1` — todas las VMs corren en VirtualBox con red interna.

---

## Tecnologías

**Linux (Bash)**
- Servicios: DHCP (ISC), DNS (BIND9), SSH (OpenSSH), FTP (vsftpd), HTTP (Apache · Nginx · Tomcat)
- Seguridad: SSL/TLS (OpenSSL), firewalld, Fail2ban
- Contenedores: Docker, Docker Compose

**Windows (PowerShell)**
- Active Directory: GPO, FSRM, AppLocker, Logon Hours
- Autenticación: MFA con multiOTP, delegación de administración

**Correo (Docker)**
- Postfix · Dovecot · Rspamd · OpenDKIM · Roundcube · MariaDB · Nginx

---

## Prácticas

| # | Tema | Plataforma | Scripts principales |
|---|------|-----------|---------------------|
| 1 | Diagnóstico del sistema (hostname, IP, disco) | Linux · Windows | `tarea1/tarea1_diagnostico.sh` · `tarea1/tarea1_diagnostico.ps1` |
| 2 | Servidor DHCP automatizado | Linux · Windows | `tarea2/tarea2_DHCP_automatizado.sh` · `tarea2/tarea2_DHCP.ps1` |
| 3 | Servidor DNS con BIND9 | Linux · Windows | `tarea3/tarea3_DNS_automatizado.sh` · `tarea3/tarea3.ps1` |
| 4 | Servidor SSH | Linux · Windows | `tarea4/script-ssh.sh` · `tarea4/tarea4.ps1` |
| 5 | Servidor FTP (vsftpd) con grupos y permisos | Linux · Windows | `tarea5/script-ftp-v3.sh` · `tarea5/tarea5-ftp-v3.ps1` |
| 6 | Servidores HTTP (Apache, Nginx, Tomcat) | Linux · Windows | `tarea6/serviciosHTTP.sh` · `tarea6/windows-serviciosHTTP.ps1` |
| 7 | HTTPS con SSL/TLS + descarga de paquetes por FTP | Linux · Windows | `tarea7/script-practica7.sh` · `tarea7/practica7_windows.ps1` |
| 8 | Active Directory: GPO, FSRM, AppLocker, cuotas | Windows | `tarea8/tarea8v2.ps1` |
| 9 | Active Directory: MFA (multiOTP) y delegación | Windows | `tarea9/practica9.ps1` |
| 10 | Contenedores Docker: web + base de datos + FTP | Linux | `tarea10/practica10.sh` |
| 11 | Microservicios Docker: stack completo con PostgreSQL y pgAdmin | Linux | `tarea11/practica11.sh` |
| 12 | Servidor de correo privado auto-hospedado | Linux | `tarea12/setup.sh` |

---

## Estructura del repositorio

```
.
├── Menu.sh                         # Menú de entrada para los scripts Linux
├── Documentacion/
│   ├── arquitectura.md
│   ├── configuracion-red.md
│   ├── imagenes/
│   └── PDFs/                       # Documentación de cada práctica
└── Scripts/
    ├── linux/
    │   ├── lib/                    # Utilidades y validaciones compartidas
    │   │   ├── utils.sh
    │   │   ├── validaciones.sh
    │   │   ├── Dockers/            # Funciones Docker reutilizables (red, volúmenes, web, db, ftp)
    │   │   ├── Practica11/         # Módulos de la práctica 11 (firewall, stack, pruebas)
    │   │   └── tarea12/            # Configuración de nginx, backup y webmail
    │   ├── tarea1/ … tarea12/      # Un directorio por práctica
    │   └── tarea12/
    │       ├── docker-compose.yml
    │       ├── setup.sh
    │       ├── nginx/
    │       ├── backup/
    │       └── webmail/
    └── windows/
        ├── lib/
        │   ├── utils.ps1
        │   └── Practica9/          # Módulos AD: usuarios, delegación, MFA, políticas
        └── tarea1/ … tarea9/
```

---

## Práctica destacada — Servidor de correo (Práctica 12)

La práctica más completa del curso: infraestructura de correo electrónico completamente auto-hospedada en Docker.

**Stack de 5 contenedores:**

| Contenedor | Imagen | Función |
|---|---|---|
| `mailserver` | docker-mailserver | Postfix (SMTP) + Dovecot (IMAP) + Rspamd + Fail2ban + OpenDKIM |
| `roundcube` | roundcube/roundcubemail | Portal webmail |
| `roundcube_db` | mariadb:10.11 | Base de datos de preferencias |
| `mail_nginx` | nginx:alpine (custom) | Proxy inverso HTTPS con SSL |
| `mail_backup` | alpine (custom) | Respaldo automático de buzones cada 24h |

```bash
# Despliegue en un solo paso
cd Scripts/linux/tarea12
chmod +x setup.sh && ./setup.sh
docker compose up -d --build
```

Ver [`Scripts/linux/lib/tarea12/README.md`](Scripts/linux/lib/tarea12/README.md) para la guía completa de despliegue y protocolo de pruebas.

---

## Uso general

```bash
# Clonar el repositorio
git clone https://github.com/Dany1912-dev/administracion_sistemas/

# Ejecutar cualquier script Linux directamente
bash Scripts/linux/tarea2/tarea2_DHCP_automatizado.sh --help

# Menú global para Linux
bash Menu.sh --help
```

Los scripts de Windows se ejecutan en PowerShell con privilegios de administrador:

```powershell
# Ejemplo: configurar Active Directory con MFA
.\Scripts\windows\tarea9\practica9.ps1
```

---

## Convenciones de los scripts

- Todos los scripts Linux cargan `lib/utils.sh` y `lib/validaciones.sh` para salida con colores y validaciones comunes.
- Cada script acepta `-?` o `--help` para mostrar sus opciones disponibles.
- Los scripts más largos están modularizados en funciones separadas dentro de `lib/` para facilitar la reutilización entre prácticas.
