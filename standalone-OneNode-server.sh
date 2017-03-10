#!/bin/bash
#########################################################################################
## standalone-OneNode-server installations 
#########################################################################################
# This script only supports Azure currently, mainly due to the disk persistence method
# Installs Schema / Rest / Connect / Control-Center docker images on a single server
#
# USAGE:
#
#    sudo standalone-OneNode-server.sh standalone-server-build.ini
#
# USEFUL LINKS: 
# 
#
#########################################################################################

g_prog=standalone-OneNode-server
RETVAL=0

######################################################
## defined script variables
######################################################
STAGE_DIR=/tmp/$g_prog/stage
LOG_DIR=/var/log/$g_prog
LOG_FILE=$LOG_DIR/${prog}.log.$(date +%Y%m%d_%H%M%S_%N)
INI_FILE=$LOG_DIR/${g_prog}.ini

THISDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCR=$(basename "${BASH_SOURCE[0]}")
THIS_SCRIPT=$THISDIR/$SCR

######################################################
## log()
##
##   parameter 1 - text to log
##
##   1. write parameter #1 to current logfile
##
######################################################
function log ()
{
    if [[ -e $LOG_DIR ]]; then
        echo "$(date +%Y/%m/%d_%H:%M:%S.%N) $1" >> $LOG_FILE
    fi
}

######################################################
## fatalError()
##
##   parameter 1 - text to log
##
##   1.  log a fatal error and exit
##
######################################################
function fatalError ()
{
    MSG=$1
    log "FATAL: $MSG"
    echo "ERROR: $MSG"
    exit -1
}

function installRPMs()
{
    INSTALL_RPM_LOG=$LOG_DIR/yum.${g_prog}_install.log.$$

    STR=""
   # STR="$STR java-1.8.0-openjdk.x86_64i docker-engine-selinux-1.12.6-1.el7.centos docker-engine-1.12.6-1.el7.centos"
    STR="$STR java-1.8.0-openjdk.x86_64i docker-ce-17.03.0.ce-1.el7.centos"
 
    unset DOCKER_HOST DOCKER_TLS_VERIFY
    yum -y remove docker docker-ce container-selinux docker-rhel-push-plugin docker-common docker-engine-selinux docker-engine yum-utils

    yum install -y yum-utils

    yum-config-manager \
       --add-repo \
       https://download.docker.com/linux/centos/docker-ce.repo

    yum makecache fast
    
    yum list docker-ce  --showduplicates |sort -r > $INSTALL_RPM_LOG

    echo "installRPMs(): to see progress tail $INSTALL_RPM_LOG"
    
    yum -y install $STR > $INSTALL_RPM_LOG

    #if ! yum -y install $STR > $INSTALL_RPM_LOG
    #then
    #    fatalError "installRPMs(): failed; see $INSTALL_RPM_LOG"
    #fi
    systemctl start docker > $INSTALL_RPM_LOG
    systemctl enable docker > $INSTALL_RPM_LOG


}

##############################################################
# Open Zookeeper / Kafka Server Ports
##############################################################
function openZkKafkaPorts()
{
    log "$g_prog.installZookeeper: Opening firewalls ports"    
    systemctl status firewalld  >> $LOG_FILE
    firewall-cmd --get-active-zones  >> $LOG_FILE
    firewall-cmd --zone=public --list-ports  >> $LOG_FILE
 
    firewall-cmd --zone=public --add-port=${ccport}/tcp --permanent
    firewall-cmd --zone=public --add-port=${connectport}/tcp --permanent
    firewall-cmd --zone=public --add-port=${restport}/tcp --permanent
    firewall-cmd --zone=public --add-port=${schemaport}/tcp --permanent
 
    firewall-cmd --reload  >> $LOG_FILE
    firewall-cmd --zone=public --list-ports  >> $LOG_FILE

}

