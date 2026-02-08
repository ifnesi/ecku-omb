# Create EC2 instance for the PNI Proxy
resource "aws_instance" "proxy" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type_proxy
  key_name                    = aws_key_pair.main.key_name
  vpc_security_group_ids      = [aws_security_group.main.id]
  subnet_id                   = aws_subnet.main[0].id
  associate_public_ip_address = true

  user_data = <<-EOFPROXY
#!/bin/bash

set -e

# 1. Install nginx and stream module (Amazon Linux 2023 specific)
yum update -y
yum install -y wget yum-utils nginx nginx-mod-stream bind-utils

# 2. START of setting up https://docs.confluent.io/cloud/current/networking/ccloud-console-access.html#configure-a-proxy
BOOTSTRAP_HOST="${local.pni_bootstrap_endpoint}"
echo "Setting up NGINX proxy for Confluent Cloud PNI" >> /var/log/user-data.log
echo "Bootstrap host: $BOOTSTRAP_HOST" >> /var/log/user-data.log

# 3. Test NGINX configuration (before we modify it)
echo "Testing initial NGINX configuration..." >> /var/log/user-data.log
nginx -t >> /var/log/user-data.log 2>&1

# 4. Check if ngx_stream_module.so exists and set MODULE_PATH
echo "Checking for stream module..." >> /var/log/user-data.log
if [ -f /usr/lib64/nginx/modules/ngx_stream_module.so ]; then
  MODULE_PATH="/usr/lib64/nginx/modules/ngx_stream_module.so"
  echo "Found stream module at: $MODULE_PATH" >> /var/log/user-data.log
elif [ -f /usr/lib/nginx/modules/ngx_stream_module.so ]; then
  MODULE_PATH="/usr/lib/nginx/modules/ngx_stream_module.so"
  echo "Found stream module at: $MODULE_PATH" >> /var/log/user-data.log
else
  echo "ERROR: ngx_stream_module.so not found!" >> /var/log/user-data.log
  exit 1
fi

# 5. Use AWS resolver directly (we know it works on EC2)
RESOLVER="169.254.169.253"
echo "Using AWS resolver: $RESOLVER" >> /var/log/user-data.log

# 6. Update NGINX configuration
#------------------------------
cat > /etc/nginx/nginx.conf <<NGINXCONF
load_module $MODULE_PATH;

events {}
stream {
  map \$ssl_preread_server_name \$targetBackend {
    default \$ssl_preread_server_name;
  }

  server {
    listen 9092;
    proxy_connect_timeout 1s;
    proxy_timeout 7200s;
    resolver $RESOLVER;
    proxy_pass \$targetBackend:9092;
    ssl_preread on;
  }

  server {
    listen 443;
    proxy_connect_timeout 1s;
    proxy_timeout 7200s;
    resolver $RESOLVER;
    proxy_pass \$targetBackend:443;
    ssl_preread on;
  }

  log_format stream_routing '[\$time_local] remote address \$remote_addr '
                            'with SNI name "\$ssl_preread_server_name" '
                            'proxied to "\$upstream_addr" '
                            '\$protocol \$status \$bytes_sent \$bytes_received '
                            '\$session_time';
  access_log /var/log/nginx/stream-access.log stream_routing;
}
NGINXCONF
#------------------------------

# 7. Re-test NGINX configuration
echo "Testing NGINX configuration after update..." >> /var/log/user-data.log
if nginx -t >> /var/log/user-data.log 2>&1; then
  echo "NGINX configuration test passed" >> /var/log/user-data.log
else
  echo "NGINX configuration test failed:" >> /var/log/user-data.log
  nginx -t >> /var/log/user-data.log 2>&1
  exit 1
fi

# 8. Restart NGINX
echo "Restarting NGINX..." >> /var/log/user-data.log
systemctl restart nginx

# 9. Verify NGINX is running
echo "Verifying NGINX status..." >> /var/log/user-data.log
if systemctl is-active --quiet nginx; then
  echo "NGINX is running successfully" >> /var/log/user-data.log
  systemctl status nginx >> /var/log/user-data.log 2>&1
else
  echo "NGINX failed to start:" >> /var/log/user-data.log
  systemctl status nginx >> /var/log/user-data.log 2>&1
  # Check error logs as suggested in Confluent docs
  echo "NGINX error log:" >> /var/log/user-data.log
  tail -20 /var/log/nginx/error.log >> /var/log/user-data.log 2>&1
  exit 1
fi

# 10. Enable NGINX to start on boot
systemctl enable nginx
echo "Proxy setup completed successfully!" >> /var/log/user-data.log
echo "You can now test with: nslookup $BOOTSTRAP_HOST $RESOLVER" >> /var/log/user-data.log
EOFPROXY

  tags = {
    Name  = "${var.demo_prefix}-ec2_proxy-${random_id.id.hex}"
    owner = var.owner
  }
}
