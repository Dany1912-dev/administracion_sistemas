PAQUETE="dhcp-server"
scope=""
ipInicial=""
ipFinal=""
mascara=""

calcularMascara(){
   local ipInicial="$1"
   local ipFinal="$2"
   
   echo "Calculando mascara de subred para el rango $ipInicial - $ipFinal..."
   
   # Convertir IPs a números
   _ip2dec() {
      local ip="$1"
      IFS='.' read -r a b c d <<< "$ip"
      echo $(( (a * 256 * 256 * 256) + (b * 256 * 256) + (c * 256) + d ))
   }
   
   _dec2ip() {
      local dec="$1"
      local o1=$(( (dec / (256 * 256 * 256)) % 256 ))
      local o2=$(( (dec / (256 * 256)) % 256 ))
      local o3=$(( (dec / 256) % 256 ))
      local o4=$(( dec % 256 ))
      echo "$o1.$o2.$o3.$o4"
   }
   
   local ip1_dec=$(_ip2dec "$ipInicial")
   local ip2_dec=$(_ip2dec "$ipFinal")
   
   if [[ $ip2_dec -lt $ip1_dec ]]; then
      echo "ERROR: IP final menor que IP inicial"
      return 1
   fi
   
   local diferencia=$((ip2_dec - ip1_dec + 1))
   echo "IPs en el rango: $diferencia"
   
   local hosts_necesarios=$((diferencia + 2))
   echo "Hosts necesarios: $hosts_necesarios"
   
   #Calcular CIDR por hosts necesarios
   local cidr_hosts=32
   while [[ $cidr_hosts -ge 8 ]]; do
      # Calcular 2^(32-cidr) sin operadores <<
      local bits=$((32 - cidr_hosts))
      local potencia=1
      for ((i=0; i<bits; i++)); do
         potencia=$((potencia * 2))
      done
      local hosts_disponibles=$((potencia - 2))
      
      if [[ $hosts_necesarios -le $hosts_disponibles ]]; then
         break
      fi
      ((cidr_hosts--))
   done
   
   #Calcular CIDR por misma subred
   local cidr_subred=32
   while [[ $cidr_subred -ge 8 ]]; do
      # Calcular máscara sin operadores <<
      local mascara_tmp=0
      # Poner 1's en los primeros cidr_subred bits
      for ((i=0; i<cidr_subred; i++)); do
         mascara_tmp=$(( (mascara_tmp * 2) + 1 ))
      done
      # Poner 0's en los bits restantes
      for ((i=cidr_subred; i<32; i++)); do
         mascara_tmp=$((mascara_tmp * 2))
      done
      
      local red1=$(( ip1_dec & mascara_tmp ))
      local red2=$(( ip2_dec & mascara_tmp ))
      if [[ $red1 -eq $red2 ]]; then
         break
      fi
      ((cidr_subred--))
   done
   
   #Elegir el CIDR que cumpla AMBAS condiciones
   local cidr_final=$(( cidr_hosts < cidr_subred ? cidr_hosts : cidr_subred ))
   
   echo "CIDR necesario por hosts: /$cidr_hosts"
   echo "CIDR necesario por subred: /$cidr_subred"
   echo "CIDR final seleccionado: /$cidr_final"
   
   local mascara_dec=0
   # Poner 1's en los primeros cidr_final bits
   for ((i=0; i<cidr_final; i++)); do
      mascara_dec=$(( (mascara_dec * 2) + 1 ))
   done
   # Poner 0's en los bits restantes
   for ((i=cidr_final; i<32; i++)); do
      mascara_dec=$((mascara_dec * 2))
   done
   
   mascara=$(_dec2ip "$mascara_dec")
   
   # Calcular hosts disponibles sin operadores <<
   local bits_final=$((32 - cidr_final))
   local hosts_potencia=1
   for ((i=0; i<bits_final; i++)); do
      hosts_potencia=$((hosts_potencia * 2))
   done
   local hosts_finales=$((hosts_potencia - 2))
   
   echo "Máscara calculada: $mascara (CIDR: /$cidr_final)"
   echo "Hosts disponibles: $hosts_finales"
   
   # Verificar si el rango cabe en la subred
   local red_base=$(( ip1_dec & mascara_dec ))
   
   # Calcular broadcast sin operadores <<
   local broadcast=$(( (~mascara_dec) & 0x7FFFFFFF ))
   # Ajustar para 32 bits
   if [[ $mascara_dec -gt 0 ]]; then
      broadcast=$(( red_base | (0xFFFFFFFF & ~mascara_dec) ))
   else
      broadcast=0xFFFFFFFF
   fi
   
   if [[ $ip1_dec -lt $red_base || $ip2_dec -gt $broadcast ]]; then
      echo "  ERROR: El rango no cabe en la subred $(_dec2ip "$red_base")/$cidr_final"
      echo "  - Broadcast de la subred: $(_dec2ip "$broadcast")"
    return 1
   fi
   
   echo "  ✓ Mascara de subred determinada: $mascara"
   return 0
}

