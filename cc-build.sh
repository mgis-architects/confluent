#!/bin/bash
#########################################################################################
## Control Center installations
#########################################################################################
# This script only supports Azure currently, mainly due to the disk persistence method
#
# USAGE:
#
#    sudo cc-build.sh ~/kafka-build.ini instance
#
# USEFUL LINKS: 
# 
#
#########################################################################################

g_prog=cc-build
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
    STR="$STR java-1.8.0-openjdk.x86_64i docker-engine-selinux-1.12.6-1.el7.centos docker-engine-1.12.6-1.el7.centos"
    
    unset DOCKER_HOST DOCKER_TLS_VERIFY
    yum -y remove docker container-selinux docker-rhel-push-plugin docker-common docker-engine-selinux docker-engine yum-utils

    yum install -y yum-utils

    yum-config-manager \
       --add-repo \
       https://docs.docker.com/engine/installation/linux/repo_files/centos/docker.repo

    yum makecache fast
    
    yum list docker-engine.x86_64  --showduplicates |sort -r > $INSTALL_RPM_LOG
    yum list docker-engine.selinux-1.12.6-1.el7.centos  --showduplicates |sort -r > $INSTALL_RPM_LOG

    echo "installRPMs(): to see progress tail $INSTALL_RPM_LOG"
    
    yum -y install $STR > $INSTALL_RPM_LOG

    #if ! yum -y install $STR > $INSTALL_RPM_LOG
    #then
    #    fatalError "installRPMs(): failed; see $INSTALL_RPM_LOG"
    #fi
    systemctl start docker > $INSTALL_RPM_LOG
    systemctl enable docker > $INSTALL_RPM_LOG


}


function oracleProfile() 
{
    cat >> /home/oracle/.bash_profile << EOForacleProfile
    export JAVA_HOME=/usr/lib/jvm
    export LD_LIBRARY_PATH=$JAVA_HOME/jre/lib/amd64/server:$LD_LIBRARY_PATH
    export PATH=$PATH:/u01/app/oracle/product/12.3.0/ogg4bd
EOForacleProfile
}

function mountMedia() {

    if [ -f /mnt/software/ogg4bd12301/V839824-01.zip ]; then
    
        log "mountMedia(): Filesystem already mounted"
        
    else
    
        umount /mnt/software
    
        mkdir -p /mnt/software
        
        eval `grep mediaStorageAccountKey $INI_FILE`
        eval `grep mediaStorageAccount $INI_FILE`
        eval `grep mediaStorageAccountURL $INI_FILE`

        l_str=""
        if [ -z $mediaStorageAccountKey ]; then
            l_str=$l_str || "mediaStorageAccountKey not found in $INI_FILE; "
        fi
        if [ -z $mediaStorageAccount ]; then
            l_str=$l_str || "mediaStorageAccount not found in $INI_FILE; "
        fi
        if [ -z $mediaStorageAccountURL ]; then
            l_str=$l_str || "mediaStorageAccountURL not found in $INI_FILE; "
        fi
        if ! [ -z $l_str ]; then
            fatalError "mountMedia(): $l_str"
        fi

        cat > /etc/cifspw << EOF1
username=${mediaStorageAccount}
password=${mediaStorageAccountKey}
EOF1

        cat >> /etc/fstab << EOF2
//${mediaStorageAccountURL}     /mnt/software   cifs    credentials=/etc/cifspw,vers=3.0,gid=54321      0       0
EOF2

        mount -a
        
        if [ ! -f /mnt/software/ogg4bd12301/V839824-01.zip ]; then
            fatalError "installGridHome(): media missing /mnt/software/ogg4bd12301/V839824-01.zip"
        fi

    fi
    
}

