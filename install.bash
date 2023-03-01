set -ue
set -o pipefail

NGINXLOG_VERSION=1.9.0
if hash systemctl; then
  # systemd
  yum install -y https://github.com/martin-helmich/prometheus-nginxlog-exporter/releases/download/v${NGINXLOG_VERSION}/prometheus-nginxlog-exporter_${NGINXLOG_VERSION}_linux_amd64.rpm || true

else
  (
    mkdir -p /tmp/prometheus-nginxlog-exporter_$$
    cd /tmp/prometheus-nginxlog-exporter_$$
    curl -o prometheus-nginxlog-exporter_${NGINXLOG_VERSION}_linux_amd64.tar.gz -L https://github.com/martin-helmich/prometheus-nginxlog-exporter/releases/download/v${NGINXLOG_VERSION}/prometheus-nginxlog-exporter_${NGINXLOG_VERSION}_linux_amd64.tar.gz
    tar zxvf prometheus-nginxlog-exporter_${NGINXLOG_VERSION}_linux_amd64.tar.gz
    cp -p prometheus-nginxlog-exporter /usr/local/sbin

    # SysVinit
    cat > /etc/init.d/prometheus-nginxlog-exporter <<'_EOD_'
#!/bin/bash
#
#   /etc/rc.d/init.d/prometheus-nginxlog-exporter
#
# chkconfig: 2345 70 30
#
# pidfile: /var/run/prometheus-nginxlog-exporter.pid

# Source function library.
. /etc/init.d/functions

RETVAL=0
ARGS="-config-file /etc/prometheus-nginxlog-exporter.hcl"
PROG="prometheus-nginxlog-exporter"
DAEMON="/usr/local/sbin/${PROG}"
PID_FILE=/var/run/${PROG}.pid
LOG_FILE=/var/log/node_exporter.log
LOCK_FILE=/var/lock/subsys/${PROG}
GOMAXPROCS=$(grep -c ^processor /proc/cpuinfo)

start() {
    if check_status > /dev/null; then
        echo "node_exporter is already running"
        exit 0
    fi

    echo -n $"Starting node_exporter: "
    ${DAEMON} ${ARGS} 1>>${LOG_FILE} 2>&1 &
    echo $! > ${PID_FILE}
    RETVAL=$?
    [ $RETVAL -eq 0 ] && touch ${LOCK_FILE}
    echo ""
    return $RETVAL
}

stop() {
    if check_status > /dev/null; then
        echo -n $"Stopping node_exporter: "
        kill -9 "$(cat ${PID_FILE})"
        RETVAL=$?
        [ $RETVAL -eq 0 ] && rm -f ${LOCK_FILE} ${PID_FILE}
        echo ""
        return $RETVAL
    else
        echo "node_exporter is not running"
        rm -f ${LOCK_FILE} ${PID_FILE}
        return 0
    fi
}  

check_status() {
    status -p ${PID_FILE} ${DAEMON}
    RETVAL=$?
    return $RETVAL
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        stop
        start
        ;;
    *)
        N=/etc/init.d/${NAME}
        echo "Usage: $N {start|stop|restart}" >&2
        RETVAL=2
        ;;
esac

exit ${RETVAL}
_EOD_

    chmod +x /etc/init.d/prometheus-nginxlog-exporter
    chkconfig --add prometheus-nginxlog-exporter
    chkconfig prometheus-nginxlog-exporter on
  )
fi

mv /etc/prometheus-nginxlog-exporter.hcl /etc/prometheus-nginxlog-exporter.hcl.orig."$(date '+%Y%m%d')" ||  true
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

  histogram_buckets = [1]

  relabel "request_uri" {
    from = "request"
    split = 2
    separator = " "
    match "^/api/system/dbfiles/.*" {
      replacement = "/api/system/dbfiles"
    }
    match "^/api.*" {
      replacement = "/api"
    }
    match "^.*" {
      replacement = "/other"
    }
  }

  relabel "host" {
    from = "server_name"
  }

  labels {
    app = "default"
  }
}

namespace "path" {
  source = {
    files = [
      "/var/log/nginx/access.log"
    ]
  }

  format = "$remote_addr - $remote_user [$time_local] \"$request\" $status $body_bytes_sent \"$http_referer\" \"$http_user_agent\" \"$http_x_forwarded_for\" rt=\"$request_time\" uct=\"$upstream_connect_time\" uht=\"$upstream_header_time\" urt=\"$upstream_response_time\""

  histogram_buckets = [1]

  relabel "path" {
    from = "request"
    split = 2
    separator = " "
    match "^/api/system/dbfiles/.*" {
      replacement = "/api/system/dbfiles"
    }
    match "^/api/v1/system/sharp-face/user/.*" {
      replacement = "/api/v1/system/sharp-face/user"
    }
    match "^/api/(.*?)/[0-9]+/[0-9]+/[0-9]+(?:$|\\?.*$|(/[^?]*).*$)" {
      replacement = "/api/$1/:id/:id/:id$2"
    }
    match "^/api/(.*?)/[0-9]+/[0-9]+(?:$|\\?.*$|(/[^?]*).*$)" {
      replacement = "/api/$1/:id/:id$2"
    }
    match "^/api/(.*?)/[0-9]+/(.*?)/[0-9]+(?:$|\\?.*$|(/[^?]*).*$)" {
      replacement = "/api/$1/:id/$2/:id$3"
    }
    match "^/api/(.*?)/[0-9]+(?:$|\\?.*$|(/[^?]*).*$)" {
      replacement = "/api/$1/:id$2"
    }
    match "^/api/([^?]*).*" {
      replacement = "/api/$1"
    }
    match "^.*" {
      replacement = "/other"
    }
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
