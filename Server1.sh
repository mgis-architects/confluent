#!/bin/bash
#
docker run -d \
   --net=host \
   --name=zk-1 \
   -e ZOOKEEPER_SERVER_ID=1 \
   -e ZOOKEEPER_CLIENT_PORT=22181 \
   -e ZOOKEEPER_TICK_TIME=2000 \
   -e ZOOKEEPER_INIT_LIMIT=5 \
   -e ZOOKEEPER_SYNC_LIMIT=2 \
   -e ZOOKEEPER_SERVERS="10.9.3.4:22888:23888;10.9.3.5:22888:23888;10.9.3.6:22888:23888" \
    confluentinc/cp-zookeeper:3.1.2

