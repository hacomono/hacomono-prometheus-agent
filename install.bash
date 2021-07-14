#! /bin/bash
set -ue
set -o pipefail

yum install -y https://github.com/martin-helmich/prometheus-nginxlog-exporter/releases/download/v1.9.0/prometheus-nginxlog-exporter_1.9.0_linux_amd64.rpm
mv /etc/prometheus-nginxlog-exporter.hcl /etc/prometheus-nginxlog-exporter.hcl.orig
cat > /etc/prometheus-nginxlog-exporter.hcl <<'_EOD_'
listen {
  port = 4040
}

namespace "nginx" {
  source = {
    files = [
      "/var/log/nginx/access.log"
    ]
  }

  format = "$remote_addr - $remote_user [$time_local] \"$request\" $status $body_bytes_sent \"$http_referer\" \"$http_user_agent\""

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

systemctl enable prometheus-nginxlog-exporter
systemctl start prometheus-nginxlog-exporter
systemctl status prometheus-nginxlog-exporter
