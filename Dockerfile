FROM debian:jessie

MAINTAINER kellyc@stratisiot.com

RUN apt-get update && apt-get install -y \
    libssl-dev \
    logrotate \
    sudo \
    iproute2 \
    net-tools \
    curl \
    mosquitto-clients \
&& rm -rf /var/lib/apt/lists/*

ENV VERNEMQ_VERSION 1.6.2

ADD https://bintray.com/artifact/download/erlio/vernemq/deb/jessie/vernemq_$VERNEMQ_VERSION-1_amd64.deb /tmp/vernemq.deb

RUN dpkg -i /tmp/vernemq.deb
RUN rm /tmp/vernemq.deb

ADD files/vm.args /etc/vernemq/vm.args

ADD bin/vernemq.sh /usr/sbin/start_vernemq
ADD bin/rand_cluster_node.escript /var/lib/vernemq/rand_cluster_node.escript
RUN chown vernemq:vernemq /var/lib/vernemq/rand_cluster_node.escript

# MQTT 1883
# MQTT/SSL 8883
# MQTT WebSockets 8080
# VerneMQ Message Distribution 44053
# EPMD - Erlang Port Mapper Daemon 4349
# Prometheus Metrics 8888
# Specific Distributed Erlang Port Range 9100-9109
EXPOSE 1883 8883 8080 44053 4349 8888 9100-9109

VOLUME ["/var/log/vernemq", "/var/lib/vernemq", "/etc/vernemq"]

CMD ["start_vernemq"] 

