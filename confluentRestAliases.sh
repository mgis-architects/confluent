export confluentRestUrl=http://10.135.50.7:28082
alias brokers.list='curl -X GET -H "Content-Type: application/json" ${confluentRestUrl}/brokers 2> /dev/null | python -mjson.tool'
function topics.list() { curl -X GET -H "Content-Type: application/json" ${confluentRestUrl}/topics/${1} 2>/dev/null | python -mjson.tool; }
function topic.get() { curl -X GET -H "Content-Type: application/json" ${confluentRestUrl}/topics/${1} 2>/dev/null | python -mjson.tool; }
function partition.list() { curl -X GET -H "Content-Type: application/json" ${confluentRestUrl}/topics/${1}/partitions 2>/dev/null | python -mjson.tool; }
function partition.get() { curl -X GET -H "Content-Type: application/json" ${confluentRestUrl}/topics/${1}/partitions/${2} 2>/dev/null | python -mjson.tool; }
function consumer.createbinary() { group=$1; instance=$2; echo '{ "id": "'$instance'", "format": "binary", "auto.offset.reset": "smallest", "auto.commit.enable": "false" }' > /tmp/consumer.create.$$.json; curl -X POST -H "Content-Type: application/vnd.kafka.binary.v1+json" --data-binary "@/tmp/consumer.create.$$.json" ${confluentRestUrl}/consumers/${group} 2>/dev/null | python -mjson.tool; }
function consumer.createavro() { group=$1; instance=$2; echo '{ "id": "'$instance'", "format": "binary", "auto.offset.reset": "smallest", "auto.commit.enable": "false" }' > /tmp/consumer.create.$$.json; curl -X POST -H "Content-Type: application/vnd.kafka.avro.v1+json" --data-binary "@/tmp/consumer.create.$$.json" ${confluentRestUrl}/consumers/${group} 2>/dev/null | python -mjson.tool; }
function consumer.readbinary() { group=$1; instance=$2; topic_name=$3; curl -X GET -H "Content-Type: application/vnd.kafka.binary.v1+json" ${confluentRestUrl}/consumers/${group}/instances/${instance}/topics/${topic_name} 2>/dev/null | python -mjson.tool; }
function consumer.readavro() { group=$1; instance=$2; topic_name=$3; curl -X GET -H "Content-Type: application/vnd.kafka.avro.v1+json" ${confluentRestUrl}/consumers/${group}/instances/${instance}/topics/${topic_name} 2>/dev/null | python -mjson.tool; }
function consumer.commit() { group=$1; instance=$2; curl -X POST -H "Content-Type: application/json" ${confluentRestUrl}/consumers/${group}/instances/${instance}/offsets 2>/dev/null | python -mjson.tool; }
function consumer.delete() { group=$1; instance=$2; curl -X DELETE -H "Content-Type: application/json" ${confluentRestUrl}/consumers/${group}/instances/${instance}; }
# partition.produce-avro	POST /topics/{topic}/partitions/{partition} with Content-Type: application/vnd.kafka.avro.v1+json header
# partition.produce-binary	POST /topics/{topic}/partitions/{partition} with Content-Type: application/vnd.kafka.binary.v1+json header
# topic.produce-avro	POST /topics/{topic} with Content-Type: application/vnd.kafka.avro.v1+json header
# topic.produce-binary	POST /topics/{topic} with Content-Type: application/vnd.kafka.binary.v1+json header