validarip(){
   local ip2="$1"
   local tipo="$2"
   if [[ ! "$ip2" =~ ^[0-9]+\.+[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "Direccion IP invalida, tiene que contener un formato X.X.X.X de numeros positivos."
      return 1
   fi

   local IFS='.' 
   read -ra octetos <<< "$ip2"
   
   if [[ "${#octetos[@]}" -ne 4 ]]; then
      echo "ERROR: Debe tener exactamente 4 octetos."
      return 1
   fi

   for i in {0..3}; do 
      local octeto=${octetos[i]}

      if [[ "$octeto" =~ ^0[0-9]+ ]] && [[ ${#octeto} -gt 1 ]]; then
         echo "ERROR: Octeto '$octeto' no puede tener ceros a la izquierda"
         return 1
      fi

      if [[ "$octeto" -gt 255 || "$octeto" -lt 0 ]]; then
         echo "ERROR: Octeto '$octeto' fuera de rango (0-255)."
         return 1
      fi
   done   

   local primeroOcteto=${octetos[0]}
   local segundoOcteto=${octetos[1]}
   local terceroOcteto=${octetos[2]}
   local cuartoOcteto=${octetos[3]}

   if [[ "$tipo" == "host" ]]; then
      if [[ $primeroOcteto -eq 0 ]]; then
         echo "ERROR: El primer octeto no puede ser 0 (0.X.X.X) para una direccion host."
         return 1
      fi
      if  [[ $cuartoOcteto -eq 0 ]]; then
         echo "ERROR: El ultimo octeto no puede ser 0 para una direccion host."
         return 1
      fi

      if [[ $cuartoOcteto -eq 255 ]]; then
         echo "ERROR: El ultimo octeto no puede ser 255 para una direccion de host."
         return 1
      fi


      if [[ $primeroOcteto -eq 127 ]]; then
         echo "ERROR: 127.x.x.x es direccion loopback, no valida para host."
         return 1
      fi
         
      if [[ $primeroOcteto -ge 224 && $primeroOcteto -le 239 ]]; then
         echo "ERROR: $ip2 es direccion multicast (224.0.0.0-239.255.255.255)."
         return 1
      fi
         
      if [[ $primeroOcteto -ge 240 ]]; then
         echo "ERROR: $ip2 esta en rango reservado experimental (240.0.0.0-255.255.255.255)."
         return 1
      fi
   elif [[ "$tipo" == "gateway" || "$tipo" == "dns" ]]; then
      # Gateway y DNS no deberían ser IPs multicast o reservadas
      if [[ $primeroOcteto -ge 224 && $primeroOcteto -le 239 ]]; then
         echo "ERROR: $ip2 es direccion multicast, no valida para $tipo."
         return 1
      fi
      
      if [[ $primeroOcteto -ge 240 ]]; then
         echo "ERROR: $ip2 esta en rango reservado experimental, no valida para $tipo."
         return 1
      fi
      
      # Gateway/DNS podría ser 0.0.0.0 en algunos casos, pero mostramos advertencia
      if [[ "$ip2" == "0.0.0.0" ]]; then
         echo "ADVERTENCIA: $ip2 puede no ser una direccion $tipo valida en produccion."
         # No retornamos error, solo advertencia
      fi
   fi

   return 0
}

copararIps(){
   local ip1="$1"
   local ip2="$2"

   _ip2num() {
      local ip="$1"
      IFS='.' read -r a b c d <<< "$ip"
      echo $(( (a * 256 * 256 * 256) + (b * 256 * 256) + (c * 256) + d ))
   }
   
   local num1=$(_ip2num "$ip1")
   local num2=$(_ip2num "$ip2")
   
   if [[ $num1 -ge $num2 ]]; then
      echo "ERROR: La IP inicial ($ip1) debe ser menor que la IP final ($ip2)."
      return 1
   fi
   
   return 0
}

configurarIpEstatica() {
   local ip_servidor="$1"
   local mascara="$2"
    
   echo "Configurando IP estática en red interna 'red_sistemas'..."
    
   # Detectar interfaces (excluyendo lo)
   local interfaces=($(ls /sys/class/net/ | grep -v lo | sort))
    
   # Asumimos:
   # - eth0 o ens33 = NAT (NO TOCAR)
   # - eth1 o ens34 = Red Interna "red_sistemas" (CONFIGURAR)
   local interfaz_nat="${interfaces[0]}"
   local interfaz_dhcp="${interfaces[1]}"
    
   echo "  - Adaptador 1 (NAT): $interfaz_nat - SIN CAMBIOS"
   echo "  - Adaptador 2 (Red Interna): $interfaz_dhcp - CONFIGURANDO"
    
   # SOLO configuramos la segunda interfaz
   # Calcular CIDR
   _mascara_a_cidr() {
         local masc="$1"
         IFS='.' read -r a b c d <<< "$masc"
         local bits=0
         local val
         for oct in $a $b $c $d; do
            val=$oct
            while [[ $val -gt 0 ]]; do
                bits=$((bits + (val & 1)))
                val=$((val >> 1))
            done
         done
      echo $bits
   }
    
   local cidr=$(_mascara_a_cidr "$mascara")
    
   # Configurar SOLO la interfaz de red interna
   cat > /etc/sysconfig/network/ifcfg-$interfaz_dhcp << EOF
   # Adaptador Red Interna - Servidor DHCP
   # Interfaz: $interfaz_dhcp
   # Red: red_sistemas
   BOOTPROTO='static'
   IPADDR='$ip_servidor/$cidr'
   STARTMODE='auto'
EOF
    
   echo "  ✓ Red Interna ($interfaz_dhcp) configurada con IP: $ip_servidor/$cidr"
    
   # NO reiniciamos todo el servicio de red, solo la interfaz
   wicked ifreload $interfaz_dhcp
   wicked ifup $interfaz_dhcp
    
   sleep 2
    
   # Mostrar solo la configuración de la red interna
   echo ""
   echo "=== CONFIGURACIÓN RED INTERNA ==="
   ip -4 addr show $interfaz_dhcp 2>/dev/null | grep inet | head -1 | awk '{print "  IP: " $2}'
   echo "  Interfaz: $interfaz_dhcp"
   echo "  Red: red_sistemas"
   echo "================================"
    
   return 0
}

generarConfiguracionDHCP() {
   local scope="$1"
   local ip_servidor="$2"
   local ip_inicial="$3"
   local ip_final="$4"
   local mascara="$5"
   local tiempo="$6"
   local gateway="$7"
   local dns="$8"
    
   echo "Generando configuración de DHCP para red interna 'red_sistemas'..."
    
   # Detectar interfaz de red interna (segundo adaptador)
   local interfaces=($(ls /sys/class/net/ | grep -v lo | sort))
   local interfaz_dhcp="${interfaces[1]}"
    
   if [[ -z "$interfaz_dhcp" ]]; then
      echo "ERROR: No se detectó adaptador de red interna"
      return 1
   fi
    
   # Obtener MAC address de la interfaz DHCP
   local mac_address=$(cat /sys/class/net/$interfaz_dhcp/address)
    
   # Calcular primera IP para clientes (ip_inicial + 1)
   IFS='.' read -r a b c d <<< "$ip_inicial"
   local ip_clientes_inicial="$a.$b.$c.$((d + 1))"
   local broadcast="$a.$b.$c.255"
    
   # Configurar DHCP para que escuche SOLO en la interfaz de red interna
   cat > /etc/sysconfig/dhcpd << EOF
# Configuración DHCP para openSUSE Leap 16.0
# ESCUCHAR SOLO EN RED INTERNA
DHCPD_INTERFACE="$interfaz_dhcp"
DHCPD_OPTIONS="-q"
EOF

   # Generar configuración
   cat > /etc/dhcp/dhcpd.conf << EOF
#
# Servidor DHCP - Red Interna "red_sistemas"
# Generado: $(date)
# Ámbito: $scope
#

authoritative;

default-lease-time $((tiempo * 60));
max-lease-time $((tiempo * 60));

option domain-name "red_sistemas.local";
option domain-name-servers ${dns:-8.8.8.8, 8.8.4.4};

# Red interna
subnet $a.$b.$c.0 netmask $mascara {
   option routers $ip_servidor;
   option subnet-mask $mascara;
   option broadcast-address $broadcast;
    
   range $ip_clientes_inicial $ip_final;
    
   # IP estática del servidor
   host servidor-dhcp {
      hardware ethernet $mac_address;
      fixed-address $ip_servidor;
   }
}

# Archivo de leases
lease-file-name "/var/lib/dhcp/db/dhcpd.leases";
EOF

   # Crear directorio y archivo de leases
   mkdir -p /var/lib/dhcp/db
   touch /var/lib/dhcp/db/dhcpd.leases
    
   echo "  ✓ Configuración DHCP lista para red interna"
   echo "  ✓ Interfaz: $interfaz_dhcp"
   echo "  ✓ MAC: $mac_address"
   echo "  ✓ Rango: $ip_clientes_inicial - $ip_final"
    
   return 0
}

levantar_servidor_dhcp() {
   echo "Iniciando servidor DHCP en red interna 'red_sistemas'..."
    
   # Detectar interfaz de red interna
   local interfaces=($(ls /sys/class/net/ | grep -v lo | sort))
   local interfaz_dhcp="${interfaces[1]}"
    
   if [[ -z "$interfaz_dhcp" ]]; then
      echo "ERROR: No se detectó interfaz de red interna"
      return 1
   fi
    
   # Verificar e instalar dhcp-server si es necesario
   if ! rpm -q dhcp-server >/dev/null 2>&1; then
      echo "  - Instalando dhcp-server..."
      zypper --non-interactive install dhcp-server
   fi
    
   # Asegurar que el servicio escuche SOLO en la red interna
   echo "DHCPD_INTERFACE=\"$interfaz_dhcp\"" > /etc/sysconfig/dhcpd
    
   # Habilitar forwarding solo para la red interna
   sysctl -w net.ipv4.ip_forward=1 >/dev/null
    
   # Iniciar servicio
   systemctl enable dhcpd
   systemctl restart dhcpd
    
   sleep 2
    
   if systemctl is-active dhcpd >/dev/null 2>&1; then
      echo ""
      echo "SERVIDOR DHCP ACTIVO - RED INTERNA"
      echo "========================================"
      echo "  Red:       red_sistemas"
      echo "  Interfaz:  $interfaz_dhcp"
      echo "  IP:        $ipInicial"
      echo "  Rango:     $(echo $ipInicial | cut -d. -f1-3).$(($(echo $ipInicial | cut -d. -f4) + 1)) - $ipFinal"
      echo "  Máscara:   $mascara"
      echo "========================================"
   else
      echo "ERROR: No se pudo iniciar el servidor DHCP"
      journalctl -u dhcpd --no-pager | tail -5
      return 1
   fi
}

intalacion_completa(){
   echo " VERIFICACANDO INSTALCION DE $PAQUETE "

   if rpm -q $PAQUETE > /dev/null 2>&1; then
      echo "[OK] El paquete '$PAQUETE' ya esta instalado."
   else
      echo "[!] Instalando $PAQUETE..."
      zypper --non-interactive install $PAQUETE

      if [$? -eq 0]; then
         echo "[EXITO] instalacion completada."
      else
         echo "[ERROR] Fallo la instalacion"
         exit 1
      fi
   fi

   echo -e  "\nCONFIGURACION DHCP DINAMICA"

   read -p "Nombre descriptivo del ambito: " scope

   until
      read -p "Rango inicial de la IP: " ipInicial
      validarip "$ipInicial" "host"
   do
      echo "Intentando de nuevo"
   done

   until
      read -p "Rango final de la IP: " ipFinal
      validarip "$ipFinal" "host"
      copararIps "$ipInicial" "$ipFinal"
   do
      echo "Intentando de nuevo"
   done

   echo ""
   if calcularMascara "$ipInicial" "$ipFinal"; then
      echo "Mascara de subred determinada: $mascara"
   else
      echo "ERROR: No se pudo calcular una mascara. Usando valor por defecto."
      mascara="255.255.255.0"
   fi
   echo ""

   until
      read -p "Tiempo de la sesion: " tiempoSesion
      if [[ -z "$tiempoSesion" ]]; then
         echo "ERROR: El tiempo de sesion no puede estar vacio."
         false
      elif ! [[ "$tiempoSesion" =~ ^[0-9]+$ ]]; then
         echo "ERROR: El tiempo de sesion debe ser un numero positivo."
         false
      elif [[ "$tiempoSesion" -le 0 ]]; then
         echo "ERROR: El tiempo de sesion debe ser mayor a 0."
         false
      elif [[ "$tiempoSesion" -gt 43200 ]]; then
         echo "ERROR: El tiempo de sesion no puede ser mayor a 43200 minutos (30 dias)."
         false
      else
         true
      fi
   do
      echo "Intentando de nuevo"
   done

   until
      read -p "Gateway (OPCIONAL, Presiona enter para omitir): " gateway
      if [[ -z "$gateway" ]]; then
         true
      elif [[ "$gateway" == "none" ]]; then
         true
      else 
         validarip "$gateway" "gateway"
      fi
   do
      echo "Intentando de nuevo"
   done

   until
      read -p "DNS (OPCIONAL, Presione enter para omitir): " dns
      if [[ -z "$dns" ]]; then
         true
      elif [[ "$dns" == "none" ]]; then
         true
      else 
         validarip "$dns" "dns"
      fi
   do
      echo "Intentando de nuevo"
   done

   echo ""
   echo "APLICANDO CONFIGURACION"
   echo ""

   configurarIpEstatica "$ipInicial" "$mascara"
   generarConfiguracionDHCP "$scope" "$ipInicial" "$ipInicial" "$ipFinal" "$mascara" "$tiempoSesion" "$gateway" "$dns" || exit 1
   levantar_servidor_dhcp

}

mostrar_menu() {
    clear
    echo "═══════════════════════════════════════════"
    echo "   SERVIDOR DHCP - RED INTERNA"
    echo "═══════════════════════════════════════════"
    echo " 1. Verificar instalación"
    echo " 2. Instalación completa (paquete + configuración)"
    echo " 3. Solo configurar/reconfigurar DHCP"
    echo " 4. Monitorear (IPs asignadas)"
    echo " 5. Reiniciar servicio"
    echo " 6. Salir"
    echo "═══════════════════════════════════════════"
    read -p " Seleccione una opción [1-6]: " opcion
    
    case $opcion in
        1) verificar_instalacion ;;
        2) instalacion_completa ;;   # <-- TUS FUNCIONES
        3) configurar_dhcp ;;        # <-- TU FUNCIÓN ORIGINAL
        4) monitorear_leases ;;
        5) reiniciar_servicio ;;
        6) exit 0 ;;
        *) 
            echo "Opción inválida"
            sleep 2
            mostrar_menu
            ;;
    esac
}

if [[ $EUID -ne 0 ]]; then
   echo "Ejecutar como root: sudo $0"
   exit 1
fi

mostrar_menu