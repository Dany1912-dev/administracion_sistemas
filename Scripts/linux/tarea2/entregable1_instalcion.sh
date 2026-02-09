PAQUETE="dhcp-server"
scope=""
ipInicial=""

validarip(){
   local ip1=0
   local ip2="$1"
   if [[ ! "$ip2" =~ ^[0-9]+\.+[0-9]+\.[0-9]+\.[0-9]+$ ]] then
      echo "Direccion IP invalida, tiene que contener un formato X.X.X.X de numeros positivos."
      return 1
   fi

   for i in {1..4}; do
      ip1=$(echo "$ip2" | cut -d'.' -f1)
      ip2=${ip2#*.}
      
      if [[ "$ip1" -gt 255 || "$ip1" -lt 0 ]] then
         echo "Direccion IP invalida, no puede ser mayor a 255 ni menor a 0."
         return 1
      fi
   done
   return 0

}



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
   validarip "$ipInicial"
do
   echo "Intentando de nuevo"
done

until
   read -p "Rango final de la IP: " ipFinal
   validarip "$ipFinal"
do
   echo "Intentando de nuevo"
done

read -p "Tiempo de la sesion: " tiempoSesion"

until
   read -p "Gateway: " gateway
   validarip "$gateway"
do
   echo "Intentando de nuevo"
done

until
   read -p "DNS: " dns
   validarip "$dns"
do
   echo "Intentando de nuevo"
done