##############################################################
# Install Schema Server
##############################################################
function installSchemaServer()
{
    log "$g_prog.installSchemaServer: Install Schema - instance ${SERVER_INSTANCE}"

    IPADDR=`cat $INI_FILE | grep srSer${SERVER_INSTANCE}`
    schemaserver=`echo ${IPADDR} | awk -F "=" '{print $2}'`
#
    docker run -d --net=host \
       --name=schema-registry-${SERVER_INSTANCE} \
       -e SCHEMA_REGISTRY_KAFKASTORE_CONNECTION_URL=${zkServers} \
       -e SCHEMA_REGISTRY_BOOTSTRAP_SERVERS=${kfServers} \
       -e SCHEMA_REGISTRY_HOST_NAME=${schemaserver} \
       -e SCHEMA_REGISTRY_LISTENERS=http://${schemaserver}:${schemaport} \
       confluentinc/cp-schema-registry:${confversion}
#
#        -e SCHEMA_REGISTRY_KAFKASTORE_CONNECTION_URL=${zkSer1}:${zkpclient},${zkSer2}:${zkpclient},${zkSer3}:${zkpclient} \
#       -e SCHEMA_REGISTRY_BOOTSTRAP_SERVERS=${kfSer1}:${kafkapclient},${kfSer2}:${kafkapclient},${kfSer3}:${kafkapclient} \

#
    RC=$?
    if [ ${RC} -ne 0 ]; then
        fatalError "$g_prog.run(): Error implementing SchemaRegistry instance - check configuration parameters"
    fi

}

##############################################################
# Install REST server
##############################################################
function installRestServer()
{
    log "$g_prog.installRestServer: Install Rest - instance ${SERVER_INSTANCE}"

    IPADDR=`cat $INI_FILE | grep srSer${SERVER_INSTANCE}`
    schemaserver=`echo ${IPADDR} | awk -F "=" '{print $2}'`
#
# REST instance will point to schema-registry on another server ...
#    *---------------*-----------------*----------------*
#    * REST on Ser1>>* Schema on Ser2  *                *
#    *---------------*-----------------*----------------*
#    *               * REST on Ser2 >> * Schema on Ser3 *
#    *---------------*-----------------*----------------*
#
    SCHEMA_REG_SER=""
    if [ ${SERVER_INSTANCE} -eq 1 ]; then
        SCHEMA_REG_SER=${srSer2}
    elif [ ${SERVER_INSTANCE} -eq 2 ]; then
        SCHEMA_REG_SER=${srSer3}
    else
        fatalError "$g_prog.InstallRestServer: Currently ${SERVER_INSTANCE} is an invalid option to install REST server"
    fi
    if [ -z ${SCHEMA_REG_SER} ]; then
        fatalError "$g_prog.InstallRestServer: SCHEMA_REG_SER is not set to a valid value"
    fi
#
    docker run -d \
        --net=host \
        --name=kafka-rest-${SERVER_INSTANCE} \
        -e KAFKA_REST_ZOOKEEPER_CONNECT=${zkServers} \
        -e KAFKA_REST_LISTENERS=http://${schemaserver}:${restport} \
        -e KAFKA_REST_SCHEMA_REGISTRY_URL=http://${SCHEMA_REG_SER}:${schemaport} \
        -e KAFKA_REST_HOST_NAME=${schemaserver} \
        confluentinc/cp-kafka-rest:${confversion}
#   -e KAFKA_REST_ZOOKEEPER_CONNECT=${zkSer1}:${zkpclient},${zkSer2}:${zkpclient},${zkSer3}:${zkpclient} \
    RC=$?
    if [ ${RC} -ne 0 ]; then
        fatalError "$g_prog.run(): Error implementing SchemaRegistry instance - check configuration parameters"
    fi

}

##############################################################
# Install Connection server
##############################################################
function installConnectionServer()
{
    log "$g_prog.installConnectionServer: Install Connection - instance ${SERVER_INSTANCE}"

    IPADDR=`cat $INI_FILE | grep srSer${SERVER_INSTANCE}`
    schemaserver=`echo ${IPADDR} | awk -F "=" '{print $2}'`
#
    docker run -d \
       --net=host \
       --name=kafka-connect-${SERVER_INSTANCE} \
       -e CONNECT_BOOTSTRAP_SERVERS=${kfServers} \
       -e CONNECT_REST_PORT=${connectport} \
       -e CONNECT_GROUP_ID="quickstart" \
       -e CONNECT_CONFIG_STORAGE_TOPIC="quickstart-config" \
       -e CONNECT_OFFSET_STORAGE_TOPIC="quickstart-offsets" \
       -e CONNECT_STATUS_STORAGE_TOPIC="quickstart-status" \
       -e CONNECT_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
       -e CONNECT_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
       -e CONNECT_INTERNAL_KEY_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
       -e CONNECT_INTERNAL_VALUE_CONVERTER="org.apache.kafka.connect.json.JsonConverter" \
       -e CONNECT_REST_ADVERTISED_HOST_NAME=${schemaserver} \
       confluentinc/cp-kafka-connect:${confversion}
# -e CONNECT_BOOTSTRAP_SERVERS=${kfSer1}:${kafkapclient},${kfSer2}:${kafkapclient},${kfSer3}:${kafkapclient} \
    RC=$?
    if [ ${RC} -ne 0 ]; then
        fatalError "$g_prog.run(): Error implementing SchemaRegistry instance - check configuration parameters"
    fi

}

