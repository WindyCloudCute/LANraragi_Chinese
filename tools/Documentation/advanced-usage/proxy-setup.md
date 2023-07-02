# 🕵️ Proxy Setup

## Setting up LANraragi behind a proxy (reverse proxy setup)

A common post-install setup is to make requests to the app transit through a gateway server such as Apache or nginx.  
If you do so, please note that archive uploads through LRR will likely **not work out of the box** due to maximum sizes on uploads those servers can enforce. The example below is for nginx:

```
http {
    client_max_body_size 0;   <----------------------- This line here
}

server {
    listen 80;

    server_name lanraragi.[REDACTED].net;

    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    index index.php index.html index.htm;
    server_name lanraragi.[REDACTED].net;

    client_max_body_size 0;   <----------------------- And this line here

    # Cert Stuff Omitted

    location / {
        proxy_pass http://0.0.0.0:3000;
        proxy_http_version 1.1;
        <----- The two following lines are needed for batch tagger support with SSL ----->
        proxy_set_header Upgrade $http_upgrade; 
        proxy_set_header Connection $connection_upgrade;
    }
}
```

## Setting up LANraragi to use a proxy for outbound network requests

This is a less common scenario, but you might want to have downloads or metadata requests to external services go through a proxy, in case said external services are blocked by your friendly local totalitarian regime.  

LANraragi runs on top of the Mojolicious web server, which has [built-in](https://docs.mojolicious.org/Mojo/UserAgent/Proxy#detect) support for proxifying external requests.  

To enable automatic proxy detection, the `MOJO_PROXY` environment variable must be set to 1 on your machine: This is enabled by default on Docker builds.  
Once said detection enabled, environment variables `HTTP_PROXY, http_proxy, HTTPS_PROXY, https_proxy, NO_PROXY` and `no_proxy` will be checked for proxy information.  

Here's an example for a Docker-compose setup:  

```
---
version: "2.1"
services:
  lanraragi:
    image: difegue/lanraragi:latest
    container_name: lanraragi
    environment:
      - http_proxy=http://192.168.10.186:1082
      - https_proxy=http://192.168.10.186:1082
    volumes:
      - [database]:/root/lanraragi/database
      - [content]:/root/lanraragi/content
    ports:
      - 7070:3000
    restart: unless-stopped
```
