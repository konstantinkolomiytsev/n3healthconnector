#!/bin/bash

#pacs-to-n3h connector script by Konstantin Kolomiytsev
#version 0.5 (16.08.2021)for http://b2b-demo.n3health.ru/
#kolomiytsev.k@alloroclinic.ru
#
#needs curl and kafkacat packages
#expects kafka messages of following format something like in HL7 manner delimited by |:
#"study-new|orthanc url|orthanc study id|study instance uid|accession number|study date|end"
#depends on orthanc server with lua script with "OnstableStudy" function

configfile=$1
#declare arguments from config file
kafkahost=`cat $configfile|grep kafkahost|cut -d '"' -f2`                         
kafkatopic_ris_to_n3h=`cat $configfile|grep kafkatopic_ris_to_n3h|cut -d '"' -f2` 
kafkagroup_ris_to_n3h=`cat $configfile|grep kafkagroup_ris_to_n3h|cut -d '"' -f2` 
my_guid=`cat $configfile|grep guid|cut -d '"' -f2`                             
my_idlpu=`cat $configfile|grep idlpu|cut -d '"' -f2`                           
my_id=`cat $configfile|grep risid|cut -d '"' -f2`                                 
requester_idlpu=`cat $configfile|grep requester|cut -d '"' -f2`             
debug=`cat $configfile|grep debug|cut -d '"' -f2`                                 
datafolder=`cat $configfile|grep datafolder|cut -d '"' -f2`                       
mysystem="urn:oid:$my_id"

#greetings to those who read the logfile
echo "pacs-to-n3h connector script by Konstantin Kolomiytsev
version 0.5 (16.08.2021)for http://b2b-demo.n3health.ru/"

#reading arguments
echo "reading arguments from config file $configfile:
kafkahost.......................: $kafkahost
kafkatopic_ris_to_n3h...........: $kafkatopic_ris_to_n3h
kafkagroup_ris_to_n3h...........: $kafkagroup_ris_to_n3h
my_guid.........................: $my_guid
my_idlpu........................: $my_idlpu
my_id...........................: $my_id
requester_idlpu.................: $requester_idlpu
debug...........................: $debug
datafolder......................: $datafolder
mysystem........................: $mysystem"

#checking if arguments are not null
if test -z "$kafkahost"; then 
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$kafkatopic_ris_to_n3h"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$kafkagroup_ris_to_n3h"; then
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
if test -z "$requester_idlpu"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$debug"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$datafolder"; then
echo "config file has missing arguments. exiting"
exit 1
fi

#creating subdirs and creating them if they don't exist
if [ -d "$datafolder/dicomcache/riston3health" ]; then
echo "using folder $datafolder"
else
echo "creating folder structure in $datafolder"
mkdir -p $datafolder/cache/riston3health
 
fi

#checking if openvpn is up
openvpn_status=`ip addr|grep -c 172.26.0`

#declare functions +

