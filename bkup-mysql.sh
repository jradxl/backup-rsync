#!/usr/bin/env bash
set -e
trap cleanup EXIT
trap controlC INT
START=`date +%s`
ERROR=0
PID1=0 #This process's instance PID
PID2=0 #PID obtained from Run Flag, which might not be same
RUNDIR="/root/backup-scripts"

### MySQL Server Login Info ###
MUSER="root"
# Set as external variable PASSWORD="Your Password"
# Run like this PASSWORD=secret ./bkup-mysql.sh
MHOST="localhost"
MPORT=3306

STATUS=""
MYSQL="$(which mysql)"
MYSQLDATA="/var/lib/mysql/"
MYSQLFLAGS="/var/lib/mysql-bak/"
MYSQLDUMP="$(which mysqldump)"
GZIP="$(which gzip)"
BACKDIR="/mnt/sea8tb/systems/z390ma1/mysql-bak"
LOGPATH=/"var/log/backups/bkup-mysql.log"

NOW=$(date +"%Y-%m-%d-%H-%M-%S")
NOWDATE=$(date +"%Y-%m-%d")

# 25h in seconds adjust to your needs.
MAX_AGE=90000
SCRIPTNAME=$(basename "$0")
FILENAME="${SCRIPTNAME%.*}"
RUNFILE="${FILENAME}.run"
RPATH="$(realpath "$0")";
SCRIPTPATH="$(dirname $RPATH)";

#MariaBackup Variables
BACKCMD=mariabackup
FULLBACKUPCYCLE=604800 # Create a new full backup every X seconds
KEEP=3 # Number of additional backups cycles a backup should kept for.
USEROPT="--user=${MUSER} --password=${PASSWORD}"
HOSTOPT="--host=${MHOST} --port=${MPORT}"
ARGS=""
BASEBACKDIR=$BACKDIR/base
INCRBACKDIR=$BACKDIR/incr

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
    logmessage "\n----------------------------------------------------------\nMariaDB Backup Starting [$NOW]..." 
}

function controlC()
{  
    logmessage "Control C received..."
    ERROR=1
}

