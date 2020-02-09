#!/usr/bin/env bash
set -e
trap cleanup EXIT
trap controlC INT
NOW=$(date +"%Y-%m-%d-%H-%M-%S")
START=`date +%s`
ERROR=0
STATUS=""
PID1=0 #This process's instance PID
PID2=0 #PID obtained from Run Flag, which might not be same
SCRIPTNAME=$(basename "$0")
FILENAME="${SCRIPTNAME%.*}"
RUNFILE="${FILENAME}.run"
RUNDIR="/root/backup-scripts"
LOGPATH=/"var/log/backups/bkup-systems.log"

# 25h in seconds adjust to your needs.
MAX_AGE=90000

logmessage()
{
    if [ ! "$1" = "" ]
    then
        echo -e "$1"  >> $LOGPATH
    #else
        #echo no message
    fi
}

function controlC()
{  
    logmessage "Control C received..."
    ERROR=1
}

startup()
{
    logmessage "\n----------------------------------------------------------\nSystems Backup Starting [$NOW]..." 
}

function checkrunning()
{
    # check for running process
    if [ -f "${RUNDIR}/${RUNFILE}" ]; then
        if [ $(( $(date +%s) - $(date +%s --reference "${RUNDIR}/${RUNFILE}") )) -gt ${MAX_AGE} ]; then
            logmessage "Backup process has been running too long... Continuing."
            rm "${RUNDIR}/${RUNFILE}";
        else 
            logmessage "Backup process is still running... Exiting."
            return 1
        fi
    fi      
    return 0
}

cleanup()
{    
    SPENT=$((`date +%s` - $START))
    logmessage "took $SPENT seconds"
    logmessage "\nUser Systems Backup Finished [$NOW]\n=========================================================="
    
    if [ $ERROR ]; then
        if [ -f ${RUNDIR}/${RUNFILE} ]; then
            
            #Read PID file. Assume one line!
            while IFS= read -r PID3
            do
                #Scope: Copy to this shell
                PID2=$PID3        
            done < ${RUNDIR}/${RUNFILE}
            
            if [[ $PID1 -eq  $PID2 ]]; then
                #Only delete the Run flag if was set by this instance
                rm ${RUNDIR}/${RUNFILE}
            fi
        fi
    fi
}

dobackup()
{
    logmessage "Backing up ETC..."
    rsync -alc --safe-links \
        --log-file=$LOGPATH \
        --exclude-from=/etc/rsync/rsync-systems.txt \
        --exclude '*.run' \
        /etc/ /mnt/sea8tb/systems/z390ma1/etc/
        
    logmessage "Backing up /VAR/WWW..."
    rsync -alc --safe-links \
        --log-file=$LOGPATH \
        --exclude-from=/etc/rsync/rsync-systems.txt \
        --exclude '*.run' \
        /var/www/ /mnt/sea8tb/systems/z390ma1/var-www/
}

## --- Start Here --- ##
cd "${RUNDIR}"
startup

# Exit if another version is running
if ! checkrunning ; then
    #Set for failing exit
    ERROR=1
fi

if [[ $ERROR -eq 0 ]]; then
    ## findmnt /mnt/sea8tb  >/dev/null 2>&1 ;
    if mountpoint -q /mnt/sea8tb 
    then
        logmessage  "/mnt/sea8tb is mounted OK."
    else
       logmessage  "ERROR: /mnt/sea8tb is not mounted."
       ERROR=1
    fi
fi

if [[ $ERROR -eq 0 ]]; then
    # Puts the current Process ID into the run flag,
    # and we save a copy for later
    PID1=$(echo $$)
    echo $$ > "${RUNDIR}/${RUNFILE}"
    dobackup
fi

##Exit without using exit

