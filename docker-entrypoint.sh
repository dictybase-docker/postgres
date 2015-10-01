#!/bin/bash

set -e

preparepg() {
    # setup database
	gosu postgres initdb

    if [ -e "/secrets/pgpass" ]
    then
        POSTGRES_PASSWORD=$(cat /secrets/pgpass)
    fi

    # account setup
    if [ ${POSTGRES_PASSWORD+defined} ]
    then
        pass="$POSTGRES_PASSWORD"
    else
        pass="postgres"
    fi

    logger -s going to use password $pass
    echo "host all all 0.0.0.0/0 md5" >> ${PGDATA}/pg_hba.conf
    # internal start of server in order to allow set-up using psql-client       
    # does not listen on TCP/IP and waits until start finishes
    gosu postgres pg_ctl -D "$PGDATA" \
        -o "-c listen_addresses=''" \
        -w start

    psql --username postgres <<-EOSQL
        ALTER ROLE postgres WITH ENCRYPTED PASSWORD '$pass';
EOSQL

    # given the options create another admin user
    if [ -e "/secrets/adminuser" -a -e "/secrets/adminpass" ]
    then
        ADMIN_USER=$(cat /secrets/adminuser)
        ADMIN_PASS=$(cat /secrets/adminpass)
        if [ -e "/secrets/admindb" ]
        then
            ADMIN_DB=$(cat /secrets/admindb)
        fi
    fi

    if [ "${ADMIN_USER+defined}" -a "${ADMIN_PASS+defined}" ]
    then
        if [ "${ADMIN_DB+defined}" ]
        then
            admindb=$ADMIN_DB
        else
            admindb=$ADMIN_USER
        fi
        logger -s going to create admin database
        psql --username postgres <<-EOSQL
            CREATE ROLE $ADMIN_USER WITH SUPERUSER CREATEDB CREATEROLE LOGIN ENCRYPTED PASSWORD '$ADMIN_PASS';
            CREATE DATABASE $admindb WITH OWNER $ADMIN_USER;
EOSQL
    fi
        
}

if [ "$1" = 'postgres' ]; then
    mkdir -p $PGDATA
	chown -R postgres $PGDATA

    chmod g+s /run/postgresql
    chown -R postgres /run/postgresql

	if [ ! -e "$PGDATA/PG_VERSION" ]; then
        preparepg

        if ! [ -d ${PGDATA}/conf.d ]
        then
            mkdir -p ${PGDATA}/conf.d
            chown -R postgres ${PGDATA}/conf.d
        fi
 
		if [ -d /docker-entrypoint-initdb.d ]; then
			for f in /docker-entrypoint-initdb.d/*; do
                case "$f" in
                    *.sh)  echo "$0: running $f"; . "$f" ;;
                    *.sql) echo "$0: running $f"; psql --username postgres < "$f" && echo ;; 
                    *)     echo "$0: ignoring $f" ;;
                esac
			done
		fi


        #Add the custom config file
        #After this every command needs to supply a password
        mv /pg_hba.conf $PGDATA/
        mv /postgresql.conf $PGDATA/

        #copy custom config
        if [ -d /config ]
        then
            mv /config/*.conf ${PGDATA}/conf.d/
        fi

        # stop the server
        gosu postgres pg_ctl -D "$PGDATA" -m fast -w stop
        echo 'PostgreSQL init process complete; ready for start up.'
	fi
	
	exec gosu postgres "$@"
fi

exec "$@"
