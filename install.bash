set -ue
set -o pipefail

yum install -y https://github.com/martin-helmich/prometheus-nginxlog-exporter/releases/download/v1.9.0/prometheus-nginxlog-exporter_1.9.0_linux_amd64.rpm
mv /etc/prometheus-nginxlog-exporter.hcl /etc/prometheus-nginxlog-exporter.hcl.orig
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

cat > /etc/logrotate.d/nginx.patch <<'_EOD_'
--- nginx.orig  2021-08-17 12:25:44.841912093 +0900
+++ nginx       2021-08-17 12:26:41.358451393 +0900
@@ -8,5 +8,6 @@
     sharedscripts
     postrotate
         /etc/init.d/nginx reload
+        service prometheus-nginxlog-exporter restart
     endscript
 }
_EOD_
(
  cd /etc/logrotate.d
  cp nginx nginx.orig."$(date '+%Y%m%d')"
  git apply nginx.patch
)


# No use systemctl for Amazon Linux 1
service prometheus-nginxlog-exporter restart
#systemctl enable prometheus-nginxlog-exporter
#systemctl start prometheus-nginxlog-exporter
#systemctl status prometheus-nginxlog-exporter
