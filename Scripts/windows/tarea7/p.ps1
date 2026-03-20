$nginxConf = @"
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    
    server_tokens off;
    
    sendfile        on;
    keepalive_timeout  65;
    
    server {
        listen       4444 ssl;
        server_name  www.reprobados.com;
        
        ssl_certificate      C:/SSL/practica7/certs/nginx.crt;
        ssl_certificate_key  C:/SSL/practica7/private/nginx.key;
        
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        
        location / {
            root   html;
            index  index.html;
        }
    }
}
"@

# Guardar SIN BOM
$Utf8NoBomEncoding = New-Object System.Text.UTF8Encoding $False
[System.IO.File]::WriteAllLines("$nginxRoot\conf\nginx.conf", $nginxConf, $Utf8NoBomEncoding)

# 4. Probar configuración
cd $nginxRoot
.\nginx.exe -t

# 5. Si dice "test is successful", iniciar Nginx
.\nginx.exe

# 6. Verificar
Start-Sleep -Seconds 2
Get-Process nginx
Get-NetTCPConnection -LocalPort 4444 -State Listen