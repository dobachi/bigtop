#!/bin/bash
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

BIGTOP_HOME=`cd $(dirname $0)/.. && pwd`

usage() {
    echo "usage build.sh --prefix trunk|1.3.0|1.2.1|... --os debian-8|centos-7|... --target hadoop|tez|... [--nexus]"
    exit 1 # unknown option
}

 if [ $# -eq 0 ]; then
     usage
 fi

while [[ $# -gt 0 ]]
do
key="$1"
case $key in
    -t|--target)
    TARGET="$2"
    shift
    ;;
    -o|--os)
    OS="$2"
    shift
    ;;
    -p|--prefix)
    PREFIX="$2"
    shift
    ;;
    -n|--nexus)
    NEXUS="--net=container:nexus"
    CONFIGURE_NEXUS="configure-nexus"
    shift
    ;;
    -r|--reuse)
    REUSE=true
    shift
    ;;
    *)
    usage
    ;;
esac
shift
done

if [ -z ${PREFIX+x} ]; then
    echo "PREFIX is required";
    UNSATISFIED=true
fi
if [ -z ${OS+x} ]; then
    echo "OS is required";
    UNSATISFIED=true
fi
if [ "$UNSATISFIED" == true ]; then
    usage
fi

IMAGE_NAME=bigtop/slaves:$PREFIX-$OS
ARCH=$(uname -m)
if [ "x86_64" != $ARCH ]; then
    IMAGE_NAME=$IMAGE_NAME-$ARCH
fi

# Start up build container
CONTID_FILE="/tmp/reuse_container_id"
if [ $REUSE = true ]  && [ -f $CONTID_FILE ]; then
  CONTAINER_ID=`cat $CONTID_FILE`
else
  CONTAINER_ID=`docker run -d $NEXUS $IMAGE_NAME /sbin/init`
fi

if [ $REUSE != true ]; then
  trap "docker rm -f $CONTAINER_ID" EXIT
fi

# Copy bigtop repo into container
docker cp $BIGTOP_HOME $CONTAINER_ID:/bigtop
docker cp $BIGTOP_HOME/bigtop-ci/entrypoint.sh $CONTAINER_ID:/bigtop/entrypoint.sh
docker exec $CONTAINER_ID bash -c "chown -R jenkins:jenkins /bigtop"

# Build
docker exec --user jenkins $CONTAINER_ID bash -c "cd /bigtop && ./entrypoint.sh $CONFIGURE_NEXUS $TARGET --info"
RESULT=$?

# save result
mkdir -p output
docker cp $CONTAINER_ID:/bigtop/build .
docker cp $CONTAINER_ID:/bigtop/output .

if [ $REUSE = true ]; then
  echo $CONTAINER_ID > $CONTID_FILE
else
  docker rm -f $CONTAINER_ID
fi

if [ $RESULT -ne 0 ]; then
    exit 1
fi
