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

INSTALL=${1:-$HOME/hsds}
INSTALL_LIB=

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

    pip install pytz numba numpy aiobotocore h5py psutil

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

    cat <<EOF >> $HOME/.oio/sds/conf/gridinit.conf

[service.HSDS-$type-$port]
group=HSDS,localhost,hsds,hsds-$type
env.NODE_TYPE=$type
env.${TYPE}_PORT=$port
env.${TYPE}_HOST=$ip
env.AWS_S3_GATEWAY=http://127.0.0.1:5000
env.AWS_SECRET_ACCESS_KEY=DEMO_PASS
env.AWS_ACCESS_KEY_ID=demo:demo
env.AWS_REGION=us-east-1
env.BUCKET_NAME=hsds
env.LOG_LEVEL=debug
env.HOST_IP=$ip
env.OIO_PROXY=http://127.0.0.1:6000
env.HSDS_ENDPOINT=http://hsds
env.PUBLIC_DNS=hsds.localhost
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

register_dn 127.0.0.1 9001
register_dn 127.0.0.1 9002

register_sn 127.0.0.1 9101
register_sn 127.0.0.1 9102
