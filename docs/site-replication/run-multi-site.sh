#!/usr/bin/env bash

# shellcheck disable=SC2120
exit_1() {
    cleanup
    exit 1
}

cleanup() {
    echo "Cleaning up instances of MinIO"
    pkill minio
    pkill -9 minio
    rm -rf /tmp/minio{1,2,3}
}

cleanup

unset MINIO_KMS_KES_CERT_FILE
unset MINIO_KMS_KES_KEY_FILE
unset MINIO_KMS_KES_ENDPOINT
unset MINIO_KMS_KES_KEY_NAME

export MINIO_BROWSER=off
export MINIO_ROOT_USER="minio"
export MINIO_ROOT_PASSWORD="minio123"
export MINIO_KMS_AUTO_ENCRYPTION=off
export MINIO_PROMETHEUS_AUTH_TYPE=public
export MINIO_KMS_SECRET_KEY=my-minio-key:OSMM+vkKUTCvQs9YL/CVMIMt43HFhkUpqJxTmGl6rYw=
export MINIO_IDENTITY_LDAP_SERVER_ADDR="localhost:389"
export MINIO_IDENTITY_LDAP_SERVER_INSECURE="on"
export MINIO_IDENTITY_LDAP_LOOKUP_BIND_DN="cn=admin,dc=min,dc=io"
export MINIO_IDENTITY_LDAP_LOOKUP_BIND_PASSWORD="admin"
export MINIO_IDENTITY_LDAP_USER_DN_SEARCH_BASE_DN="dc=min,dc=io"
export MINIO_IDENTITY_LDAP_USER_DN_SEARCH_FILTER="(uid=%s)"
export MINIO_IDENTITY_LDAP_GROUP_SEARCH_BASE_DN="ou=swengg,dc=min,dc=io"
export MINIO_IDENTITY_LDAP_GROUP_SEARCH_FILTER="(&(objectclass=groupOfNames)(member=%d))"

if [ ! -f ./mc ]; then
    wget -O mc https://dl.minio.io/client/mc/release/linux-amd64/mc \
        && chmod +x mc
fi

minio server --address ":9001" /tmp/minio1/{1...4} >/tmp/minio1_1.log 2>&1 &
minio server --address ":9002" /tmp/minio2/{1...4} >/tmp/minio2_1.log 2>&1 &
minio server --address ":9003" /tmp/minio3/{1...4} >/tmp/minio3_1.log 2>&1 &

sleep 10

export MC_HOST_minio1=http://minio:minio123@localhost:9001
export MC_HOST_minio2=http://minio:minio123@localhost:9002
export MC_HOST_minio3=http://minio:minio123@localhost:9003

./mc admin replicate add minio1 minio2 minio3

./mc admin policy set minio1 consoleAdmin user="uid=dillon,ou=people,ou=swengg,dc=min,dc=io"
sleep 5

./mc admin user info minio2 "uid=dillon,ou=people,ou=swengg,dc=min,dc=io"
./mc admin user info minio3 "uid=dillon,ou=people,ou=swengg,dc=min,dc=io"
./mc admin policy add minio1 rw ./docs/site-replication/rw.json

sleep 5
./mc admin policy info minio2 rw >/dev/null 2>&1
./mc admin policy info minio3 rw >/dev/null 2>&1

./mc admin policy remove minio3 rw

sleep 10
./mc admin policy info minio1 rw
if [ $? -eq 0 ]; then
    echo "expecting the command to fail, exiting.."
    exit_1;
fi

./mc admin policy info minio2 rw
if [ $? -eq 0 ]; then
    echo "expecting the command to fail, exiting.."
    exit_1;
fi

./mc admin user info minio1 "uid=dillon,ou=people,ou=swengg,dc=min,dc=io"
if [ $? -eq 1 ]; then
    echo "policy mapping missing, exiting.."
    exit_1;
fi

./mc admin user info minio2 "uid=dillon,ou=people,ou=swengg,dc=min,dc=io"
if [ $? -eq 1 ]; then
    echo "policy mapping missing, exiting.."
    exit_1;
fi

./mc admin user info minio3 "uid=dillon,ou=people,ou=swengg,dc=min,dc=io"
if [ $? -eq 1 ]; then
    echo "policy mapping missing, exiting.."
    exit_1;
fi

# LDAP simple user
./mc admin user svcacct add minio2 dillon --access-key testsvc --secret-key testsvc123
if [ $? -eq 1 ]; then
    echo "adding svc account failed, exiting.."
    exit_1;
fi

sleep 10

./mc admin user svcacct info minio1 testsvc
if [ $? -eq 1 ]; then
    echo "svc account not mirrored, exiting.."
    exit_1;
fi

./mc admin user svcacct info minio2 testsvc
if [ $? -eq 1 ]; then
    echo "svc account not mirrored, exiting.."
    exit_1;
fi

./mc admin user svcacct rm minio1 testsvc
if [ $? -eq 1 ]; then
    echo "removing svc account failed, exiting.."
    exit_1;
fi

sleep 10
./mc admin user svcacct info minio2 testsvc
if [ $? -eq 0 ]; then
    echo "svc account found after delete, exiting.."
    exit_1;
fi

./mc admin user svcacct info minio3 testsvc
if [ $? -eq 0 ]; then
    echo "svc account found after delete, exiting.."
    exit_1;
fi

cleanup