createreportbundle()
{
if [[ $type = report ]]; then
taskrisid=$ris_id
else 
childtasksuffix=`shuf -i 1-1000 -n 1`
taskrisid=$ris_id.$type.$childtasksuffix
fi

printf '{
  "resourceType": "Bundle",
  "type": "transaction",
  "entry": [
    {
      "fullUrl": "urn:uuid:60c9485c-556b-4d67-8b54-35ee9e39083f",
      "resource": {
        "resourceType": "Task",
        "identifier": [
          {
            "system": "urn:oid:'$my_id'",
            "value": "'$taskrisid'"
          }
        ],
        "basedOn": {
          "reference": "Task/'$n3h_uid'"
        },
        "status": "'$status'",
        "intent": "reflex-order",
        "focus": {
          "reference": "urn:uuid:4f6a30fb-cd3c-4ab6-8757-532101f72065"
        },
        "for": {
          "reference": "'$relatedpatient'"
        },
        "authoredOn": "'$currentdatetime'",
        "requester": {
          "reference": "Organization/'$requester_idlpu'"
        },
        "owner": {
          "reference": "Organization/'$my_idlpu'"
        },
        "note": [
          {
            "text": "'$doctor_notes_base64'"
          }
        ]
      }
    },
    {
      "fullUrl": "urn:uuid:4f6a30fb-cd3c-4ab6-8757-532101f72065",
      "resource": {
        "resourceType": "DiagnosticReport",
        "meta": {
          "security": [
            {
              "code": "N"
            }
          ]
        },
        "basedOn": [
          {
            "reference": "'$relatedservicerequest'"
          }
        ],
        "status": "'$diagnosticreportstatus'",
        "category": [
          {
            "coding": [
              {
                "system": "urn:oid:1.2.643.5.1.13.13.11.1472",
                "version": "1",
                "code": "1"
              }
            ]
          }
        ],
        "code": {
          "coding": [
            {
              "system": "urn:oid:1.2.643.2.69.1.1.1.57",
              "version": "1",
              "code": "'$requestedcodenmu'"
            }
          ]
        },
        "subject": {
          "reference": "'$relatedpatient'"
        },
        "effectiveDateTime": "'$currentdatetime'",
        "issued": "'$currentdatetime'",
        "performer": [
          {
            "reference": "PractitionerRole/'$n3hpractitionerroleid'"
          }
        ],
        "result": [
          {
            "reference": "urn:uuid:661f0cdc-2e7f-4e3a-99b1-da68d2b196c6"
          },
          {
            "reference": "urn:uuid:661f0cdc-2e7f-4e3a-99b1-da68d2b196c9"
          }
        ],
        "conclusionCode": [
          {
            "coding": [
              {
                "system": "urn:oid:1.2.643.2.69.1.1.1.2",
                "version": "184",
                "code": "I10"
              }
            ]
          }
        ],
        "presentedForm": [
          {
            "contentType": "application/pdf",
            "url": "urn:uuid:a47a98bf-43b8-4651-8969-39d83d3f3df6"
          }
        ]
      }
    },
    {
      "fullUrl": "urn:uuid:661f0cdc-2e7f-4e3a-99b1-da68d2b196c9",
      "resource": {
        "resourceType": "Observation",
        "status": "final",
        "code": {
          "coding": [
            {
              "system": "urn:oid:1.2.643.2.69.1.1.1.119",
              "version": "1",
              "code": "1"
            }
          ]
        },
        "issued": "'$currentdatetime'",
        "performer": [
          {
            "reference": "PractitionerRole/'$n3hpractitionerroleid'"
          }
        ],
        "valueString": "'$report_text_base64'"
      }
    },
    {
      "fullUrl": "urn:uuid:661f0cdc-2e7f-4e3a-99b1-da68d2b196c6",
      "resource": {
        "resourceType": "Observation",
        "status": "final",
        "code": {
          "coding": [
            {
              "system": "urn:oid:1.2.643.2.69.1.1.1.119",
              "version": "1",
              "code": "2"
            }
          ]
        },
        "issued": "'$currentdatetime'",
        "performer": [
          {
            "reference": "PractitionerRole/'$n3hpractitionerroleid'"
          }
        ],
        "valueString": "'$report_conclusion_base64'"
      }
    },
    {
      "fullUrl": "urn:uuid:a47a98bf-43b8-4651-8969-39d83d3f3df6",
      "resource": {
        "resourceType": "Binary",
        "contentType": "application/pdf",
        "data": "'$report_attachment_base64'"
      }
    }
  ]
}'>/tmp/bloodybigjson.json
createreportbundleout=`curl --silent --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir?_format=json' \
--header "Authorization: N3 $my_guid" \
--header "Content-Type: application/json" \
--data "@/tmp/bloodybigjson.json"`

rm /tmp/bloodybigjson.json

if [[ $debug = 1 ]]; then
echo "reply from n3h for create report bundle:"
jq -r '.' <<< $createreportbundleout
fi

n3htaskid=`jq '.entry[] | .fullUrl' <<< "$createreportbundleout" |grep Task|tr -d '"'|cut -d '/' -f2`

if test -z "$n3htaskid"; then
echo "exception. diagnosticreport task with report was not created, original message from ris stored to cache"
echo $newmessagefromris > $datafolder/cache/riston3health/$n3h_uid.retry
else
echo "created.....Task/$n3htaskid"
fi
}

addpractitionerrole()
{
practitionerroleout=`curl --silent --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir/PractitionerRole?_format=json' \
--header "Authorization: N3 $my_guid" \
--header "Content-Type: application/json" \
--data-raw '{
  "resourceType": "PractitionerRole",
  "active": true,
  "practitioner": {
    "reference": "Practitioner/'$n3hpractitionerid'"
  },
  "organization": {
    "reference": "Organization/'$my_idlpu'"
  },
  "code": [
    {
      "coding": [
        {
          "system": "urn:oid:1.2.643.5.1.13.13.11.1002",
          "version": "1",
          "code": "57"
        }
      ]
    }
  ],
  "specialty": [
    {
      "coding": [
        {
          "system": "urn:oid:1.2.643.5.1.13.13.11.1066",
          "version": "11",
          "code": "11"
        }
      ]
    }
  ]
}'`
if [[ $debug = 1 ]]; then
echo "reply from n3h for new practitionerrole request:"
jq -r '.' <<< $practitionerroleout
fi
n3hpractitionerroleid=`jq -r '.id' <<< $practitionerroleout`
echo "created.....PractitionerRole/$n3hpractitionerroleid"
}

#this function adds practitioner
addpractitioner()
{
practitionerout=`curl --silent --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir/Practitioner?_format=json' \
--header "Authorization: N3 $my_guid" \
--header "Content-Type: application/json" \
--data-raw '{
    "resourceType": "Practitioner",
    "active": true,
    "identifier": [
        {
            "system": "urn:oid:1.2.643.5.1.13.2.7.100.5",
            "value": "'$doctor_id'",
            "assigner": {
                "display": "'$my_id'"
            }
        }
    ],
    "name": {
        "family": "'$doctor_lastname'",
        "given": [
            "'$doctor_firstname'",
            "'$doctor_middlename'"
        ]
    }
}'`
if [[ $debug = 1 ]]; then
echo "reply from n3h for new practitioner request:"
jq -r '.' <<< $practitionerout
fi
n3hpractitionerid=`jq -r '.id' <<< $practitionerout`
echo "created.....Practitioner/$n3hpractitionerid"
addpractitionerrole
}

