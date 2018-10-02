#!/bin/bash

YAML_BASE=kubelab
TEMPLATE=${YAML_BASE}.yml.TEMPLATE

BASE_PORT=8800

USERS=1


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

CREATE_YAML() {
    NAMESPACE=$1; shift
    USER=$1; shift
    YAML_FILE=$1; shift

    let PUBLIC_PORT=BASE_PORT+USER

    sed -e "s/PUBLIC_PORT/$PUBLIC_PORT/g" \
        -e "s/NAMESPACE/$NAMESPACE/g" \
        < $TEMPLATE > $YAML_FILE
    ls -altr $YAML_FILE
}

RESTART_JUPYTER() {
    YAML_FILE=$1; shift

    RUN kubectl delete -f $YAML_FILE
    RUN kubectl apply -f $YAML_FILE 

    RUN kubectl get pods jupyter

    echo "Waiting for Pod to start ..."
    while ! kubectl get --no-headers pod jupyter | grep -q " Running "; do echo $(date) Waiting ...; sleep 5; done
    RUN kubectl get pods jupyter
    RUN kubectl logs jupyter
}

GET_JUPYTER_TOKEN_URL() {
    TOKEN_FILE=$1; shift

    echo "Getting NODE/IP/PORT for Jupyter ..."
    NODE=$(kubectl get --no-headers pods jupyter -o wide | awk '{ print $NF; }')
    [ -z "$NODE" ] && die "Failed to get NODE"
    echo "Running on node <$NODE>"

    case $NODE in
        docker-for-desktop) NODE_IP=127.0.0.1;;

        *) 
          # TO CHECK ON digital-ocean (my tf, or their managed):
          # TO CHECK ON azure/aks:
          NODE_IP=$(kubectl describe nodes $NODE | awk '/InternalIP:/ { print $2; }')
          ;;

    esac

    #Digital Ocean:
    #NODE_IP=$(~/z/bin/win64/doctl.exe compute droplet list | awk "/ $NODE / { print \$3; }")
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

    ## echo
    ## echo "Jupyter address is $URL"
    ## echo
    echo "******** Connect using $TOKEN_URL"
    ## echo
    ## echo "Using Docker image:"
    ## kubectl describe pod jupyter | grep -i docker

    RUN kubectl logs -f jupyter

    echo "$TOKEN_URL" > $TOKEN_FILE
    ls -altr $TOKEN_FILE
}

## -- Args: ----------------------------------------------------------------------

while [ ! -z "$1" ]; do
    case $1 in
        -[0-9]*) USERS=${1#-}; break;;
        [0-9]*)  USERS=$1; break;;
        *)      die "Unknown option <$1>";;
    esac
    shift
done

## -- Main: ----------------------------------------------------------------------

for USER in $(seq 1 $USERS); do
    NAMESPACE=USER$USER
    echo USER$USER
    kubectl create namespace $NAMESPACE
    CREATE_YAML $NAMESPACE $USER kubelab_user$USER.yml
    RESTART_JUPYTER kubelab_user$USER.yml
    GET_JUPYTER_TOKEN_URL kubelab_user$USER.txt
done
exit 0



