#!/bin/sh

if [ "$INITDB" = 'true' ]; then
    echo "---- InitDB Okapi"

    java -Dstorage=$OKAPI_STORAGE -Dpostgres_host=$PG_HOST -Dpostgres_port=$PG_PORT -Dpostgres_username=$PG_USERNAME \
    -Dpostgres_password=$PG_PASSWORD -Dpostgres_database=$PG_DATABASE -Dhost=$OKAPI_HOST -Dport=$OKAPI_PORT -Dokapiurl=$OKAPI_URL \
    -Dnodename=$OKAPI_NODENAME -Dloglevel=$OKAPI_LOGLEVEL -jar okapi/okapi-core/target/okapi-core-fat.jar initdatabase

    sleep 10
fi

export OKAPI_CLUSTERHOST=$(hostname -i)
export OKAPI_NODENAME=$(hostname)

echo "---- Start Okapi"

java -Dstorage=$OKAPI_STORAGE \
-Dpostgres_host=$PG_HOST -Dpostgres_port=$PG_PORT -Dpostgres_username=$PG_USERNAME -Dpostgres_password=$PG_PASSWORD -Dpostgres_database=$PG_DATABASE \
-Dhost=$OKAPI_HOST -Dport=$OKAPI_PORT -Dokapiurl=$OKAPI_URL \
-Dnodename=$OKAPI_NODENAME -Dloglevel=$OKAPI_LOGLEVEL \
-Dhazelcast.ip=$HAZELCAST_IP -Dhazelcast.port=$HAZELCAST_PORT \
-Dkube_server_url=$KUBE_SERVER_URL -Dkube_server_pem=$KUBE_SERVER_PEM -Dkube_token=$KUBE_TOKEN -Dkube_namespace=$KUBE_NAMESPACE \
--add-modules java.se --add-exports java.base/jdk.internal.ref=ALL-UNNAMED --add-opens java.base/java.lang=ALL-UNNAMED --add-opens java.base/java.nio=ALL-UNNAMED --add-opens java.base/sun.nio.ch=ALL-UNNAMED --add-opens java.management/sun.management=ALL-UNNAMED --add-opens jdk.management/com.sun.management.internal=ALL-UNNAMED \
-jar okapi/okapi-core/target/okapi-core-fat.jar $OKAPI_COMMAND -cluster-host $OKAPI_CLUSTERHOST -cluster-port $HAZELCAST_VERTX_PORT -hazelcast-config-file $HAZELCAST_FILE