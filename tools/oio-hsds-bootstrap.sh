#!/bin/bash

# oio-hsds-boostrap.sh
#
# Copyright (C) 2019 OpenIO SAS, as part of OpenIO SDS
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


# This script will help to deploy HSDS and integrate service and data nodes
# into conscience.

# It requires:
# - python 3.6 or + (numpy dependency)
# - oioswift with swift3 enabled on 127.0.0.1:5000
# - a bucket hsds


if [ "${1}" = "-g" ]; then
	# use deployement path
	LOCAL=0
	shift 1
	ADDR=$1
	if [ "$ADDR" = "" ]; then
		echo "Missing bindind address"
		exit 1
	fi
	# Assume local GW is here
	GW=$ADDR:6007
	ACCESS_KEY=$2
	SECRET_ACCESS=$3
	PROXY=$(cat /etc/oio/sds.conf.d/OPENIO  | grep "proxy" | cut -d= -f2)
	CONSCIENCE=$(cat /etc/oio/sds.conf.d/OPENIO  | grep "conscience" | cut -d= -f2)
	GRIDINIT=/etc/gridinit.d/OPENIO-hsds.conf
else
	# use dev path
	LOCAL=1
	ADDR=127.0.0.1
	GW=127.0.0.1:5000
	ACCESS_KEY=demo:demo
	SECRET_ACCESS=DEMO_PASS
	PROXY=$ADDR:6000
	GRIDINIT=$HOME/.oio/sds/conf/gridinit.conf
fi


INSTALL=$HOME/hsds
INSTALL_LIB=

# usage:
# oio-hsds-bootstrap.sh [-g]

function create_venv() {
    local found=
    for exe in python3.6 python3.7; do
        which $exe || continue
        ok=$(${exe} -c 'import sys; print(sys.version > "3.6")')
        if [ "$ok" == "True" ]; then
            found=$exe
            break
        fi
    done

    [ -z $found ] && echo "Missing Python 3.6 or more" && exit 1

    # deploy
    $found -m venv ${INSTALL}

    . ${INSTALL}/bin//activate
    pip install -U pip wheel setuptools

    pip install pytz numba numpy aiobotocore h5py psutil kubernetes

    pip install git+https://github.com/HDFGroup/h5pyd.git

    # there is no setup.py available
    # pip install git+https://github.com/HDFGroup/hsds.git@openio
    pip install git+https://github.com/murlock/hsds.git@M-openio-fixes

    INSTALL_LIB=$INSTALL/lib/$found/site-packages/
}

function register_gridinit() {
    local type=$1
    local TYPE=$(echo $1 | tr '[:lower:]' '[:upper:]')
    local ip=$2
    local port=$3
    local script=$4

    # Add script to wrap stdout > syslog
    cat <<EOF > $INSTALL/bin/hsds-startup
#!/bin/bash

function trap_exit() {
    local PIDS=\$(jobs -p)
    for pid in \$PIDS; do
        kill \$pid
        wait \$pid
    done
}

trap trap_exit EXIT

RUN=\$1
PREFIX=OIO,OPENIO,\$2,\$3

$INSTALL/bin/python -u \$RUN | logger -t \$PREFIX
EOF
    chmod +x $INSTALL/bin/hsds-startup

    cat <<EOF >> $GRIDINIT

[service.HSDS-$type-$port]
group=HSDS,localhost,hsds,hsds-$type
env.NODE_TYPE=$type
env.${TYPE}_PORT=$port
env.${TYPE}_HOST=$ip
env.AWS_S3_GATEWAY=http://${GW}
env.AWS_SECRET_ACCESS_KEY=$SECRET_ACCESS
env.AWS_ACCESS_KEY_ID=$ACCESS_KEY
env.AWS_REGION=us-east-1
env.BUCKET_NAME=hsds
env.LOG_LEVEL=debug
env.HOST_IP=$ip
env.OIO_PROXY=http://${PROXY}
env.HSDS_ENDPOINT=http://hsds
env.PUBLIC_DNS=hsds.localhost
env.PASSWORD_FILE=
env.MIN_CHUNK_SIZE=16m
env.MAX_CHUNK_SIZE=64m
on_die=cry
enabled=true
start_at_boot=false
env.PYTHONPATH=$INSTALL_LIB/site-packages
command=$INSTALL/bin/hsds-startup $INSTALL_LIB/hsds/$script $type $port
EOF
}

function register_dn() {
    register_gridinit dn $1 $2 datanode.py
}

function register_sn() {
    register_gridinit sn $1 $2 servicenode.py
}

create_venv

register_dn $ADDR 9001
register_dn $ADDR 9002

register_sn $ADDR 9101
register_sn $ADDR 9102

cat <<EOF
- Run oioswift, listening on http://127.0.0.1:5000
- Unlock hsds services with openio cluster
- Create bucket hsds
- Run hsds virtualenv
    - Launch hsconfigure: Server endpoint is a Service Note (API Key and authentication are not used)
    - Run hstouch /home/
    - Run hsinfo: no errors should be shown
EOF
