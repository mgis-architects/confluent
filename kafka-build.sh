#!/bin/bash
#########################################################################################
## Kafka installations
#########################################################################################
# This script only supports Azure currently, mainly due to the disk persistence method
#
# USAGE:
#
#    sudo kafka-build.sh ~/kafka-build.ini instance
#
# USEFUL LINKS: 
# 
#
#########################################################################################

g_prog=kafka-build
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
    firewall-cmd --zone=public --add-port=${zkpserverlow}/tcp --permanent  >> $LOG_FILE  
    firewall-cmd --zone=public --add-port=${zkpserverhigh}/tcp --permanent  >> $LOG_FILE
    firewall-cmd --zone=public --add-port=${zkpclient}/tcp --permanent  >> $LOG_FILE
    firewall-cmd --zone=public --add-port=${kafkapclient}/tcp --permanent  >> $LOG_FILE
    
    firewall-cmd --reload  >> $LOG_FILE
    firewall-cmd --zone=public --list-ports  >> $LOG_FILE

}

##############################################################
# Install Zookeeper 
##############################################################
function installZookeeper()
{

    log "$g_prog.installZookeeper: Install ZooKeeper - instance ${SERVER_INSTANCE}"
    docker run -d \
        --net=host \
        --name=zk-${SERVER_INSTANCE} \
        -e ZOOKEEPER_SERVER_ID=${SERVER_INSTANCE} \
        -e ZOOKEEPER_CLIENT_PORT=${zkpclient} \
        -e ZOOKEEPER_TICK_TIME=2000 \
        -e ZOOKEEPER_INIT_LIMIT=5 \
        -e ZOOKEEPER_SYNC_LIMIT=2 \
        -e ZOOKEEPER_SERVERS="${zkKafkaSer1}:${zkpserverlow}:${zkpserverhigh};${zkKafkaSer2}:${zkpserverlow}:${zkpserverhigh};${zkKafkaSer3}:${zkpserverlow}:${zkpserverhigh}" \
         confluentinc/cp-zookeeper:${confversion}
#
    RC=$?
    if [ ${RC} -ne 0 ]; then
        fatalError "$g_prog.run(): Error implementing ZooKeeper - check configuration parameters"
    fi
}

##############################################################
# Install Kafka          
##############################################################
function installKafka()
{

    log "$g_prog.installZookeeper: Install Kafka - instance ${SERVER_INSTANCE}"
   
    IPADDR=`cat $INI_FILE | grep zkKafkaSer${SERVER_INSTANCE}`
    kafkaserver=`echo ${IPADDR} | awk -F "=" '{print $2}'`

    docker run -d \
        --net=host \
        --name=kafka-${SERVER_INSTANCE} \
        -e KAFKA_ZOOKEEPER_CONNECT=${zkKafkaSer1}:${zkpclient},${zkKafkaSer2}:${zkpclient},${zkKafkaSer3}:${zkpclient} \
        -e KAFKA_ADVERTISED_LISTENERS=PLAINTEXT://${kafkaserver}:${kafkapclient} \
        confluentinc/cp-kafka:${confversion}

    RC=$?
    if [ ${RC} -ne 0 ]; then
        fatalError "$g_prog.run(): Error implementing Kafka - check configuration parameters"
    fi

}

##############################################################
# Install components
##############################################################
function installServer()
{
    installZookeeper 
    installKafka
}


function run()
{
    eval `grep platformEnvironment $INI_FILE`
    if [ -z $platformEnvironment ]; then    
        fatalError "$g_prog.run(): Unknown environment, check platformEnvironment setting in iniFile"
    elif [ $platformEnvironment != "AZURE" ]; then    
        fatalError "$g_prog.run(): platformEnvironment=AZURE is the only valid setting currently"
    fi

    eval `grep zkKafkaSer1 ${INI_FILE}`
    eval `grep zkKafkaSer2 ${INI_FILE}`
    eval `grep zkKafkaSer3 ${INI_FILE}`
#
    eval `grep zkpclient ${INI_FILE}`
    eval `grep zkpserverlow ${INI_FILE}`
    eval `grep zkpserverhigh ${INI_FILE}`
    eval `grep kafkapclient ${INI_FILE}`
#
    eval `grep confversion ${INI_FILE}`
    if [ -z ${confversion} ]; then
        fatalError "$g_prog.run(): Unknown parameter, check confversion parameter in iniFile"
    fi
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

