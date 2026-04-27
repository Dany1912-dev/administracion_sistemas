FROM nginx:alpine

RUN adduser -D -H -s /sbin/nologin webuser

# Desactivar server tokens dentro del bloque http
RUN sed -i '/^http {/a\    server_tokens off;' /etc/nginx/nginx.conf

# Ejecutar workers como webuser (master sigue en root para bind port 80)
RUN sed -i 's/^user .*/user  webuser;/' /etc/nginx/nginx.conf

COPY --chown=webuser:webuser . /usr/share/nginx/html/

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
