#!/bin/bash
#
# Open ports ...
#
systemctl status firewalld
firewall-cmd --get-active-zones
firewall-cmd --zone=public --list-ports
firewall-cmd --zone=public --add-port=28082/tcp --permanent
firewall-cmd --zone=public --add-port=28083/tcp --permanent
firewall-cmd --reload
firewall-cmd --zone=public --list-ports
#
docker run -d --net=host --name=schema-registry01 \
  -e SCHEMA_REGISTRY_KAFKASTORE_CONNECTION_URL=10.9.3.4:22181,10.9.3.5:32181,10.9.3.6:42181 \
  -e SCHEMA_REGISTRY_HOST_NAME=10.9.3.7 \
  -e SCHEMA_REGISTRY_LISTENERS=http://10.9.3.7:28081 \
  confluentinc/cp-schema-registry:3.1.2
#
docker run -d \
  --net=host \
  --name=kafka-rest01 \
  -e KAFKA_REST_ZOOKEEPER_CONNECT=10.9.3.4:22181,10.9.3.5:32181,10.9.3.6:42181 \
  -e KAFKA_REST_LISTENERS=http://10.9.3.7:28082 \
  -e KAFKA_REST_SCHEMA_REGISTRY_URL=http://10.9.3.7:28081 \
  -e KAFKA_REST_HOST_NAME=10.9.3.7 \
  confluentinc/cp-kafka-rest:3.1.2
#
docker run -d \
  --name=kafka-connect01 \
  --net=host \
  -e CONNECT_BOOTSTRAP_SERVERS=10.9.3.4:29092,10.9.3.5:39092,10.9.3.6:49092 \
  -e CONNECT_REST_PORT=28083 \
  -e CONNECT_GROUP_ID="quickstart" \
  -e CONNECT_CONFIG_STORAGE_TOPIC="quickstart-config" \
  -e CONNECT_OFFSET_STORAGE_TOPIC="quickstart-offsets" \
  -e CONNECT_STATUS_STORAGE_TOPIC="quickstart-status" \
  -e CONNECT_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e CONNECT_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e CONNECT_INTERNAL_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e CONNECT_INTERNAL_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
  -e CONNECT_REST_ADVERTISED_HOST_NAME=10.9.3.7 \
  confluentinc/cp-kafka-connect:3.1.2



