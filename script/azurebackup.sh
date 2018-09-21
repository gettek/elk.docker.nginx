#!/bin/bash

#===========================================================#
# ELASTICSEARCH BACKUPS TO RUN AS CRON JOB ONCE EVERY NIGHT
#===========================================================#
# CRONTAB ENTRY RUNS AT 00:30
# 30 0 * * * /bin/sh  /media/data/product.monitoring/script/azurebackup.sh > /dev/null

# Check root privilages
GOTROOT=`whoami`
if [ "$GOTROOT" != "root" ]; then
	echo "must be root to execute"
	exit 1
fi

# Create Variables
HOSTNAME=`hostname`
IP=`ifconfig eth0 | grep "inet addr" | cut -d ':' -f 2 | cut -d ' ' -f 1`
DATE=`date +%d.%m.%y`
LOG=/media/data/backups/backup-$DATE.log
SEPERATOR="--------------------------------------\r"
BACKUP_DIR=/media/data/backups
INDEXPATH=/media/data/elk.docker.nginx/data/elasticsearch/
DAYS=7

#===========================
# CREATE MAIN LOG FILE
#===========================
echo "Monitoring Index Backup Cron" > $LOG
echo "Start Date/Time: `/bin/date`" >> $LOG
echo -e "$SEPERATOR" >> $LOG
echo "Hostname = $HOSTNAME" >> $LOG
echo "IP on eth0 = $IP" >> $LOG
echo -e "$SEPERATOR" >> $LOG

#===========================
# BEGIN BACKUP
#===========================
if [ ! -d "$BACKUP_DIR" ]; then
	echo "Creating Backup DIR $BACKUP_DIR" >> $LOG
	mkdir $BACKUP_DIR
fi

echo "Checking for and Removing backups older than $DAYS days" >> $LOG
find "$BACKUP_DIR" -mtime +$DAYS -type f -exec echo {} \; -exec rm {} \; | wc -l
echo "Backing up Indicies to ${BACKUP_DIR}/${DATE}-${HOSTNAME}.tgz" >> $LOG
tar -pczf $BACKUP_DIR/${DATE}-${HOSTNAME}.tgz $INDEXPATH

#===========================
# LOG COMPLETION STEPS
#===========================
echo -e "$SEPERATOR" >> $LOG
echo -e "ElasticSearch Indicies backed up successfully: `/bin/date`" >> $LOG
exit 0 