parseservicerequest()
{
servicerequesttoparse=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$relatedservicerequest --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "reply from n3h for get ServiceRequest request:"
jq -r '.' <<< $servicerequesttoparse
fi
requestedcodenmu=`jq -r '.' <<< "$servicerequesttoparse"|grep -A3 "1.2.643.2.69.1.1.1.57" |grep "code" |cut -d '"' -f4`
}

searchoriginaltask()
{
originaltask=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/Task/$n3h_uid --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "reply from n3h for get original task request:"
jq -r '.' <<< $originaltask
fi
if test -z "$originaltask"; then
echo "exception. original task $n3h_uid was not found"
taskavailable=0
else
taskstatus=`jq '.status' <<< $originaltask |tr -d '"'`
if [[ $taskstatus = completed ]]; then
echo "exception. original task $n3h_uid has already been completed"
elif [[ $taskstatus = cancelled ]]; then
echo "exception. original task $n3h_uid has already been cancelled"
elif [[ $taskstatus = rejected ]]; then
echo "exception. original task $n3h_uid has already been rejected"
else
echo "parsing.....Task/$n3h_uid"
taskavailable=1
relatedservicerequest=`jq '.focus .reference' <<< $originaltask |tr -d '"'`
relatedpatient=`jq '.for .reference' <<< $originaltask |tr -d '"'`
echo "parsing.....$relatedservicerequest"
echo "parsing.....$relatedpatient"
fi
fi
}


#declare functions -

#the main loop
while true; do
#check if openvpn tunnel is up
openvpn_status=`ip addr|grep -c 172.26.0`
if [[ $openvpn_status = 1 ]]; then

#reset variables
newstudy=0

#wait for new message from kafka with kafkacat

echo "waiting for new message........."

#expects |new-report|n3h_uid|ris_id|status<in-progress/completed>|type<report/secondarycaptures>|report_text_base64|report_conclusion_base64|doctor_notes_base64|report_attachment_base64|doctor_id|doctor_lastname|doctor_firstname|doctor_middlename|end
newmessagefromris=`kafkacat -C -b $kafkahost -G $kafkagroup_ris_to_n3h -c 1 -q $kafkatopic_ris_to_n3h`
currentdatetime=`date -u +"%Y-%m-%dT%H:%M:%S.%N+03:00"`

#output the raw message
#echo "$newmessagefromris"
#check what have we recieved to run corresponding function
newreport=`echo "$newmessagefromris"|grep -c new-report`

#parse the message
tasksubject=`echo "$newmessagefromris"|cut -d '|' -f1|tr -d '"'`
n3h_uid=`echo "$newmessagefromris"|cut -d '|' -f2`
ris_id=`echo "$newmessagefromris"|cut -d '|' -f3`
status=`echo "$newmessagefromris"|cut -d '|' -f4`
type=`echo "$newmessagefromris"|cut -d '|' -f5`
report_text_base64=`echo "$newmessagefromris"|cut -d '|' -f6`
report_conclusion_base64=`echo "$newmessagefromris"|cut -d '|' -f7`
doctor_notes_base64=`echo "$newmessagefromris"|cut -d '|' -f8`
report_attachment_base64=`echo "$newmessagefromris"|cut -d '|' -f9`
doctor_id=`echo "$newmessagefromris"|cut -d '|' -f10|xargs`
doctor_lastname=`echo "$newmessagefromris"|cut -d '|' -f11|xargs`
doctor_firstname=`echo "$newmessagefromris"|cut -d '|' -f12|xargs`
doctor_middlename=`echo "$newmessagefromris"|cut -d '|' -f13|xargs`
if [[ $status = "in-progress" ]]; then
diagnosticreportstatus="partial"
elif [[ $status = "completed" ]]; then
diagnosticreportstatus="final"
else
newreport=0
fi

#output the parsed message for debugging
if [[ $debug = 1 ]]; then
echo "processing $tasksubject message from pacs
n3h_uid..................:$n3h_uid
ris_id...................:$ris_id
status...................:$status
type.....................:$type
doctor_id................:$doctor_id
doctor_lastname..........:$doctor_lastname
doctor_firstname.........:$doctor_firstname
doctor_middlename........:$doctor_middlename
report_text_base64.......:$report_text_base64
report_conclusion_base64.:$report_conclusion_base64
doctor_notes_base64......:$doctor_notes_base64"

fi

#now let's decide what to do with the message
             if [[ $newreport = 1 ]]; then
                  if test -z "$n3h_uid"; then
                  echo "bad report - no n3h id specified, skipping"
                  else
                  searchoriginaltask
                      if [[ $taskavailable = 1 ]]; then
					  addpractitioner
                      parseservicerequest
                      createreportbundle
					  fi
			     fi
			else	  
            echo "Crap happened. Unexpected message."
            fi
else
echo "Openvpn is down, Sleeping 5 seconds"
sleep 5
fi
done
