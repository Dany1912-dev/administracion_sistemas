PAQUETE="dhcp-server"
scope=""
ipInicial=""
ipFinal=""
mascara=""
tiempoSesion=""
gateway=""
dnsPrimario=""
dnsSecundario=""
broadcast=""
ipServidor=""
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
   
   broadcast=$(( (~mascara_dec) & 0x7FFFFFFF ))
   # Ajustar para 32 bits
   if [[ $mascara_dec -gt 0 ]]; then
      broadcast=$(( red_base | (0xFFFFFFFF & ~mascara_dec) ))
   else
      broadcast=0xFFFFFFFF
   fi
   
   if [[ $ip1_dec -lt $red_base || $ip2_dec -gt $broadcast ]]; then
      echo "ERROR: El rango no cabe en la subred $(_dec2ip "$red_base")/$cidr_final"
      echo "Broadcast de la subred: $(_dec2ip "$broadcast")"
    return 1
   fi
   
   echo "Broadcast de la subred: $(_dec2ip "$broadcast")"
   echo "Mascara de subred determinada: $mascara"
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

   for i in 0 1 2 3; do
      octeto="${octetos[$i]}"

      if [[ "$octeto" =~ ^0[0-9]+ ]] && [[ ${#octeto} -gt 1 ]]; then
         echo "ERROR: Octeto '$octeto' no puede tener ceros a la izquierda"
         return 1
      fi

      if ((octeto > 255 || octeto < 0)); then
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

intalacionCompleta(){
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
   ConfiguracionDHCP
}

ConfiguracionDHCP(){
   echo -e  "\nCONFIGURACION DHCP DINAMICA"

   read -p "Nombre descriptivo del ambito: " scope

   until
      read -p "Rango inicial de la IP: " ipInicial
      validarip "$ipInicial" "host"
      ipServidor="$ipInicial"
      local IFS='.' 
      read -ra octetos <<< "$ipInicial"
      ipInicial="${octetos[0]}.${octetos[1]}.${octetos[2]}.$((octetos[3] + 1))"
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
      if [[ -z "$dnsPrimario" ]]; then
         true
      elif [[ "$dnsPrimario" == "none" ]]; then
         true
      else 
         validarip "$dnsPrimario" "dns"
      fi
   do
      echo "Intentando de nuevo"
   done

   if [[ -z "$dnsPrimario" ]]; then
      echo "No se agrego un DNS primario."
   else
      until
         read -p "¿Desea agregar un DNS secundario? (s/n): " agregarDNS
         if [[ "$agregarDNS" == "s" ]]; then
            read -p "DNS secundario: " dnsSecundario
            validarip "$dnsSecundario" "dns"
         elif [[ "$agregarDNS" == "n" ]]; then
            break
         else
            echo "Por favor ingrese 's' o 'n'."
         fi
      do
         echo "Intentando de nuevo"
      done
   fi

   echo -e "\nInterfaces de red disponibles:"
	ip -br link show | grep -v "lo" | awk '{print $1}'
	read -p "Ingrese la interfaz de red a usar (ej: enp0s8): " interfaz

    echo -e "\nLA CONFIGURACION FINAL ES:"
	echo -e "Nombre del ambito: $scope"
	echo -e "Mascara: $mascara"
	echo -e "IP inicial: $ipInicial"
	echo -e "IP final: $ipFinal"
	echo -e "Tiempo de sesion: $tiempoSesion"
	echo -e "Gateway: $gateway"
	echo -e "DNS primario: $dnsPrimario"
	echo -e "DNS alternativo: $dnsSecundario"
	echo -e "Interfaz: $interfaz\n"

   read -p "Acepta esta configuracion? (y/n): " opc
   if [ "$opc" = "y" ]; then
   echo ""
   echo "APLICANDO CONFIGURACION"
   echo ""
	# Calcular la dirección de red correctamente
	IFS='.' read -r a b c d <<< "$ipInicial"
	IFS='.' read -r ma mb mc md <<< "$mascara"
	
	# AND bit a bit entre IP y máscara para obtener la red
	red="$((a & ma)).$((b & mb)).$((c & mc)).$((d & md))"
	
	# Calcular broadcast
	broadcast="$((a | (255 - ma))).$((b | (255 - mb))).$((c | (255 - mc))).$((d | (255 - md)))"
	
	echo -e "${amarillo}Red calculada: $red${nc}"
	echo -e "${amarillo}Broadcast calculado: $broadcast${nc}"
	
	# Crear configuración DHCP
	echo -e "${amarillo}Creando configuración DHCP...${nc}"
	sudo bash -c "cat > /etc/dhcpd.conf" << EOF
# Configuracion DHCP - $scope
default-lease-time $tiempoSesion;
max-lease-time $((tiempoSesion * 2));
authoritative;

subnet $red netmask $mascara {
    range $ipInicial $ipFinal;
    option routers $gateway;
    option subnet-mask $mascara;
$(if [ "$dnsPrimario" != "" ] && [ "$dnsSecundario" != "" ]; then
    echo "    option domain-name-servers $dnsPrimario, $dnsSecundario;"
elif [ "$dnsPrimario" != "" ]; then
    echo "    option domain-name-servers $dnsPrimario;"
fi)
    option broadcast-address $broadcast;
}
EOF

		# Configurar interfaz
		interfaz="enp0s8"
		echo -e "Configurando interfaz de red..."
		sudo bash -c "echo 'DHCPD_INTERFACE=\"$interfaz\"' > /etc/sysconfig/dhcpd"
		
		echo -e "${amarillo}Configurando IP estática $ipServidor en la interfaz $interfaz...${nc}"
		sudo ip addr flush dev $interfaz
		sudo ip addr add $ipServidor/$( calcular_Bits "$mascara" ) dev $interfaz
		sudo ip link set $interfaz up

sudo bash -c "cat > /etc/sysconfig/network/ifcfg-$interfaz" << EOF
BOOTPROTO='static'
STARTMODE='auto'
IPADDR='$ipServidor'
NETMASK='$mascara'
EOF

		# Reiniciar servicio
		echo -e "Reiniciando servicio DHCP..."
		sudo systemctl restart dhcpd
		
		echo -e "IP estática $ipServidor configurada en $interfaz"

		# Verificar estado
		if sudo systemctl is-active --quiet dhcpd; then
			echo -e "¡Servidor DHCP configurado y funcionando correctamente!"
			sudo systemctl status dhcpd --no-pager
		else
			echo -e "Error al iniciar el servicio DHCP"
			echo -e "Ejecute: sudo journalctl -xeu dhcpd.service"
	   fi
   else
      echo -e "Volviendo a configurar..."
      ConfiguracionDHCP
   fi
}

verificarInstalacion(){
   echo " VERIFICACANDO INSTALCION DE $PAQUETE "

   if rpm -q $PAQUETE > /dev/null 2>&1; then
      echo "[OK] El paquete '$PAQUETE' ya esta instalado."
   else
      echo "El paquete '$PAQUETE' no esta instaldo"
   fi
}

reiniciarDHCP(){
    echo -e "Reiniciando servidor DHCP..."
    
    if ! systemctl is-active --quiet dhcpd; then
        echo -e "El servicio DHCP no está activo"
        read -p "¿Desea iniciarlo en lugar de reiniciarlo? (y/n): " opc
        if [[ "$opc" = "y" ]]; then
            sudo systemctl start dhcpd
        else
            return 1
        fi
    else
        sudo systemctl restart dhcpd
    fi
    
    if systemctl is-active --quiet dhcpd; then
        echo -e "Servidor DHCP reiniciado correctamente"
        sudo systemctl status dhcpd --no-pager
    else
        echo -e "Error al reiniciar el servidor DHCP"
        echo -e "Ejecute: sudo journalctl -xeu dhcpd.service"
    fi
}

mostrarMenu() {
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
        1) verificarInstalacion ;;
        2) intalacionCompleta ;;
        3) ConfiguracionDHCP ;;
        4) monitorear ;;
        5) reiniciarDHCP ;;
        6) exit 0 ;;
        *) 
            echo "Opción inválida"
            sleep 2
            mostrar_menu
            ;;
    esac
}

#if [[ $EUID -ne 0 ]]; then
#   echo "Ejecutar como root: sudo $0"
#   exit 1
#fi

mostrarMenu