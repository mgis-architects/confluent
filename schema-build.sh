#!/bin/bash
#########################################################################################
## Schema / REST installations
#########################################################################################
# This script only supports Azure currently, mainly due to the disk persistence method
#
# USAGE:
#
#    sudo schema-build.sh ~/kafka-build.ini instance
#
# USEFUL LINKS: 
# 
#
#########################################################################################

g_prog=schema-build
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
# Open Schema / REST / Connect Ports
##############################################################
function openSchemaPorts()
{
    log "$g_prog.openSchemaPorts: Opening firewalls ports"    
    systemctl status firewalld  >> $LOG_FILE
    firewall-cmd --get-active-zones  >> $LOG_FILE
    firewall-cmd --zone=public --list-ports  >> $LOG_FILE
    firewall-cmd --zone=public --add-port=${restport}/tcp --permanent  >> $LOG_FILE  
    firewall-cmd --zone=public --add-port=${connectport}/tcp --permanent  >> $LOG_FILE

    firewall-cmd --reload  >> $LOG_FILE
    firewall-cmd --zone=public --list-ports  >> $LOG_FILE

}

##############################################################
# Install Schema-Registry
##############################################################
function installSchemaRegistry()
{

    log "$g_prog.installSchemaRegistry: Install Schema-Registry - instance ${SERVER_INSTANCE}"
# 
    IPADDR=`cat $INI_FILE | grep srSer${SERVER_INSTANCE}`
    schemaserver=`echo ${IPADDR} | awk -F "=" '{print $2}'`
#
    docker run -d --net=host --name=schema-registry-${SERVER_INSTANCE} \
       -e SCHEMA_REGISTRY_KAFKASTORE_CONNECTION_URL=${zkKafkaSer1}:${zkpclient},${zkKafkaSer2}:${zkpclient},${zkKafkaSer3}:${zkpclient} \
       -e SCHEMA_REGISTRY_HOST_NAME=${schemaserver} \
       -e SCHEMA_REGISTRY_LISTENERS=http://${schemaserver}:${schemaport} \
       confluentinc/cp-schema-registry:${confversion}
#
    RC=$?
    if [ ${RC} -ne 0 ]; then
        fatalError "$g_prog.run(): Error implementing SchemaRegistry instance - check configuration parameters"
    fi
}

##############################################################
# Install REST server
##############################################################
function installREST()
{

    log "$g_prog.installREST: Install REST - instance ${SERVER_INSTANCE}"
#   
    IPADDR=`cat $INI_FILE | grep srSer${SERVER_INSTANCE}`
    schemaserver=`echo ${IPADDR} | awk -F "=" '{print $2}'`
# 
    docker run -d \
        --net=host \
        --name=kafka-rest-${SERVER_INSTANCE} \
        -e KAFKA_REST_ZOOKEEPER_CONNECT=${zkKafkaSer1}:${zkpclient},${zkKafkaSer2}:${zkpclient},${zkKafkaSer3}:${zkpclient} \
        -e KAFKA_REST_LISTENERS=http://${schemaserver}:${restport} \
        -e KAFKA_REST_SCHEMA_REGISTRY_URL=http://${schemaserver}:${schemaport} \
        -e KAFKA_REST_HOST_NAME=${schemaserver} \
        confluentinc/cp-kafka-rest:${confversion}
#
    RC=$?
    if [ ${RC} -ne 0 ]; then
        fatalError "$g_prog.run(): Error implementing REST instance - check configuration parameters"
    fi

}

##############################################################
# Install Connect server
##############################################################
function installConnect()
{

    log "$g_prog.installConnect: Install Connect - instance ${SERVER_INSTANCE}"
#
    IPADDR=`cat $INI_FILE | grep srSer${SERVER_INSTANCE}`
    schemaserver=`echo ${IPADDR} | awk -F "=" '{print $2}'`
#
    docker run -d \
       --net=host \
       --name=kafka-connect-${SERVER_INSTANCE} \
       -e CONNECT_BOOTSTRAP_SERVERS=${zkKafkaSer1}:${kafkapclient},${zkKafkaSer2}:${kafkapclient},${zkKafkaSer3}:${kafkapclient} \
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
#
    RC=$?
    if [ ${RC} -ne 0 ]; then
        fatalError "$g_prog.run(): Error implementing Connect instance - check configuration parameters"
    fi

}

##############################################################
# Install components
##############################################################
function installServer()
{
     installSchemaRegistry
     installREST
     installConnect
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
    eval `grep zkKafkaSer1 ${INI_FILE}`
    eval `grep zkKafkaSer2 ${INI_FILE}`
    eval `grep zkKafkaSer3 ${INI_FILE}`
#
    eval `grep zkpclient ${INI_FILE}`
    eval `grep zkpserverlow ${INI_FILE}`
    eval `grep zkpserverhigh ${INI_FILE}`
    eval `grep kafkapclient ${INI_FILE}`
#
    eval `grep schemaport ${INI_FILE}`
    eval `grep restport ${INI_FILE}`
    eval `grep connectport ${INI_FILE}`
#
    eval `grep confversion ${INI_FILE}`
    if [ -z ${confversion} ]; then
        fatalError "$g_prog.run(): Unknown parameter, check confversion parameter in iniFile"
    fi
#
  # function calls
    installRPMs
    openSchemaPorts
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

if [[ -z $INI_FILE_PATH ]]; then
    fatalError "${g_prog} called with null parameter, should be the path to the driving ini_file"
fi

if [[ -z $SERVER_INSTANCE ]]; then
    fatalError "${g_prog} called with null parameter, missing server-instance"
fi


if [[ ! -f $INI_FILE_PATH ]]; then
    fatalError "${g_prog} ini_file cannot be found"
fi

if ! mkdir -p $LOG_DIR; then
    fatalError "${g_prog} cant make $LOG_DIR"
fi


chmod 777 $LOG_DIR

cp $INI_FILE_PATH $INI_FILE

run ${SERVER_INSTANCE}

log "$g_prog ended cleanly"
exit $RETVAL

