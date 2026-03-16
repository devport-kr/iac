#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=== DevPort Proxy Instance Setup ==="
echo "API Domain: ${api_domain}"
echo "Backend IP: ${backend_ip}"

# Wait for internet connectivity
echo "=== Waiting for internet connectivity ==="
for i in {1..30}; do
    if curl -s --connect-timeout 2 https://amazon.com > /dev/null; then
        echo "Internet connection established."
        break
    fi
    echo "Waiting for internet (attempt $i/30)..."
    sleep 5
done

# Update system
echo "=== Updating system packages ==="
dnf update -y

# Install required packages
echo "=== Installing packages ==="
dnf install -y \
    nginx \
    awscli \
    python3-pip \
    augeas-libs \
    jq \
    cronie

# Install Certbot with Route53 DNS plugin
echo "=== Installing Certbot ==="
pip3 install certbot certbot-dns-route53

# Write nginx configuration BEFORE cert (so config is always present)
echo "=== Writing nginx configuration ==="
cat > /etc/nginx/nginx.conf << 'NGINX_CONF'
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent"';
    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    keepalive_timeout 65;

    # HTTP -> HTTPS redirect
    server {
        listen 80;
        server_name ${api_domain};
        return 301 https://$host$request_uri;
    }

    server {
        listen       443 ssl;
        server_name  ${api_domain};

        ssl_certificate     /etc/letsencrypt/live/${api_domain}/fullchain.pem;
        ssl_certificate_key /etc/letsencrypt/live/${api_domain}/privkey.pem;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_prefer_server_ciphers on;
        ssl_session_cache   shared:SSL:10m;
        ssl_session_timeout 10m;

        # SSE endpoint — buffering MUST be off or stream never reaches client
        location /api/wiki/projects/chat/stream {
            proxy_pass         http://${backend_ip}:8080;
            proxy_buffering    off;
            proxy_cache        off;
            proxy_set_header   Connection '';
            proxy_http_version 1.1;
            chunked_transfer_encoding on;
            proxy_set_header   Host $host;
            proxy_set_header   X-Real-IP $remote_addr;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $scheme;
            proxy_read_timeout 300s;
        }

        # All other traffic -> private EC2
        location / {
            proxy_pass         http://${backend_ip}:8080;
            proxy_set_header   Host $host;
            proxy_set_header   X-Real-IP $remote_addr;
            proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header   X-Forwarded-Proto $scheme;
            proxy_read_timeout 300s;
            proxy_connect_timeout 75s;
        }
    }
}
NGINX_CONF

# Obtain SSL certificate via DNS-01 challenge
echo "=== Obtaining SSL certificate for ${api_domain} ==="
for i in {1..5}; do
    certbot certonly \
        --dns-route53 \
        -d ${api_domain} \
        --non-interactive \
        --agree-tos \
        -m ${certbot_email} \
    && break
    echo "Certbot attempt $i failed, waiting 30s before retry..."
    sleep 30
done

if [ ! -f "/etc/letsencrypt/live/${api_domain}/fullchain.pem" ]; then
    echo "WARNING: SSL certificate not obtained. Nginx will not start until cert is provisioned manually:"
    echo "  certbot certonly --dns-route53 -d ${api_domain} --non-interactive --agree-tos -m ${certbot_email}"
else
    # Start nginx only after cert is available
    systemctl enable nginx
    systemctl start nginx
fi

# Cert auto-renewal at 2 AM (reloads nginx after renewal)
echo "0 2 * * * root /usr/local/bin/certbot renew --quiet --post-hook 'systemctl reload nginx'" >> /etc/crontab

systemctl enable crond
systemctl start crond

echo ""
echo "=== Proxy setup complete ==="
echo "Nginx is proxying ${api_domain} -> ${backend_ip}:8080"
