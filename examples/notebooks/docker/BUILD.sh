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
    press "About to run command 
-- $CMD" && return 1

    $CMD
}

RUN docker build -t mjbright/skippbox-jupyter .
RUN docker build -f Dockerfile.kubelab -t mjbright/kubelab .

RUN docker login
RUN docker push mjbright/skippbox-jupyter:latest
RUN docker login
RUN docker push mjbright/kubelab:latest

## echo; echo  "-- ./REDEPLOY.sh -a"
## ./REDEPLOY.sh -a

echo
RUN ./REDEPLOY.sh -a

