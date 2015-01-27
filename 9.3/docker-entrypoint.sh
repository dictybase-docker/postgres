#!/bin/bash
set -e

startpgback() {
    gosu postgres pg_ctl start
}

stoppg() {
    gosu postgres pg_ctl stop
}

preparepg() {
    # setup database
	gosu postgres initdb
    startpgback

    # account setup
    if [ ${POSTGRES_PASSWORD+defined} ]
    then
        pass='$POSTGRES_PASSWORD'
    else
        cat >&2 <<-'EOWARN'
            ****************************************************
                No password has been given for superuser postgres.
                Using default password *postgres*
            ****************************************************
        EOWARN
        pass='postgres'
    fi
    gosu postgres psql -U postgres -c "ALTER ROLE postgres WITH ENCRYPTED PASSWORD $pass"
    
    # create another superuser 
    if [ ${SUPERUSER+defined} -a ${SUPERPASS+defined} ]
    then
        gosu postgres createuser  -U postgres -d -E -l -s $SUPERUSER
        gosu postgres psql -U postgres -c "ALTER ROLE docker PASSWORD '$SUPERPASS'"
        PGPASSWORD=$SUPERPASS createdb -U $SUPERUSER $SUPERUSER
    fi

    # create folders
    if [ ! -e $BACKUP ]; then 
        mkdir -p $BACKUP
        chown postgres:postgres $BACKUP
    fi

    if [ ! -e $ARCHIVE ]; then 
        mkdir -p $ARCHIVE
        chown postgres:postgres $ARCHIVE
    fi
    stoppg
}

if [ "$1" = 'postgres' ]; then
	chown -R postgres $PGDATA
	
	if [ -z "$(ls -A "$PGDATA")" ]; then
		gosu postgres initdb
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
