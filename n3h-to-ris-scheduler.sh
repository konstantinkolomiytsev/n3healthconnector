#!/bin/bash

#n3h-to-ris scheduler script by Konstantin Kolomiytsev
#version 0.1 (19.08.2021)for http://b2b-demo.n3health.ru/
#kolomiytsev.k@alloroclinic.ru
#
#needs curl jq kafkacat packages
#polls n3h service for new schedule slots, informs ris via kafka
#should be pretty roubst
#assumes to be used one running script per one remote clinic in separate VM, LXC or docker or as different services on one host
#

configfile=$1
#declare arguments from config file
kafkahost=`cat $configfile|grep kafkahost|cut -d '"' -f2`
kafkatopic_n3h_to_ris_schedule=`cat $configfile|grep kafkatopic_n3h_to_ris_schedule|cut -d '"' -f2`
my_guid=`cat $configfile|grep guid|cut -d '"' -f2`
my_idlpu=`cat $configfile|grep idlpu|cut -d '"' -f2`
my_id=`cat $configfile|grep risid|cut -d '"' -f2`
requester_idlpu=`cat $configfile|grep requester|cut -d '"' -f2`
scheduleupdate=`cat $configfile|grep scheduleupdate|cut -d '"' -f2`
debug=`cat $configfile|grep debug|cut -d '"' -f2`
timesync_correction=`cat $configfile|grep timesync_correction|cut -d '"' -f2`
firstrun_search=`cat $configfile|grep firstrun_search|cut -d '"' -f2`
datafolder=`cat $configfile|grep datafolder|cut -d '"' -f2`
mysystem="urn:oid:$my_id"





#greetings to those who read the logfile
echo "n3h-to-ris scheduler script by Konstantin Kolomiytsev
version 0.1 (19.08.2021)for http://b2b-demo.n3health.ru/"

#reading arguments
echo "reading arguments from config file $configfile:
kafkahost......................: $kafkahost
kafkatopic_n3h_to_ris_schedule.: $kafkatopic_n3h_to_ris_schedule
my_guid........................: $my_guid
my_idlpu.......................: $my_idlpu
my_id..........................: $my_id
requester_idlpu................: $requester_idlpu
debug..........................: $debug
scheduleupdate.................: $scheduleupdate
timesync_correction............: $timesync_correction
firstrun_search................: $firstrun_search
datafolder.....................: $datafolder
mysystem.......................: $mysystem
"


#checking if arguments are not null
if test -z "$kafkahost"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$kafkatopic_n3h_to_ris_schedule"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$my_guid"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$my_idlpu"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$my_id"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$my_idlpu"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$requester_idlpu"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$debug"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$scheduleupdate"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$timesync_correction"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$datafolder"; then
echo "config file has missing arguments. exiting"
exit 1
fi




#declare functions +

searchschedule()
{
founddevicesjson=`curl --silent --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir/Device/_search?_format=json' \
--header "Authorization: N3 $my_guid" \
--header "Content-Type: application/json" \
--data-raw '{
    "resourceType": "Parameters",
    "parameter": [
        {
            "name": "organization",
            "valueString": "'$requester_idlpu'"
        },
        {
            "name": "_count",
            "valueString": "10000"
        }
    ]
}'
`
if [[ $debug = 1 ]]; then
echo "parsing Devices:"
jq -r '.' <<< $founddevicesjson
fi

thereissomething=`jq '.total' <<< "$founddevicesjson" |tr -d '"'`
if [[ $thereissomething = 0 ]]; then
echo "no devices found for  Organization/$requester_idlpu"
else
devicesarray=(`jq '.entry[] .resource.id' <<< "$founddevicesjson" |tr -d '"'`)
for (( i=0; i<${#devicesarray[@]}; i++ ));
do
echo "device...:${devicesarray[i]}"
device=${devicesarray[i]}
findschedulefordevice
done
fi
}


findschedulefordevice()
{
foundschedulefordevice=`curl --silent --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir/Schedule/_search?_format=json' \
--header "Authorization: N3 $my_guid" \
--header "Content-Type: application/json" \
--data-raw '{
    "resourceType": "Parameters",
    "parameter": [
        {
            "name": "actor",
            "valueString": "Device/'$device'"
        },
        {
            "name": "_lastUpdated",
            "valueString": "ge'$currentdatetime'"
        },
        {
            "name": "_count",
            "valueString": "10000"
        }
    ]
}'`
if [[ $debug = 1 ]]; then
echo "parsing Schedule:"
jq -r '.' <<< $foundschedulefordevice
fi

thereissomething=`jq '.total' <<< "$foundschedulefordevice" |tr -d '"'|xargs`
if [[ $thereissomething = 0 ]]; then
echo "no schedule found for Device/$device"
else
echo "found schedule updates:"
schedulesarray=(`jq '.entry[] .resource.id' <<< "$foundschedulefordevice" |tr -d '"'`)
planningstart=(`jq '.entry[] .resource.planningHorizon .start' <<< "$foundschedulefordevice" |tr -d '"'`)
plannedmodality=(`jq -r '.entry[] .resource.serviceType[0] .coding[0] .code' <<< "$foundschedulefordevice"|tr -d '"'`)
plannedsku=(`jq -r '.entry[] .resource.comment' <<< "$foundschedulefordevice"|tr -d '"'`)
for (( j=0; j<${#schedulesarray[@]}; j++ ));
do
thisscheduleslot=${schedulesarray[j]}
thisschedulesku=${plannedsku[j]}
thisplanningtime=${planningstart[j]}
thisschedulemodality=${plannedmodality[j]}

echo "n3h id...:$thisscheduleslot   planned...:$thisplanningtime   his sku...:$thisschedulesku"
echo "schedule-update|$thisscheduleslot|$plannedmodality|$thisschedulesku|$thisplanningtime|end" |kafkacat -P -b $kafkahost -t $kafkatopic_n3h_to_ris_schedule -c 1
done	
fi
}

#declare functions -

#checking subdirs and creating them if they don't exist
if [ -d "$datafolder" ]; then
echo "using folder '$datafolder'"
else
echo "creating folder structure in '$datafolder'"
mkdir -p $datafolder
mkdir -p $datafolder/cache
fi

#get lastupdatetime from cached file
currentdatetime=`cat $datafolder/cache/risschedulerlastupdate`
if test -z "$currentdatetime"; then
currentdatetime="$firstrun_search"
fi
echo "syncing schedules upadted since $currentdatetime"

#the main loop
while true; do
#check if openvpn tunnel is up
openvpn_status=`ip addr|grep -c 172.26.0`
if [[ $openvpn_status = 1 ]]; then
searchschedule
currentdatetime=`date -u +"%Y-%m-%dT%H:%M:%S.00+00:0$timesync_correction"`
echo $currentdatetime > $datafolder/cache/risschedulerlastupdate
echo "sleeping............"
sleep $scheduleupdate
else
echo "Openvpn is down, Sleeping 5 seconds"
sleep 5
fi
done
