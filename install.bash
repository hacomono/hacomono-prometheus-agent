set -ue
set -o pipefail

yum install -y https://github.com/martin-helmich/prometheus-nginxlog-exporter/releases/download/v1.9.0/prometheus-nginxlog-exporter_1.9.0_linux_amd64.rpm
mv /etc/prometheus-nginxlog-exporter.hcl /etc/prometheus-nginxlog-exporter.hcl.orig."$(date '+%Y%m%d')"
cat > /etc/prometheus-nginxlog-exporter.hcl <<'_EOD_'
listen {
  port = 4040
  metrics_endpoint = "/metrics"
}

namespace "nginx" {
  source = {
    files = [
      "/var/log/nginx/access.log"
    ]
  }

  format = "$remote_addr - $remote_user [$time_local] \"$request\" $status $body_bytes_sent \"$http_referer\" \"$http_user_agent\" \"$http_x_forwarded_for\" rt=\"$request_time\" uct=\"$upstream_connect_time\" uht=\"$upstream_header_time\" urt=\"$upstream_response_time\""

  relabel "request_uri" {
    from = "request"
    split = 2
    separator = " "
    match "^/([^?]*).*" {
      replacement = "/$1"
    }
  }

  relabel "host" {
    from = "server_name"
  }

  labels {
    app = "default"
  }
}
_EOD_

if [ ! -f /etc/logrotate.d/nginx ] || grep -q "service prometheus-nginxlog-exporter restart" /etc/logrotate.d/nginx; then
  echo "Already appended service prometheus-nginxlog-exporter restart"
else
  sed -i '/^}/d' /etc/logrotate.d/nginx
  cat >> /etc/logrotate.d/nginx <<'_EOD_'
    lastaction
        service prometheus-nginxlog-exporter restart
    endscript
}
_EOD_
fi

# No use systemctl for Amazon Linux 1
service prometheus-nginxlog-exporter restart
#systemctl enable prometheus-nginxlog-exporter
#systemctl start prometheus-nginxlog-exporter
#systemctl status prometheus-nginxlog-exporter
