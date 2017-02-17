#!/bin/bash
#
systemctl status firewalld
firewall-cmd --get-active-zones
firewall-cmd --zone=public --list-ports
firewall-cmd --zone=public --add-port=22888/tcp --permanent
firewall-cmd --zone=public --add-port=23888/tcp --permanent
firewall-cmd --zone=public --add-port=22181/tcp --permanent
firewall-cmd --zone=public --add-port=32181/tcp --permanent
firewall-cmd --zone=public --add-port=42181/tcp --permanent
firewall-cmd --zone=public --add-port=29092/tcp --permanent
firewall-cmd --zone=public --add-port=39092/tcp --permanent
firewall-cmd --zone=public --add-port=49092/tcp --permanent
firewall-cmd --reload
firewall-cmd --zone=public --list-ports
#
docker run -d \
   --net=host \
   --name=zk-3 \
   -e ZOOKEEPER_SERVER_ID=3 \
   -e ZOOKEEPER_CLIENT_PORT=42181 \
   -e ZOOKEEPER_TICK_TIME=2000 \
   -e ZOOKEEPER_INIT_LIMIT=5 \
   -e ZOOKEEPER_SYNC_LIMIT=2 \
   -e ZOOKEEPER_SERVERS="10.9.3.4:22888:23888;10.9.3.5:22888:23888;10.9.3.6:22888:23888" \
   confluentinc/cp-zookeeper:3.1.2

