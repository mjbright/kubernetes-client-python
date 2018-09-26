#!/bin/bash

# Function: press <prompt>
# Prompt user to press <return> to continue
# Exit if the user enters q or Q
#
press()
{
    [ ! -z "$1" ] && echo "$*"
    echo "Press <return> to continue"
    read _DUMMY
    [ "$_DUMMY" = "s" ] && return 1
    [ "$_DUMMY" = "S" ] && return 1
    [ "$_DUMMY" = "q" ] && exit 0
    [ "$_DUMMY" = "Q" ] && exit 0
}

RUN() {
    CMD="$*"

    echo
    press "About to run command 
-- $CMD" && return 1

    $CMD
}

die() {
    echo "$0: die - $*" >&2
    exit 1
}

RESTART_JUPYTER() {
    RUN kubectl delete -f jupyter.yml
    RUN kubectl apply -f jupyter.yml 
    RUN kubectl get pods jupyter

    echo "Waiting for Pod to start ..."
    while ! kubectl get --no-headers pod jupyter | grep -q " Running "; do echo $(date) Waiting ...; sleep 5; done
    RUN kubectl get pods jupyter
    RUN kubectl logs jupyter
}

GET_JUPYTER_TOKEN_URL() {
    echo "Getting NODE/IP/PORT for Jupyter ..."
    NODE=$(kubectl get --no-headers pods jupyter -o wide | awk '{ print $NF; }')
    [ -z "$NODE" ] && die "Failed to get NODE"
    echo "Running on node <$NODE>"

    NODE_IP=$(~/z/bin/win64/doctl.exe compute droplet list | awk "/ $NODE / { print \$3; }")
    [ -z "$NODE_IP" ] && die "Failed to get NODE_IP"
    echo "Node <$NODE> has IP <$NODE_IP>"

    NODE_PORT=$(kubectl get --no-headers svc jupyter | sed -e 's/.*://' -e 's-/.*--')
    [ -z "$NODE_PORT" ] && die "Failed to get NODE_PORT"
    echo "Jupyter is exposed on port <$NODE_PORT>"

    URL="http://$NODE_IP:$NODE_PORT"
    # curl -sL $NODE_IP:$NODE_PORT

    TOKEN=$(kubectl logs jupyter | awk -F '=' '/  http:..0.0.0.0:/ { print $2; exit(0); }')
    echo "Token to use is <$TOKEN>"

    TOKEN_URL="$URL/?token=$TOKEN"

    echo
    echo "Jupyter address is $URL"
    echo
    echo "******** Connect using $TOKEN_URL"

    echo
    echo "Using Docker image:"
    kubectl describe pod jupyter | grep -i docker

    RUN kubectl logs -f jupyter
}

RESTART_JUPYTER
GET_JUPYTER_TOKEN_URL