installOgg4bd()
{
    local l_installdir=/u01/app/oracle/product/12.3.0/ogg4bd
    local l_media=/mnt/software/ogg4bd12301/V839824-01.zip
    local l_tmp_script=$LOG_DIR/$g_prog.installOgg4bd.$$.sh

    if [ ! -f ${l_media} ]; then
        fatalError "installGridHome(): media missing ${l_media}"
    fi

    cat > $l_tmp_script << EOFogg4bd

    mkdir -p ${l_installdir}
    
    cd ${l_installdir}
    
    unzip ${l_media}
    
    tar -xf ggs_Adapters_Linux_x64.tar
    
    rm -f ggs_Adapters_Linux_x64.tar
    
    ./ggsci  << EOFggsci1
       CREATE SUBDIRS 
EOFggsci1

    echo "PORT 7801" > ${l_installdir}/dirprm/mgr.prm
    
    ./ggsci  << EOFggsci2
        START MGR 
EOFggsci2

    sleep 3
    
    ./ggsci  << EOFggsci2
        INFO MGR 
EOFggsci2

EOFogg4bd

    su - oracle -c "bash -x $l_tmp_script" |tee ${l_oracleinstall_log}

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
    firewall-cmd --zone=public --add-port=${ccport}/tcp --permanent  >> $LOG_FILE  

    firewall-cmd --reload  >> $LOG_FILE
    firewall-cmd --zone=public --list-ports  >> $LOG_FILE

}

##############################################################
# Install Control Center
##############################################################
function installControlCenter()
{

    log "$g_prog.installControlCenter: Install Control Center  - instance ${SERVER_INSTANCE}"
    # echo "retcode={$?}"
    # echo "server-name=mmo275confluentvm${ID}"
    # echo "SERVER_INSTANCE=${SERVER_INSTANCE}"
    # echo "ip=${zkKafkaSer1}"
    # echo "ip=${zkKafkaSer2}"
    # echo "ip=${zkKafkaSer3}"
    # echo "zkpclient=${zkpclient}"
    # echo "low=${zkpserverlow}"
    # echo "high=${zkpserverhigh}"
 
    eval `grep srNoSer ${INI_FILE}`
    # echo "NoSer=${srNoSer}"

    count=1
    connClust=""

######################################################
# Get the number of Schema / Rest / Connection servers
#   and string them together, with the port number 
#######################################################
    while [ ${count} -le ${srNoSer} ]
    do
        srSerIP=`cat $INI_FILE | grep srSer${count}`
        retip=`echo ${srSerIP} | awk -F "=" '{print $2}'`
        if [ ${count} -gt 1 ]; then
             connClust="${connClust},"
        fi
        connClust="${connClust}${retip}:${connectport}"
        count=$[$count+1]
    done

    IPADDR=`cat $INI_FILE | grep ccSer${SERVER_INSTANCE}`
    ccserver=`echo ${IPADDR} | awk -F "=" '{print $2}'`

    mkdir -p /tmp/control-center/data
    RC=$?
    if [ ${RC} -ne 0 ]; then
        fatalError "$g_prog.run(): Error creating folder /tmp/control-center/data"
    fi
#
    echo "inttopicpart=${inttopicpart}"

    docker run -d \
       --net=host \
       --name=control-center \
       --ulimit nofile=${nofile}:${nofile} \
       -p ${ccport}:${ccport} \
       -v /tmp/control-center/data:/var/lib/confluent-control-center \
       -e CONTROL_CENTER_ZOOKEEPER_CONNECT=${zkKafkaSer1}:${zkpclient},${zkKafkaSer2}:${zkpclient},${zkKafkaSer3}:${zkpclient} \
       -e CONTROL_CENTER_BOOTSTRAP_SERVERS=${zkKafkaSer1}:${kafkapclient},${zkKafkaSer2}:${kafkapclient},${zkKafkaSer3}:${kafkapclient} \
       -e CONTROL_CENTER_REPLICATION_FACTOR=${repfactor} \
       -e CONTROL_CENTER_MONITORING_INTERCEPTOR_TOPIC_PARTITIONS=${montopicpart} \
       -e CONTROL_CENTER_INTERNAL_TOPICS_PARTITIONS=${inttopicpart} \
       -e CONTROL_CENTER_STREAMS_NUM_STREAM_THREADS=${streamthread} \
       -e CONTROL_CENTER_CONNECT_CLUSTER=${connClust} \
       confluentinc/cp-enterprise-control-center:3.1.2
#
    RC=$?
    if [ ${RC} -ne 0 ]; then
        fatalError "$g_prog.run(): Error implementing SchemaRegistry instance - check configuration parameters"
    fi
}

##############################################################
# Install components
##############################################################
function installServer()
{
    installControlCenter
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
  # function calls
    installRPMs
  #  oracleProfile
  #  mountMedia
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

