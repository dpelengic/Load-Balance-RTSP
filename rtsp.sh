#!/bin/bash
### check for "RTSP/1.0 200 OK" response
RES=$(echo -e "OPTIONS / RTSP/1.0\n" | nc $1 554 |grep "RTSP/1.0 200 OK")
if [[ -z ${RES} ]];
then
        exit 1 # fail
else
        exit 0 # success
fi
