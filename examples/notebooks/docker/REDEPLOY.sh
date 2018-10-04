#!/bin/bash

PREFIX=kubelab
DEPLOY_TEMPLATE=${PREFIX}_deploy.yml.template
SERVICE_TEMPLATE=${PREFIX}_service.yml.template

PROMPTS=1

mkdir -p tmp/

BASE_PORT=8800

NUM_USERS=1
USERS=""

# Function: press <prompt>
# Prompt user to press <return> to continue
# Exit if the user enters q or Q
#
press()
{
    [ ! -z "$1" ] && echo "$*"

    [ $PROMPTS -eq 0 ] && return 0

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
    PREFIX=$1; shift

    DEPLOY_YAML=tmp/${PREFIX}_deploy_${USER}.yaml
    SERVICE_YAML=tmp/${PREFIX}_service_${USER}.yaml

    USER_NUM=${USER#user}; shift
    let PUBLIC_PORT=BASE_PORT+USER_NUM

    sed -e "s/PUBLIC_PORT/$PUBLIC_PORT/g" \
        -e "s/NAMESPACE/$NAMESPACE/g" \
        < $SERVICE_TEMPLATE > $SERVICE_YAML

    sed -e "s/PUBLIC_PORT/$PUBLIC_PORT/g" \
        -e "s/NAMESPACE/$NAMESPACE/g" \
        < $DEPLOY_TEMPLATE > $DEPLOY_YAML

    ls -altr $DEPLOY_YAML $SERVICE_YAML
}

RESTART_JUPYTER() {
    NAMESPACE=$1; shift
    DEPLOY_YAML=$1; shift
    SERVICE_YAML=$1; shift

    kubectl -n $NAMESPACE get service jupyter 2>/dev/null &&
        RUN kubectl delete -f $SERVICE_YAML
    kubectl -n $NAMESPACE get pod jupyter 2>/dev/null &&
        RUN kubectl delete -f $DEPLOY_YAML

    RUN kubectl apply -f $SERVICE_YAML
    RUN kubectl apply -f $DEPLOY_YAML

    RUN kubectl -n $NAMESPACE get pods jupyter

    echo "Waiting for Pod to start ..."
    while ! kubectl get --no-headers -n $NAMESPACE pod jupyter | grep -q " Running "; do echo $(date) Waiting ...; sleep 5; done
    RUN kubectl -n $NAMESPACE get pods jupyter
    RUN kubectl -n $NAMESPACE logs jupyter
}



start_timer() {
    START_S=`date +%s`
}

stop_timer() {
    END_S=`date +%s`
    let TOOK=END_S-START_S

    hhmmss $TOOK
    echo "Took $TOOK secs [${HRS}h${MINS}m${SECS}]"

}

hhmmss() {
    _REM_SECS=$1; shift

    let SECS=_REM_SECS%60

    let _REM_SECS=_REM_SECS-SECS

    let MINS=_REM_SECS/60%60

    let _REM_SECS=_REM_SECS-60*MINS

    let HRS=_REM_SECS/3600

    [ $SECS -lt 10 ] && SECS="0$SECS"
    [ $MINS -lt 10 ] && MINS="0$MINS"
}


GET_JUPYTER_TOKEN_URL() {
    TOKEN_FILE=$1; shift

    NS_KUBECTL="kubectl -n $NAMESPACE"

    echo "Getting NODE/IP/PORT for Jupyter ..."
    NODE=$($NS_KUBECTL get --no-headers pods jupyter -o wide | awk '{ print $NF; }')
    [ -z "$NODE" ] && die "Failed to get NODE"
    echo "Running on node <$NODE>"

    case $NODE in
        docker-for-desktop)
          echo "Running on a Docker-for-desktop setup"
          NODE_IP=127.0.0.1
          NODE_PORT=$($NS_KUBECTL get --no-headers svc jupyter | sed -e 's/.*://' -e 's-/.*--')
          ;;

        *aks*) 
          echo "Running on an Azure/aks cluster ($CLUSTER)"


          NODE_IP="<pending>"
          start_timer
          echo "Looping whilst EXTERNAL-IP is in pending state:"
          while [ $NODE_IP = "<pending>" ]; do
            NODE_IP=$($NS_KUBECTL get --no-headers svc jupyter | awk '{ print $4; }')
            echo -n "."
          done
          stop_timer
          NODE_PORT=$PUBLIC_PORT
          ;;

        *) 
          echo "Running on an unidentified setup"
          # TO CHECK ON digital-ocean (my tf, or their managed):
          NODE_IP=$($NS_KUBECTL describe nodes $NODE | awk '/InternalIP:/ { print $2; }')
          NODE_PORT=$($NS_KUBECTL get --no-headers svc jupyter | sed -e 's/.*://' -e 's-/.*--')
          ;;

    esac


    #Digital Ocean:
    #NODE_IP=$(~/z/bin/win64/doctl.exe compute droplet list | awk "/ $NODE / { print \$3; }")
    [ -z "$NODE_IP" ] && die "Failed to get NODE_IP"
    echo "Node <$NODE> has IP <$NODE_IP>"
    [ "$NODE_IP" = "<pending>" ] && die "Failed to get NODE_IP ($NODE_IP)"

    [ -z "$NODE_PORT" ] && die "Failed to get NODE_PORT"
    echo "Jupyter is exposed on port <$NODE_PORT>"

    URL="http://$NODE_IP:$NODE_PORT"
    # curl -sL $NODE_IP:$NODE_PORT

    TOKEN=$($NS_KUBECTL logs jupyter | awk -F '=' '/  http:..0.0.0.0:/ { print $2; exit(0); }')
    echo "Token to use is <$TOKEN>"

    TOKEN_URL="$URL/?token=$TOKEN"

    ## echo
    ## echo "Jupyter address is $URL"
    ## echo
    echo "******** Connect using $TOKEN_URL"
    ## echo
    ## echo "Using Docker image:"
    ## $NS_KUBECTL describe pod jupyter | grep -i docker

    #RUN $NS_KUBECTL logs -f jupyter

    echo "$TOKEN_URL" > $TOKEN_FILE
    ls -altr $TOKEN_FILE
}

