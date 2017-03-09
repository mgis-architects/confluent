#!/bin/bash
#########################################################################################
## Kafka Server installations
#########################################################################################
# This scrip installs kafka (Confluent) on Linux
#
# USAGE:
#
#    sudo standalone-kafka-server.sh ~/standalone-server-build.ini instance
#
# USEFUL LINKS: 
# 
#
#########################################################################################

g_prog=standalone-kafka-server
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
    STR="$STR java-1.8.0-openjdk"
   # STR="$STR java-1.8.0-openjdk.x86_64i docker-ce-17.03.0.ce-1.el7.centos"
    
    yum -y install yum-utils
    
    rpm --import http://packages.confluent.io/rpm/3.2/archive.key

    yum -y install ${STR} >> ${INSTALL_RPM_LOG}
    
    cat > /etc/yum.repos.d/confluent.repo << EOF1 
[Confluent.dist]
name=Confluent repository (dist)
baseurl=http://packages.confluent.io/rpm/3.2/7
gpgcheck=1
gpgkey=http://packages.confluent.io/rpm/3.2/archive.key
enabled=1

[Confluent]
name=Confluent repository
baseurl=http://packages.confluent.io/rpm/3.2
gpgcheck=1
gpgkey=http://packages.confluent.io/rpm/3.2/archive.key
enabled=1
EOF1

    log "$g_prog.installRPMs: Installing confluent-plaform-2.11"
    yum -y install confluent-platform-2.11      
}

##############################################################
# Open Zookeeper ports
##############################################################
function openKafkaPorts()
{
    log "$g_prog.openKafkaPorts: Opening firewalls ports"    
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
# Create Kafka Properties file
##############################################################
function createKafkaPropertiesFile()
{
    KAFKA_PROP_FILE="/etc/kafka/server.properties"
    log "$g_prog.KafkaPropertiesFile: Creating Kafka Properties file ${KAFKA_PROP_FILE}"
#
    IPADDR=`cat $INI_FILE | grep kfSer${BROKERID}`
    brokerser=`echo ${IPADDR} | awk -F "=" '{print $2}'`
#
    rm ${KAFKA_PROP_FILE}
    cat > ${KAFKA_PROP_FILE} << EOFPROP1
broker.id=${BROKERID}
#delete.topic.enable=true
listeners=PLAINTEXT://${brokerser}:${kafkapclient}
#advertised.listeners=PLAINTEXT://your.host.name:9092
#listener.security.protocol.map=PLAINTEXT:PLAINTEXT,SSL:SSL,SASL_PLAINTEXT:SASL_PLAINTEXT,SASL_SSL:SASL_SSL
num.network.threads=3
num.io.threads=8
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400
socket.request.max.bytes=104857600
log.dirs=/var/lib/kafka
num.partitions=1
num.recovery.threads.per.data.dir=1
#log.flush.interval.messages=10000
#log.flush.interval.ms=1000
log.retention.hours=168
#log.retention.bytes=1073741824
log.segment.bytes=1073741824
log.retention.check.interval.ms=300000
zookeeper.connect=${zkServers}
#zookeeper.connect=${zkSer1}:${zkpclient},${zkSer2}:${zkpclient},${zkSer3}:${zkpclient}
zookeeper.connection.timeout.ms=6000
#metric.reporters=io.confluent.metrics.reporter.ConfluentMetricsReporter
#confluent.metrics.reporter.bootstrap.servers=localhost:9092
#confluent.metrics.reporter.zookeeper.connect=localhost:2181
#confluent.metrics.reporter.topic.replicas=1
confluent.support.metrics.enable=true
confluent.support.customer.id=anonymous
EOFPROP1

}
##############################################################
# Start kafka server
##############################################################
function startKafka()
{
    log "$g_prog.InstallKafka: Starting Kafka as a background server"
    running=`ps -ef | grep server.properties | wc -l`
    if [ ${running} -gt 1 ]; then
        fatalError "$g_prog.run(): Kafka is already running as a back-ground process."
    fi
    nohup sh /bin/kafka-server-start /etc/kafka/server.properties  >>  /var/log/standalone-kafka-server/kafkabroker.log.$(date +%Y%m%d_%H%M%S_%N) &
    RC=$?
    if [ ${RC} -ne 0 ]; then
        fatalError "$g_prog.run(): Error implementing Kafka - check configuration parameters"
    fi
}

##############################################################
# Install Components
##############################################################
function startServer()
{
       openKafkaPorts
       createKafkaPropertiesFile
       startKafka
}

function run()
{
    echo "running ..."
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
#
    eval `grep kfSer1 ${INI_FILE}`
    eval `grep kfSer2 ${INI_FILE}`
    eval `grep kfSer3 ${INI_FILE}`
#
    eval `grep zkNoSer ${INI_FILE}`
    eval `grep kfNoSer ${INI_FILE}`
#
    eval `grep zkpclient ${INI_FILE}`
    eval `grep zkpserverlow ${INI_FILE}`
    eval `grep zkpserverhigh ${INI_FILE}`
    eval `grep kafkapclient ${INI_FILE}`
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
    startServer
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
BROKERID=${2}
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

if [ -z BROKERID ]; then
    fatalError "${g_prog} invalid arguments - missing brokerid" 
fi

chmod 777 $LOG_DIR

cp $INI_FILE_PATH $INI_FILE

run

log "$g_prog ended cleanly"
exit $RETVAL

