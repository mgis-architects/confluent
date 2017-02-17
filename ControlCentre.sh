#!/bin/bash
#
systemctl status firewalld
firewall-cmd --get-active-zones
firewall-cmd --zone=public --list-ports
firewall-cmd --zone=public --add-port=9091/tcp --permanent
firewall-cmd --reload
firewall-cmd --zone=public --list-ports
#
mkdir -p /tmp/control-center/data
#
docker run -d \
  --name=control-center \
  --net=host \
  --ulimit nofile=16384:16384 \
  -p 9021:9021 \
  -v /tmp/control-center/data:/var/lib/confluent-control-center \
  -e CONTROL_CENTER_ZOOKEEPER_CONNECT=10.9.3.4:22181,10.9.3.5:32181,10.9.3.6:42181 \
  -e CONTROL_CENTER_BOOTSTRAP_SERVERS=10.9.3.4:29092,10.9.3.5:39092,10.9.3.6:49092 \
  -e CONTROL_CENTER_REPLICATION_FACTOR=3 \
  -e CONTROL_CENTER_MONITORING_INTERCEPTOR_TOPIC_PARTITIONS=3 \
  -e CONTROL_CENTER_INTERNAL_TOPICS_PARTITIONS=3 \
  -e CONTROL_CENTER_STREAMS_NUM_STREAM_THREADS=2 \
  -e CONTROL_CENTER_CONNECT_CLUSTER=10.9.3.7:28083,10.9.3.8:28083 \
  confluentinc/cp-enterprise-control-center:3.1.2