##############################################################
# Install Control Centre Server
##############################################################
function installControlCentreServer()
{
    log "$g_prog.installControlCentreServer: Install Control Centre - instance ${SERVER_INSTANCE}"

    IPADDR=`cat $INI_FILE | grep srSer${SERVER_INSTANCE}`
    schemaserver=`echo ${IPADDR} | awk -F "=" '{print $2}'`
#
    mkdir -p /tmp/control-center/data
    RC=$?
    if [ ${RC} -ne 0 ]; then
        fatalError "$g_prog.run(): Error creating folder /tmp/control-center/data"
    fi
#
    docker run -d \
       --net=host \
       --name=control-center-${SERVER_INSTANCE} \
       --ulimit nofile=${nofile}:${nofile} \
       -p ${ccport}:${ccport} \
       -v /tmp/control-center/data:/var/lib/confluent-control-center \
       -e CONTROL_CENTER_ZOOKEEPER_CONNECT=${zkServers} \
       -e CONTROL_CENTER_BOOTSTRAP_SERVERS=${kfServers} \
       -e CONTROL_CENTER_REPLICATION_FACTOR=${repfactor} \
       -e CONTROL_CENTER_MONITORING_INTERCEPTOR_TOPIC_PARTITIONS=${montopicpart} \
       -e CONTROL_CENTER_INTERNAL_TOPICS_PARTITIONS=${inttopicpart} \
       -e CONTROL_CENTER_STREAMS_NUM_STREAM_THREADS=${streamthread} \
       -e CONTROL_CENTER_CONNECT_CLUSTER=${schemaserver}:${connectport} \
       confluentinc/cp-enterprise-control-center:${confversion}
#
#       -e CONTROL_CENTER_ZOOKEEPER_CONNECT=${zkSer1}:${zkpclient},${zkSer2}:${zkpclient},${zkSer1}:${zkpclient} \
#       -e CONTROL_CENTER_BOOTSTRAP_SERVERS=${kfSer1}:${kafkapclient},${kfSer2}:${kafkapclient},${kfSer3}:${kafkapclient} \
#
    RC=$?
    if [ ${RC} -ne 0 ]; then
        fatalError "$g_prog.run(): Error implementing Control Centre instance - check configuration parameters"
    fi

}


##############################################################
# Install components
##############################################################
function installServer()
{
   # installZookeeper 
   # installKafka
   ## installSchemaServer
   ## installRestServer
   #  installConnectionServer
   # installControlCentreServer
   
   for i in `echo ${INSTALL_OPTIONS} | sed "s/,/ /g"`
   do
       case "${i}" in
         schema)
           installSchemaServer
           ;;
         rest)
           installRestServer
           ;;
         connect)
           installConnectionServer
           ;;
         control)
           installControlCentreServer
           ;;
         *)
           fatalError "$g_prog.run(): Invalid Install Option"
           ;;
       esac

   done


}


