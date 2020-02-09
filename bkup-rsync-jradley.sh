#!/usr/bin/env bash
set -e
trap cleanup EXIT
trap controlC INT
NOW=$(date +"%Y-%m-%d-%H-%M-%S")
START=`date +%s`
ERROR=0
PID1=0 #This process's instance PID
PID2=0 #PID obtained from Run Flag, which might not be same
STATUS=""
HOST="your-host"
USER="your-user"
DEST="/mnt/your-destination"
SCRIPTNAME=$(basename "$0")
FILENAME="${SCRIPTNAME%.*}"
RUNFILE="${FILENAME}.run"
RPATH="$(realpath "$0")";
SCRIPTPATH="$(dirname $RPATH)";
RUNDIR="/home/$USER/backup-scripts"
LOGFILE="bkup-$USER.log"
LOGDIR="$RUNDIR/logs"
LOGPATH="$LOGDIR/$LOGFILE"

# 25h in seconds adjust to your needs.
MAX_AGE=90000

function logmessage()
{
    if [ ! "$1" = "" ]
    then
        echo -e "$1"  >> $LOGPATH
    #else
        #echo no message
    fi
}

function startup()
{
    logmessage "\n----------------------------------------------------------\nUser $USER Backup Starting [$NOW]..." 
}

function controlC()
{  
    logmessage "Control C received..."
    ERROR=1
}

cleanup()
{    
    SPENT=$((`date +%s` - $START))
    logmessage "took $SPENT seconds"
    logmessage "\nUser $USER Backup Finished [$NOW]\n=========================================================="
    
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

function dobackup()
{
    logmessage "Backing up User $USER"
    rsync -alc --safe-links \
      --log-file="$LOGPATH" \
      --include=".ssh/" \
      --include=".gnupg/" \
      --exclude-from=/etc/rsync/rsync-homedir-local.txt \
      --exclude=/Programs \
      --exclude=/ExpanDrive \
      --exclude=/rclonemnt \
      --exclude=/snap \
      --exclude=/thinclient_drives \
      --exclude=/rdp-share \
      --exclude=/sambashare \
      --exclude=/shared \
      --exclude=/miniconda3 \
      --exclude=".*/" \
      --exclude="*.run" \
      /home/$USER/ $DEST/homes/$HOST/$USER/ \
      >> $LOGPATH 2>&1
      ##--delete \
}

## --- Start Here --- ###
cd "${RUNDIR}"

#Create dir for logs
if [ ! -d "$LOGDIR/" ]; then
    mkdir -p "$LOGDIR/"
fi

startup

# Exit if another version is running
if ! checkrunning ; then
    #Set for failing exit
    ERROR=1
fi

if [[ $ERROR -eq 0 ]]; then
    if mountpoint -q $DEST
    then
        logmessage  "$DEST is mounted OK."
    else
       logmessage  "ERROR: $DEST is not mounted."
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

