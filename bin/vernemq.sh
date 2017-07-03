#!/usr/bin/env bash

IP_ADDRESS=$(ip -4 addr show eth0 | grep -oP "(?<=inet).*(?=/)"| sed -e "s/^[[:space:]]*//" | tail -n 1)

# Ensure correct ownership and permissions on volumes
chown vernemq:vernemq /var/lib/vernemq /var/log/vernemq
chmod 755 /var/lib/vernemq /var/log/vernemq

# Ensure the Erlang node name is set correctly
sed -i.bak "s/VerneMQ@127.0.0.1/VerneMQ@${IP_ADDRESS}/" /etc/vernemq/vm.args

if env | grep -q "DOCKER_VERNEMQ_DISCOVERY_NODE"; then
    echo "-eval \"vmq_server_cmd:node_join('VerneMQ@${DOCKER_VERNEMQ_DISCOVERY_NODE}')\"" >> /etc/vernemq/vm.args
fi

# Cluster discovery implementation based on https://github.com/thesandlord/kubernetes-pod-ip-finder
if env | grep -q "KUBE_VERNEMQ_DISCOVERY_URL"; then
    response=$(curl ${KUBE_VERNEMQ_DISCOVERY_URL})
    IFS=','
    nodes=($(echo "$response" | tr -d '[]"'))
    length=$(echo ${#nodes[@]})
    for i in "${nodes[@]}"
    do
      if [ "$i" != "null" ] && [ "$i" != "$IP_ADDRESS" ] && (($length > 1)); then
        echo "Start Joining to VerneMQ@${i}."
        echo "-eval \"vmq_server_cmd:node_join('VerneMQ@${i}')\"" >> /etc/vernemq/vm.args
      fi
    done
    IFS=''
fi

sed -i '/########## Start ##########/,/########## End ##########/d' /etc/vernemq/vernemq.conf

echo "########## Start ##########" >> /etc/vernemq/vernemq.conf

env | grep DOCKER_VERNEMQ | grep -v DISCOVERY_NODE | cut -c 16- | tr '[:upper:]' '[:lower:]' | sed 's/__/./g' >> /etc/vernemq/vernemq.conf

echo "erlang.distribution.port_range.minimum = 9100" >> /etc/vernemq/vernemq.conf
echo "erlang.distribution.port_range.maximum = 9109" >> /etc/vernemq/vernemq.conf
echo "listener.tcp.default = ${IP_ADDRESS}:1883" >> /etc/vernemq/vernemq.conf
echo "listener.ws.default = ${IP_ADDRESS}:8080" >> /etc/vernemq/vernemq.conf
echo "listener.vmq.clustering = ${IP_ADDRESS}:44053" >> /etc/vernemq/vernemq.conf
echo "listener.http.metrics = ${IP_ADDRESS}:8888" >> /etc/vernemq/vernemq.conf

if [ -e /etc/vernemq-cfg/vernemq.conf.overrides ]; then
    cat /etc/vernemq-cfg/vernemq.conf.overrides >> /etc/vernemq/vernemq.conf
fi

if [ -e /etc/vernemq-cfg/vmq_plugin.conf ]; then
    cp /etc/vernemq-cfg/vmq_plugin.conf /usr/lib/vernemq/lib
    chown vernemq:vernemq /usr/lib/vernemq/lib/vmq_plugin.conf
fi

echo "########## End ##########" >> /etc/vernemq/vernemq.conf

# Check configuration file
su - vernemq -c "/usr/sbin/vernemq config generate 2>&1 > /dev/null" | tee /tmp/config.out | grep error

if [ $? -ne 1 ]; then
    echo "configuration error, exit"
    echo "$(cat /tmp/config.out)"
    exit $?
fi

pid=0

# SIGUSR1-handler
siguser1_handler() {
    echo "stopped"
}

# SIGTERM-handler
sigterm_handler() {
    if [ $pid -ne 0 ]; then
        # this will stop the VerneMQ process
        vmq-admin cluster leave node=VerneMQ@$IP_ADDRESS -k > /dev/null
        wait "$pid"
    fi
    exit 143; # 128 + 15 -- SIGTERM
}

# setup handlers
# on callback, kill the last background process, which is `tail -f /dev/null`
# and execute the specified handler
trap 'kill ${!}; siguser1_handler' SIGUSR1
trap 'kill ${!}; sigterm_handler' SIGTERM

/usr/sbin/vernemq start
pid=$(ps aux | grep '[b]eam.smp' | awk '{print $2}')

while true
do
    tail -qF /var/log/vernemq/console.log /var/log/vernemq/error.log /var/log/vernemq/crash.log /var/log/vernemq/erlang.log.1 & wait ${!}
done
