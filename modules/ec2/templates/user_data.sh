#!/bin/bash
set -e

# Log all output
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=== DevPort EC2 Instance Setup ==="
echo "Project: ${project_name}"
echo "Environment: ${environment}"
echo "Domain: ${domain_name}"
echo "API Domain: ${api_domain}"

# Wait for internet connectivity (NAT instance might still be booting)
echo "=== Waiting for internet connectivity ==="
for i in {1..30}; do
    if curl -s --connect-timeout 2 https://amazon.com > /dev/null; then
        echo "Internet connection established."
        break
    fi
    echo "Waiting for NAT instance to route traffic (attempt $i/30)..."
    sleep 5
done

# Update system
echo "=== Updating system packages ==="
dnf update -y

# Install required packages
echo "=== Installing packages ==="
dnf install -y \
    docker \
    awscli \
    amazon-cloudwatch-agent \
    cronie \
    jq \
    python3-pip \
    augeas-libs

# Install Docker Compose
echo "=== Installing Docker Compose ==="
DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r .tag_name)
curl -L "https://github.com/docker/compose/releases/download/$${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

# Install Certbot with Route53 DNS plugin
# DNS-01 challenge works from private subnet — no inbound port needed
echo "=== Installing Certbot ==="
pip3 install certbot certbot-dns-route53

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Add ec2-user to docker group
usermod -aG docker ec2-user

# Create application directories
echo "=== Creating application directories ==="
mkdir -p /opt/devport/{logs,nginx,nginx-logs}
chown -R ec2-user:ec2-user /opt/devport

# ============================================================
# nginx configuration
# Terraform expands ${api_domain} here.
# Nginx $vars (no braces) pass through Terraform unchanged.
# ============================================================
echo "=== Writing nginx configuration ==="
cat > /opt/devport/nginx/nginx.conf << 'NGINX_CONF'
worker_processes auto;
error_log /var/log/nginx/error.log warn;

events {
    worker_connections 1024;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                      '$status $body_bytes_sent "$http_referer" '
                      '"$http_user_agent"';
    access_log  /var/log/nginx/access.log  main;

    sendfile        on;
    keepalive_timeout 65;

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
            proxy_pass         http://devport-api-native:8080;
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

        # All other API traffic
        location / {
            proxy_pass         http://devport-api-native:8080;
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

chown ec2-user:ec2-user /opt/devport/nginx/nginx.conf

# ============================================================
# Backup script
# ============================================================
echo "=== Creating backup script ==="
mkdir -p /opt/scripts

cat > /opt/scripts/backup.sh << 'BACKUP'
#!/bin/bash
set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BUCKET="${backup_bucket}"

if [ -z "$BUCKET" ]; then
    echo "No backup bucket configured"
    exit 0
fi

echo "Backing up PostgreSQL..."
docker exec devport-postgres-native pg_dump -U ${db_user} ${db_name} | gzip > /tmp/db_backup_$TIMESTAMP.sql.gz

echo "Uploading to S3..."
aws s3 cp /tmp/db_backup_$TIMESTAMP.sql.gz s3://$BUCKET/db/db_backup_$TIMESTAMP.sql.gz

rm /tmp/db_backup_$TIMESTAMP.sql.gz
echo "Backup completed: db_backup_$TIMESTAMP.sql.gz"
BACKUP

chmod +x /opt/scripts/backup.sh

# ============================================================
# CloudWatch Agent
# ============================================================
echo "=== Configuring CloudWatch Agent ==="
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWAGENT'
{
    "agent": {
        "metrics_collection_interval": 60,
        "run_as_user": "root"
    },
    "metrics": {
        "namespace": "DevPort",
        "metrics_collected": {
            "disk": {
                "measurement": ["used_percent"],
                "resources": ["/"],
                "metrics_collection_interval": 60
            },
            "mem": {
                "measurement": ["mem_used_percent"],
                "metrics_collection_interval": 60
            },
            "net": {
                "measurement": ["bytes_sent", "bytes_recv"],
                "resources": ["eth0"],
                "metrics_collection_interval": 60
            }
        }
    },
    "logs": {
        "logs_collected": {
            "files": {
                "collect_list": [
                    {
                        "file_path": "/opt/devport/logs/app.log",
                        "log_group_name": "/devport/spring-boot",
                        "log_stream_name": "{instance_id}",
                        "retention_in_days": 30
                    }
                ]
            }
        }
    }
}
CWAGENT

systemctl enable amazon-cloudwatch-agent
systemctl start amazon-cloudwatch-agent

# Start cronie
systemctl enable crond
systemctl start crond

# Daily DB backup at 3 AM
echo "0 3 * * * root /opt/scripts/backup.sh >> /var/log/backup.log 2>&1" >> /etc/crontab
# Cert auto-renewal at 2 AM (reloads nginx after renewal)
echo "0 2 * * * root /usr/local/bin/certbot renew --quiet --post-hook 'docker exec devport-nginx nginx -s reload'" >> /etc/crontab

# ============================================================
# Obtain SSL certificate via DNS-01 challenge
# IAM role has route53:ChangeResourceRecordSets — no inbound
# port required, works from private subnet via NAT instance.
# ============================================================
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
    echo "ERROR: SSL certificate not obtained."
    echo "Check IAM permissions and retry manually:"
    echo "  certbot certonly --dns-route53 -d ${api_domain} --non-interactive --agree-tos -m ${certbot_email}"
fi

echo ""
echo "=== EC2 setup complete ==="
echo "nginx.conf is at: /opt/devport/nginx/nginx.conf"
echo "Certs will be at: /etc/letsencrypt/live/${api_domain}/"
echo "SSH in and run: docker compose up -d"
