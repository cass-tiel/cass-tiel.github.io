#!/bin/sh

ver="3.2.1"
if [ ! -z $1 ]; then
    ver="$1"
fi
zabbix_version="zabbix-${ver}"
install_dir="/usr/local/product"
zabbix_dir="/usr/local/zabbix"
zabbix_server_ip="192.168.0.11"

function sysVersion() {
    ## Check OS
    if grep 'CentOS' /etc/issue > /dev/null 2>&1 ;then
        OS_TYPE='centos'
    elif grep 'Red Hat' /etc/issue > /dev/null 2>&1 ;then
        OS_TYPE='redhat'
    else
        echo "error system"
        exit
    fi

    ## Check OS Version
    if [ ${OS_TYPE} = 'centos' ]; then
        OS_VER=$(awk '$1~/CentOS/{print $3}' /etc/issue | cut -d. -f1)
    elif [ ${OS_TYPE} = 'redhat' ]; then
        OS_VER=$(awk '$1~/Red/{print $7}' /etc/issue)
    fi
}

function addUser() {
    #创建zabbix用户
    useradd -s /sbin/nologin zabbix
    mkdir -p ${install_dir}
    mkdir -p /var/log/zabbix
}

function Install() {
    #安装gcc编译器
    yum install gcc -y

    [ ! -f "${zabbix_version}.tar.gz" ] && echo "no file" && exit
    tar -zxf ${zabbix_version}.tar.gz

    #安装zabbix-agent
    cd ${zabbix_version}
    if [ -d ${install_dir}/${zabbix_version} ]; then
        echo "!!!!! ${install_dir}/${zabbix_version} exists! please check!"
        exit;
    fi
    ./configure --prefix=${install_dir}/${zabbix_version} --enable-agent
    make
    make install
    [ $? -ne 0 ] && echo "编译失败！" && exit
    echo "编译完成..."
    ln -s ${install_dir}/${zabbix_version} ${zabbix_dir}
    mkdir -p ${zabbix_dir}/share/zabbix/externalscripts
}

function makeConf() {
    #编辑agent配置文件
    cat >${zabbix_dir}/etc/zabbix_agentd.conf <<EOF
PidFile=/tmp/zabbix_agentd.pid
LogFile=/var/log/zabbix/zabbix_agentd.log
LogFileSize=10
DebugLevel=3
EnableRemoteCommands=1
LogRemoteCommands=1
RefreshActiveChecks=60
Server=${zabbix_server_ip}
ServerActive=${zabbix_server_ip}
ListenPort=10050
StartAgents=5
AllowRoot=1
Timeout=30
Include=${zabbix_dir}/etc/zabbix_agentd.conf.d/*.conf
LoadModulePath=${zabbix_dir}/share/zabbix/modules
EOF
}


function makeStart6() {
    #编辑agent启动脚本
    cat >/etc/init.d/zabbix_agentd <<EOF
#!/bin/bash
#
#       /etc/rc.d/init.d/zabbix_agentd
#
# Starts the zabbix_agentd daemon
#
# chkconfig: - 95 5
# description: Zabbix Monitoring Agent
# processname: zabbix_agentd
# pidfile: /tmp/zabbix_agentd.pid
# May 2012, Zabbix SIA

# Source function library.

. /etc/init.d/functions

RETVAL=0
prog="Zabbix Agent"
ZABBIX_BIN="${zabbix_dir}/sbin/zabbix_agentd"
ZABBIX_CONF="${zabbix_dir}/etc/zabbix_agentd.conf"

if [ ! -x \${ZABBIX_BIN} ] ; then
        echo -n "\${ZABBIX_BIN} not installed! "
        # Tell the user this has skipped
        exit 5
fi

start() {
        echo -n \$"Starting \$prog: "
        daemon \$ZABBIX_BIN -c \${ZABBIX_CONF}
        RETVAL=\$?
        [ \$RETVAL -eq 0 ] && touch /var/lock/subsys/zabbix_agentd
        echo
}

stop() {
        echo -n \$"Stopping \$prog: "
        killproc \$ZABBIX_BIN
        RETVAL=\$?
        [ \$RETVAL -eq 0 ] && rm -f /var/lock/subsys/zabbix_agentd
        echo
}

case "\$1" in
  start)
        start
        ;;
  stop)
        stop
        ;;
  reload|restart)
        stop
        sleep 10
        start
        RETVAL=\$?
        ;;
  condrestart)
        if [ -f /var/lock/subsys/zabbix_agentd ]; then
            stop
            start
        fi
        ;;
  status)
        status \$ZABBIX_BIN
        RETVAL=\$?
        ;;
  *)
        echo \$"Usage: \$0 {condrestart|start|stop|restart|reload|status}"
        exit 1
esac

exit \$RETVAL
EOF

    chmod +x /etc/init.d/zabbix_agentd
    chkconfig zabbix_agentd on
    echo "配置完成..."
    /etc/init.d/zabbix_agentd start
    [ $? -ne 0 ] && echo "启动失败！" && exit
}

function makeStart7() {
    #编辑agent启动脚本
    cat >/usr/lib/systemd/system/zabbix-agent.service <<EOF
[Unit]
Description=Zabbix Agent
After=syslog.target
After=network.target

[Service]
Environment="CONFFILE=${zabbix_dir}/etc/zabbix_agentd.conf"
EnvironmentFile=-/etc/sysconfig/zabbix-agent
Type=forking
Restart=on-failure
PIDFile=/tmp/zabbix_agentd.pid
KillMode=control-group
ExecStart=${zabbix_dir}/sbin/zabbix_agentd -c \$CONFFILE
ExecStop=/bin/kill -SIGTERM \$MAINPID
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable zabbix-agent
    systemctl start zabbix-agent
    echo "配置完成..."
    [ $? -ne 0 ] && echo "启动失败！" && exit
}

function main() {
    #sysVersion
    addUser
    Install
    makeConf
    SYS_VER=$(ps --pid 1 -o comm | tail -1)
    if [ "${SYS_VER}" == "init" ]; then
        makeStart6
    elif [ "${SYS_VER}" == "systemd" ]; then
        makeStart7
    else
        echo "not found"
    fi

    echo "安装完成，已启动 ^_^"
}

main