INSTALL_KUBECONFIG() {
    KCNAME=kubeconfig.${CLUSTER}-${USER}-user
    
    [ ! -f ~/tmp/$KCNAME ] && die "No such kubeconfig file"

    cp -a ~/tmp/$KCNAME tmp/${USER}.kubeconfig
    ls -al tmp/${USER}.kubeconfig
    RUN kubectl cp tmp/${USER}.kubeconfig ${USER}/jupyter:.kube/config
}


SETUP_USER() {
    NAMESPACE=$1; shift
    USER=$1; shift
    DEPLOY_YAML=$1; shift
    SERVICE_YAML=$1; shift
    
    RESTART_JUPYTER $NAMESPACE $DEPLOY_YAML $SERVICE_YAML
    GET_JUPYTER_TOKEN_URL tmp/${PREFIX}_$USER.token.url
    INSTALL_KUBECONFIG
}

## -- Args: ----------------------------------------------------------------------

AUTO=0

while [ ! -z "$1" ]; do
    case $1 in
        -auto)
            # LATER: PROMPTS=0
            AUTO=1
            # Create for all 'users' defined as namespaces ...
            USERS=$(kubectl get ns | awk '/^user[0-9]/ { print $1; }')
            ;;
        -np) PROMPTS=0;;

        -[0-9]*) NUM_USERS=${1#-}; break;;
         [0-9]*) NUM_USERS=$1;     break;;

        -a|--all) 
            # Create for all 'users' defined as namespaces ...
            USERS=$(kubectl get ns | awk '/^user[0-9]/ { print $1; }')
            ;;

        *)      die "Unknown option <$1>";;
    esac
    shift
done

## -- Main: ----------------------------------------------------------------------

[ -z "$USERS" ] && {
    for USER in $(seq 1 $NUM_USERS); do
        USERS+=" user$USER"
    done
}

[ $AUTO -ne 0 ] && echo "About to run in background"
echo "Users are <$(echo $USERS)>"
echo "Current context is $( kubectl config current-context )"
echo
press "Current context is correct?"

[ $AUTO -ne 0 ] && PROMPTS=0

CLUSTER=$(kubectl config get-contexts | awk '/^* / { print $3; }')

for USER in $USERS; do
    NAMESPACE=$USER
    #echo USER$USER

    kubectl get namespace $NAMESPACE 2>&1 >/dev/null ||
        kubectl create namespace $NAMESPACE

    CREATE_YAML $NAMESPACE $USER ${PREFIX}
    if [ $AUTO -ne 0 ];then
        SETUP_USER $NAMESPACE $USER $DEPLOY_YAML $SERVICE_YAML &
    else
        SETUP_USER $NAMESPACE $USER $DEPLOY_YAML $SERVICE_YAML
    fi
done

if [ $AUTO -ne 0 ];then
    echo "Waiting for subprocesses to complete"
    wait
fi

exit 0



