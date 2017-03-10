#!/bin/bash
#########################################################################################
## Zookeeper Server installations
#########################################################################################
# This scrip installs zookeeper (Confluent) on Linux
#
# USAGE:
#
#    sudo zookeeper-server.sh ~/kafka-server.ini instance
#
# USEFUL LINKS: 
# 
#
#########################################################################################

g_prog=standalone-zookeeper-server
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
function openZookeeperPorts()
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
# Create Zookeeper properties file
##############################################################
function createZookeeperPropertiesFile()
{
    ZOOKEEPER_PROP_FILE="/etc/kafka/zookeeper.properties"
    log "$g_prog.ZookeeperPropertiesFile: Creating Zookeeper properties file ${ZOOKEEPER_PROP_FILE}"

    rm ${ZOOKEEPER_PROP_FILE}
    cat > ${ZOOKEEPER_PROP_FILE} << EOFPROP1
dataDir=/var/lib/zookeeper/
dataLogDir=/var/lib/zookeeper/log
clientPort=${zkpclient}
maxClientCnXns=0
initLimit=5
syncLimit=2
tickTime=2000
EOFPROP1
######################################################
#
######################################################
    count=1
    while [ ${count} -le ${zkNoSer} ]
    do
        zkSerIP=`cat $INI_FILE | grep zkSer${count}`
        retip=`echo ${zkSerIP} | awk -F "=" '{print $2}'`
        echo "server.${count}=${retip}:${zkpserverlow}:${zkpserverhigh}" >>  ${ZOOKEEPER_PROP_FILE}
        count=$[$count+1]
    done
#
#server.1=${zkSer1}:${zkpserverlow}:${zkpserverhigh}
#server.2=${zkSer2}:${zkpserverlow}:${zkpserverhigh}
#server.3=${zkSer3}:${zkpserverlow}:${zkpserverhigh}

    mkdir -p /var/lib/zookeeper/
    echo "${ZOOID}" > /var/lib/zookeeper/myid
}

##############################################################
# start Zookeeper         
##############################################################
function startZookeeper()
{
    log "$g_prog.InstallZookeeper: Starting Zookeeper as a background server"
    running=`ps -ef | grep zookeeper.properties | wc -l`
    if [ ${running} -gt 1 ]; then
        fatalError "$g_prog.run(): Zookeeper is already running as a background process."
    fi
    nohup sh /bin/zookeeper-server-start /etc/kafka/zookeeper.properties >>  /var/log/standalone-zookeeper-server/zookeeper.log.$(date +%Y%m%d_%H%M%S_%N) &
    RC=$?
    if [ ${RC} -ne 0 ]; then
        fatalError "$g_prog.run(): Error starting Zookeeper - check configuration parameters"
    fi
}

##############################################################
# Install Components
##############################################################
function startServer()
{
       openZookeeperPorts
       createZookeeperPropertiesFile
       startZookeeper
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
#
    eval `grep zkNoSer ${INI_FILE}`
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
  # Functions
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
ZOOID=${2}
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

if [[ -z ${ZOOID} ]]; then
    fatalError "${g_prog} Invalid parameters - Zookeeper ID is missing"
fi

chmod 777 $LOG_DIR

cp $INI_FILE_PATH $INI_FILE

run

log "$g_prog ended cleanly"
exit $RETVAL

