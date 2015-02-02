#!/bin/bash

preparepg() {
    # setup database
	gosu postgres initdb

    # account setup
    if [ ${POSTGRES_PASSWORD+defined} ]
    then
        pass="$POSTGRES_PASSWORD"
    else
        pass="postgres"
    fi

    logger -s going to use password $pass
    gosu postgres postgres --single -E <<-EOSQL
        ALTER ROLE postgres WITH ENCRYPTED PASSWORD '$pass';
EOSQL

    # create another superuser 
    if [ "${ADMIN_USER+defined}" -a "${ADMIN_PASS+defined}" ]
    then
        if [ "${ADMIN_DB+defined}" ]
        then
            admindb=$ADMIN_DB
        else
            admindb=$ADMIN_USER
        fi
        logger -s going to create admin database
        gosu postgres postgres --single -E <<-EOSQL
            CREATE ROLE $ADMIN_USER WITH SUPERUSER CREATEDB CREATEROLE LOGIN ENCRYPTED PASSWORD '$ADMIN_PASS';
            CREATE DATABASE $admindb WITH OWNER $ADMIN_USER;
EOSQL
    fi
        
    #Add the custom config file
    #After this every command needs to supply a password
    mv /pg_hba.conf $PGDATA/
    mv /postgresql.conf $PGDATA/
}

if [ "$1" = 'postgres' ]; then
	chown -R postgres $PGDATA

	if [ -z "$(ls -A "$PGDATA")" ]; then
        preparepg

        if ! [ -d ${PGDATA}/conf.d ]
        then
            mkdir -p ${PGDATA}/conf.d
            chown -R postgres ${PGDATA}/conf.d
        fi

		if [ -d /docker-entrypoint-initdb.d ]; then
			for f in /docker-entrypoint-initdb.d/*.sh; do
				[ -f "$f" ] && . "$f"
			done
		fi

        #copy custom config
        if [ -d /config ]
        then
            mv /config/*.conf ${PGDATA}/conf.d/
        fi
	fi
	
	exec gosu postgres "$@"
fi

exec "$@"
