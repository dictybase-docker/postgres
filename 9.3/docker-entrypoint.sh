#!/bin/bash
set -x

startpgback() {
    logger -s starting postgresql service
    gosu postgres pg_ctl start
    sleep 3
}

stoppg() {
    logger -s stopping postgresql service
    gosu postgres pg_ctl stop
}

preparepg() {
    # setup database
	gosu postgres initdb
    
    #Add the custom config file
    mv /pg_hba.conf /var/lib/postgresql/data/

    startpgback

    # account setup
    if [ ${POSTGRES_PASSWORD+defined} ]
    then
        pass="'$POSTGRES_PASSWORD'"
    else
        logger -s going to use default pass
        pass="'postgres'"
    fi
    logger -s "going to use password $pass"
    gosu postgres psql -U postgres -c "ALTER ROLE postgres WITH ENCRYPTED PASSWORD $pass"
    
    # create another superuser 
    if [ ${SUPERUSER+defined} -a ${SUPERPASS+defined} ]
    then
        gosu postgres createuser  -U postgres -d -E -l -s $SUPERUSER
        gosu postgres psql -U postgres -c "ALTER ROLE $SUPERUSER PASSWORD '$SUPERPASS'"
        PGPASSWORD=$SUPERPASS createdb -U $SUPERUSER $SUPERUSER
    fi
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