function run()
{
    eval `grep platformEnvironment $INI_FILE`
    if [ -z $platformEnvironment ]; then    
        fatalError "$g_prog.run(): Unknown environment, check platformEnvironment setting in iniFile"
    elif [ $platformEnvironment != "AZURE" ]; then    
        fatalError "$g_prog.run(): platformEnvironment=AZURE is the only valid setting currently"
    fi
#
    eval `grep zkSer1 ${INI_FILE}`
    eval `grep zkSer2 ${INI_FILE}`
    eval `grep zkSer3 ${INI_FILE}`
    eval `grep kfSer1 ${INI_FILE}`
    eval `grep kfSer2 ${INI_FILE}`
    eval `grep kfSer3 ${INI_FILE}`
#
    eval `grep srSer1 ${INI_FILE}`
    eval `grep srSer2 ${INI_FILE}`
    eval `grep srSer3 ${INI_FILE}`
#
    eval `grep zkNoSer ${INI_FILE}`
    eval `grep kfNoSer ${INI_FILE}`
#
    eval `grep zkpclient ${INI_FILE}`
#
    eval `grep zkpserverlow ${INI_FILE}`
    eval `grep zkpserverhigh ${INI_FILE}`
#
    eval `grep kafkapclient ${INI_FILE}`
#
    eval `grep schemaport ${INI_FILE}`
    eval `grep restport ${INI_FILE}`
    eval `grep connectport ${INI_FILE}`
#
    eval `grep ccport ${INI_FILE}`
    eval `grep nofile ${INI_FILE}`
    eval `grep repfactor ${INI_FILE}`
    eval `grep montopicpart ${INI_FILE}`
    eval `grep inttopicpart ${INI_FILE}`
    eval `grep streamthread ${INI_FILE}`
#
    eval `grep confversion ${INI_FILE}`
#
    count=1
    zkServers=""
######################################################
# String the Zookeeper servers together
#######################################################
    while [ ${count} -le ${zkNoSer} ]
    do
        zkSerIP=`cat $INI_FILE | grep zkSer${count}`
        retip=`echo ${zkSerIP} | awk -F "=" '{print $2}'`
        if [ ${count} -gt 1 ]; then
             zkServers="${zkServers},"
        fi
        zkServers="${zkServers}${retip}:${zkpclient}"
        count=$[$count+1]
    done
#
    count=1
    kfServers=""
######################################################
# String the Kafka servers together
#######################################################
    while [ ${count} -le ${kfNoSer} ]
    do
        kfSerIP=`cat $INI_FILE | grep kfSer${count}`
        retip=`echo ${kfSerIP} | awk -F "=" '{print $2}'`
        if [ ${count} -gt 1 ]; then
             kfServers="${kfServers},"
        fi
        kfServers="${kfServers}${retip}:${kafkapclient}"
        count=$[$count+1]
    done
#
  # function calls
    installRPMs
    openZkKafkaPorts
    installServer
}


######################################################
## Main Entry Point
######################################################

log "$g_prog starting"
log "STAGE_DIR=$STAGE_DIR"
log "LOG_DIR=$LOG_DIR"
log "INI_FILE=$INI_FILE"
log "LOG_FILE=$LOG_FILE"
echo "$g_prog starting, LOG_FILE=$LOG_FILE"

if [[ $EUID -ne 0 ]]; then
    fatalError "$THIS_SCRIPT must be run as root"
    exit 1
fi

INI_FILE_PATH=$1
SERVER_INSTANCE=${2}

# comma separated string: connect,rest,schema - will install in that order
INSTALL_OPTIONS=${3}
#
if [[ -z $INI_FILE_PATH ]]; then
    fatalError "${g_prog} called with null parameter, should be the path to the driving ini_file"
fi

if [[ ! -f $INI_FILE_PATH ]]; then
    fatalError "${g_prog} ini_file cannot be found"
fi

if ! mkdir -p $LOG_DIR; then
    fatalError "${g_prog} cant make $LOG_DIR"
fi
#
if [[ -z ${SERVER_INSTANCE} ]]; then
    fatalError "${g_prog} invalid arguments - SERVER_INSTANCE is missing"
fi
#
if [[ -z ${INSTALL_OPTIONS} ]]; then
    fatalError "${g_prog} invalid arguments - INSTALL_OPTIONS is missing"
fi
   for i in `echo ${INSTALL_OPTIONS} | sed "s/,/ /g"`
   do
       case "${i}" in
         schema)
           log "$g_prog: Schema will be installed"
           ;;
         rest)
           log "$g_prog: REST will be installed"
           ;;
         connect)
           log "$g_prog: Connect will be installed"
           ;;
         control)
           log "$g_prog: ControlCentre will be installed"
           ;;
         *)
           fatalError "$g_prog.run(): Invalid Install Options - valid options are:schema,rest,connect,control"
           ;;
       esac

   done
#
chmod 777 $LOG_DIR

cp $INI_FILE_PATH $INI_FILE

run

log "$g_prog ended cleanly"
exit $RETVAL

