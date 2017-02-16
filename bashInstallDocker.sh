#!/bin/bash
#
LOG_FILE=~/bashInstallDocker.log
#
function log()
{
     echo "$(date +%Y/%m/%d_%H:%M:%S.%N) $1" >> $LOG_FILE    
}

function fatalError ()
{
    MSG=$1
    log "FATAL: $MSG"
    echo "ERROR: $MSG"
    exit -1
}

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCR=$(basename "${BASH_SOURCE[0]}")
THIS_SCRIPT=$DIR/$SCR

if [[ $EUID -ne 0 ]]; then
    fatalError "$THIS_SCRIPT must be run as root"
    exit 1
fi

log "Installing git  ..."
#
sudo yum install git
#
log "git installed ..."
log "Installing Docker ..."

sudo unset DOCKER_HOST DOCKER_TLS_VERIFY

sudo yum -y remove docker container-selinux docker-rhel-push-plugin docker-common docker-engine-selinux docker-engine yum-utils
sudo yum install -y yum-utils

sudo yum-config-manager \
    --add-repo \
    https://docs.docker.com/engine/installation/linux/repo_files/centos/docker.repo

sudo yum makecache fast

sudo yum list docker-engine.x86_64  --showduplicates |sort -r
sudo yum list docker-engine.selinux-1.12.6-1.el7.centos  --showduplicates |sort -r

sudo yum -y install docker-engine-selinux-1.12.6-1.el7.centos
sudo yum -y install docker-engine-1.12.6-1.el7.centos

sudo systemctl start docker

log "Docker Installed"




