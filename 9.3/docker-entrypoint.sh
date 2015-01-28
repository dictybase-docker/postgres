#!/bin/bash
set -e

startpgback() {
    gosu postgres pg_ctl -l /tmp/orebaba start
    cat /tmp/orebaba
    logger -s starting postgresql service
}

stoppg() {
    gosu postgres pg_ctl stop
    logger -s stopping postgresql service
}

preparepg() {
    # setup database
	gosu postgres initdb
    startpgback
    logger -s going to setup pass

    # account setup
    if [ ${POSTGRES_PASSWORD+defined} ]
    then
        logger -s going to use given pass
        pass='$POSTGRES_PASSWORD'
    else
        logger -s going to use default pass
        read -r -d '' warning <<-EOWARN
            ****************************************************
                No password has been given for superuser postgres.
                Using default password *postgres*
            ****************************************************
EOWARN
        echo $warning
        pass='postgres'
    fi
    logger -s going to change pass
    gosu postgres psql -U postgres -c "ALTER ROLE postgres WITH ENCRYPTED PASSWORD $pass"
    
    # create another superuser 
    if [ ${SUPERUSER+defined} -a ${SUPERPASS+defined} ]
    then
        gosu postgres createuser  -U postgres -d -E -l -s $SUPERUSER
        gosu postgres psql -U postgres -c "ALTER ROLE docker PASSWORD '$SUPERPASS'"
        PGPASSWORD=$SUPERPASS createdb -U $SUPERUSER $SUPERUSER
    fi

    # create folders
    #if [ ! -e $BACKUP ]; then 
        #mkdir -p $BACKUP
        #chown postgres:postgres $BACKUP
    #fi

    #if [ ! -e $ARCHIVE ]; then 
        #mkdir -p $ARCHIVE
        #chown postgres:postgres $ARCHIVE
    #fi
    stoppg
}

if [ "$1" = 'postgres' ]; then
	chown -R postgres $PGDATA
	
	if [ -z "$(ls -A "$PGDATA")" ]; then
        preparepg
		
		if [ -d /docker-entrypoint-initdb.d ]; then
            startpgback
			for f in /docker-entrypoint-initdb.d/*.sh; do
				[ -f "$f" ] && . "$f"
			done
            stoppg
		fi
	fi
	
	exec gosu postgres "$@"
fi

exec "$@"
