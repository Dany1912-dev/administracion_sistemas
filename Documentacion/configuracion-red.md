DESCRIPCION: En este documento se dejara claro que segmento de red se utilizara y de que manera.

Nodo 1: openSUSE Leap 16.0
    Adaptador 1: Puerto NAT (Para descargas de paquetes desde internet y conexion a repositorios)
    Adaptador 2: Red Interna para conexion entre nodos (nombre: red_sistemas)

Nodo 2: Windows Server 2025 Standart Edition
    Adaptador 1: Puerto NAT (Para descargas de paquetes desde internet y conexion a repositorios)
    Adaptador 2: Red Interna para conexion entre nodos (nombre: red_sistemas)

Nodo 3: Linux Mint Cinnamon 22.3
    Adaptador 1: Puerto NAT (Para conexion a internet)
    Adaptador 2: Red Interna para conexion entre nodos (nombre: red_sistemas)

SEGMENTO DE RED UTILIZADO:
    openSUSE Leap 16.0:                             192.168.10.100/24
    Windows Server 2025 Standart Edition:           192.168.10.150/24
    Linux Mint Cinnamon 22.3:                       192.168.10.200/24