function cleanup()
{
    #TODO
    RET="$(find $BACKDIR -type f -mtime +30 -exec rm -f {} \;)"
    #RET="$(find $BACKDIR -type f -mmin +5 -exec rm -f {} \;)"

    SPENT=$((`date +%s` - $START))
    logmessage "took $SPENT seconds"
    logmessage "\nMariaDB Backup Finished [$NOW]\n=========================================================="
    
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

function do_mariabackup()
{  
    #Create the backup file
    #$BACKCMD --backup $USEROPT $ARGS --extra-lsndir=$TARGETDIR --stream=xbstream | gzip > $TARGETDIR/backup.stream.gz
    $BACKCMD --backup $USEROPT $ARGS --stream=xbstream 2>>  $LOGPATH | gzip > $BACKDIR/mariadbbackup-$NOW.stream.gz  
    return 0
}

#Removes flags when databases are deleted
#Iterate all flag dirs, and deletes flag dirs if no corresponding
#directories are found in the MariaDB DataDir
function cleanup_flags()
{
    LIST=$(find $MYSQLFLAGS/* -name "*" -type d -exec echo {} \;)
    for DIR in $LIST
    do
        DIR2=$(basename "$DIR")
        if [ -d $MYSQLDATA/$DIR2 ]
        then
           INFO="Exists - Do Nothing"
        else
           logmessage "Deleting flags for $DIR2"
           rm -r $MYSQLFLAGS/$DIR2
       fi
    done
}

# Checks each database in turn for a changed
# Index file
# parameter $1 : database_name
# Return is via global as Return does not work
function check_mariadb_for_change()
{
    #Change to the database subdirectory
    cd "$MYSQLDATA/$1"

    #==========================
    
    #Create dir for storing of change flags of this database
    if [ ! -d $MYSQLFLAGS/$1 ]
    then
      mkdir -p $MYSQLFLAGS/$1
    fi

    #Find the latest flag file (a precaution there is more than one)
    #then obtain the time stamp from the filename
    AFILE=$(find $MYSQLFLAGS/$1/ -name "*.latest" -print0 | xargs -r -0 ls -1 -t | head -1)
    
    #Test in case there is no flag file, ie first time
    if [ $AFILE ]
    then
        BFILE=${AFILE##*/}
    else
        #In this case we have never backed up, nor set a flag,
        #so we set an arbitary flag file
        BFILE="1580000000.latest"
        touch $MYSQLFLAGS/$1/$BFILE
        RET="Different"
        return 0        
    fi
    #============================  

    #=======================
    #Find the latest Index file and create a flag filename with this date
    DBFILE=$(find . -name "*.ibd" -print0 | xargs -r -0 ls -1 -t | head -1)

    #Test in case there are no index files
    if [ $DBFILE ]
    then
        LTIME=$(stat -c %Y $DBFILE)
        LFILE="${LTIME}.latest"
    else
        #In this case we backup without a flag file,
        #and we set same arbitary flag file, to avoid
        #repeatedly backing up
        LFILE="1580000000.latest"
        touch $MYSQLFLAGS/$1/$LFILE
    fi
    #=============================

    #Compare, and if different the database has at least one table change
    if [ $LFILE = $BFILE ]
    then
        INFO="Same, so do nothing"
        RET="Same"
    else
        #Do the backup if different
        #if backup completes, the remove old flag file
        #and create new flag file
        rm $MYSQLFLAGS/$1/*.latest
        touch $MYSQLFLAGS/$1/$LFILE
        RET="Different"
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
    ### See comments below ###
    ### [ ! -d $BACKDIR ] && mkdir -p $BACKDIR || /bin/rm -f $BACKDIR/* ###
    STATUS="Nothing to do!"
    [ ! -d "$BACKDIR" ] && mkdir -p "$BACKDIR"
     
    DBS="$($MYSQL $USEROPT -Bse 'show databases')"

    for DB in $DBS
    do
        FILE=$BACKDIR/$DB.$NOW-$(date +"%T").gz
      
        case "$DB" in
        information_schema) 
            INFO="do nothing"
            ;;
        performance_schema) 
            INFO="do nothing"
            ;;
        *) 
            #Determine if the Databases as been changed
            #NB: This function changes PWD
            RET=""
            check_mariadb_for_change "$DB"

            #return to previous path
            cd $RUNDIR
            
            if [ ${RET} = "Same" ]
            then
                INFO="Do Nothing"
            else
                INFO="Do Backup"
                logmessage "Do Backup for $DB"
                STATUS=""
                #10.4.2 and above
                #$MYSQL $USEROPT $DB -e "BACKUP LOCK $DB;"
                
                #Pre 10.4.2
                $MYSQL $USEROPT $DB -e "FLUSH TABLES WITH READ LOCK;"
                
                $MYSQLDUMP $USEROPT $DB --single-transaction --quick | $GZIP -9 > $FILE
                
                #10.4.2 and above
                #$MYSQL  $USEROPT $DB -e "BACKUP UNLOCK;"
                
                #Pre 10.4.2
                $MYSQL $USEROPT $DB -e "UNLOCK TABLES;"
                
                ##Do MariaBackup if mysql database has changed
                if [ "$DB" = "mysql" ] 
                then
                    do_mariabackup
                fi                 
            fi
            ;;
        esac
    done
}

### -- Start Here --- ###
##Use this working directory
## cd $SCRIPTPATH
cd $RUNDIR
startup

#Create dir for storing of change flags
if [ ! -d $MYSQLFLAGS ]
then
  mkdir -p $MYSQLFLAGS
fi

#Check if another instance is running
if checkrunning
then
    INFO="Continuing..."
else
    logmessage "\nERROR: Already Running."
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

#Tests the MariaDB daemon is up without needing credentials
#Assumes only one instance on this server
if [[ $ERROR -eq 0 ]]; then
    UP1=$(pgrep mysqld | wc -l);
    if [ "$UP1" -ne 1 ];
    then
        logmessage  "MariaDB is down. Exiting"
        ERROR=1
    else
        logmessage  "MariaDB is up."
    fi
fi

if [[ $ERROR -eq 0 ]]; then
    #Test the Credentials are OK
    #only this form of execution seems to work
    #something strange about the return value
    if [ -f ${RUNDIR}/bkup-test-mysql.sh ] 
    then
        UP3=$(${RUNDIR}/bkup-test-mysql.sh "$USEROPT")
        case "$UP3" in
            "Credentials not OK")
                logmessage  "Credentials not OK. Exiting"
                ERROR=1
            ;;
            "Credentials OK")
                logmessage  "Credentials OK."
            ;; 
            *)
                #Defensive programming
                logmessage  "ERROR: Programming Error in checking Credentials"
                ERROR=1
            ;;
        esac
    else
        logmessage "ERROR: The sub-script bkup-test-mysql.sh is missing."
        ## Script can continue ##
    fi
fi

if [[ $ERROR -eq 0 ]]; then
    # Puts the current Process ID into the run flag,
    # and we save a copy for later
    PID1=$(echo $$)
    echo $$ >${RUNFILE}

    dobackup
    cleanup_flags
fi

#Exit without using exit

