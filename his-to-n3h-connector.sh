#!/bin/bash

#his-to-n3h connector script by Konstantin Kolomiytsev
#version 0.5 (16.08.2021)for http://b2b-demo.n3health.ru/
#kolomiytsev.k@alloroclinic.ru
#
#needs curl and kafkacat packages
#expects kafka messages of following format something like in HL7 manner delimited by |:
#"task type (one of task-create, task-confirm, task-cancel)|(message fields in apropriate order)|end"

configfile=$1
#declare arguments from config file
kafkahost=`cat $configfile|grep kafkahost|cut -d '"' -f2`                         
kafkatopic_his_to_n3h=`cat $configfile|grep kafkatopic_his_to_n3h|cut -d '"' -f2` 
kafkagroup_his_to_n3h=`cat $configfile|grep kafkagroup_his_to_n3h|cut -d '"' -f2` 
my_guid=`cat $configfile|grep guid|cut -d '"' -f2`                                
my_idlpu=`cat $configfile|grep idlpu|cut -d '"' -f2`                              
my_id=`cat $configfile|grep hisid|cut -d '"' -f2`                                 
performer_idlpu=`cat $configfile|grep performerid|cut -d '"' -f2`                 
debug=`cat $configfile|grep debug|cut -d '"' -f2`                                 
datafolder=`cat $configfile|grep datafolder|cut -d '"' -f2`                      

#greetings to those who read the logfile
echo "his-to-n3h connector script by Konstantin Kolomiytsev
version 0.5 (16.08.2021)for http://b2b-demo.n3health.ru/"

#reading arguments
echo "reading arguments from config file $configfile:
kafkahost......................: $kafkahost
kafkatopic_his_to_n3h..........: $kafkatopic_his_to_n3h
kafkagroup_his_to_n3h..........: $kafkagroup_his_to_n3h
my_guid........................: $my_guid
my_idlpu.......................: $my_idlpu
my_id..........................: $my_id
performer_idlpu................: $performer_idlpu
debug..........................: $debug
datafolder.....................: $datafolder"

#checking if arguments are not null
if test -z "$kafkahost"; then 
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$kafkatopic_his_to_n3h"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$kafkagroup_his_to_n3h"; then
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
if test -z "$performer_idlpu"; then
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
if [ -d "$datafolder" ]; then
echo "using folder '$datafolder'"
else
echo "creating folder structure in '$datafolder'"
mkdir -p $datafolder
mkdir -p $datafolder/cache/
mkdir -p $datafolder/data
mkdir -p $datafolder/data/dicom 
fi

#checking if openvpn is up
openvpn_status=`ip addr|grep -c 172.26.0`

#declare functions +

#this function adds anonymised patient when we schedule a study
addanonymouspatient()
{
addanonymouspatientout=`curl -s --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir/Patient?_format=json' \
--header "Authorization: N3 $my_guid" \
--header "Content-Type: application/json" \
--data-raw '{
    "resourceType": "Patient",
    "identifier": [
        {
            "system": "urn:oid:1.2.643.5.1.13.2.7.100.5",
            "value": "'$patientid'",
            "assigner": {
                "display": "'$my_id'"
            }
        }
    ],
    "name": [
        {
            "family": "'$patientid'anonymouslastname",
            "given": [
                "'$patientid'anonymousfirstname",
                "'$patientid'anonymousmiddlename"
            ]
        }
    ],
    "gender": "'$patientgender'",
    "birthDate": "'$patientbirthdate'",
    "managingOrganization": {
        "reference": "Organization/'$my_idlpu'"
    }
}'`
if [[ $debug = 1 ]]; then
echo "reply from n3h for new patient request:"
jq -r '.' <<< $addanonymouspatientout
fi
n3hpatientid=`jq -r '.id' <<< "$addanonymouspatientout"`
}

#this function updates the patient using his real name when we confirm the study
addpatient()
{
addpatientout=`curl -s --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir/Patient?_format=json' \
--header "Authorization: N3 $my_guid" \
--header "Content-Type: application/json" \
--data-raw '{
    "resourceType": "Patient",
    "identifier": [
        {
            "system": "urn:oid:1.2.643.5.1.13.2.7.100.5",
            "value": "'$patientid'",
            "assigner": {
                "display": "'$my_id'"
            }
        }
    ],
    "name": [
        {
            "family": "'$patientlastname'",
            "given": [
                "'$patientfirstname'",
                "'$patientmiddlename'"
            ]
        }
    ],
    "gender": "'$patientgender'",
    "birthDate": "'$patientbirthdate'",
    "managingOrganization": {
        "reference": "Organization/'$my_idlpu'"
    }
}'`
if [[ $debug = 1 ]]; then
echo "reply from n3h for new patient request:"
jq -r '.' <<< $addpatientout
fi
n3hpatientid=`jq -r '.id' <<< $addpatientout`
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
            "value": "'$practitionerid'",
            "assigner": {
                "display": "'$my_id'"
            }
        }
    ],
    "name": {
        "family": "'$practitionerlastname'",
        "given": [
            "'$practitionerfirstname'",
            "'$practitionermiddlename'"
        ]
    }
}'`
if [[ $debug = 1 ]]; then
echo "reply from n3h for new practitioner request:"
jq -r '.' <<< $practitionerout
fi
n3hpractitionerid=`jq -r '.id' <<< $practitionerout`
}

#this function adds practitionerrole
# as we don't care of practitionerrole here, it always uses the same speciality and code
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
          "code": "194"
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
          "code": "24"
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
}

#this function adds device to n3h
#as we currently don't care about the device only modality attributes are used
addevice()
{
deviceout=`curl --silent --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir/Device?_format=json' \
--header "Authorization: N3 $my_guid" \
--header "Content-Type: application/json" \
--data-raw '{
    "resourceType": "Device",
    "identifier": [
        {
            "system": "urn:oid:'$my_id'",
            "value": "'$studymodality'"
        }
    ],
    "type": {
        "coding": [
            {
                "system": "urn:oid:1.2.643.2.69.1.1.1.121",
                "version": "1",
                "code": "'$studymodality'"
            }
        ]
    },
    "status": "active",
    "owner": {
        "reference": "Organization/'$my_idlpu'"
    }
}'`
if [[ $debug = 1 ]]; then
echo "reply from n3h for new device request:"
jq -r '.' <<< $deviceout
fi
n3hdeviceid=`cat <<< "$deviceout"|jq -r '.id'`
}

#this function submits new task to n3h


addtaskbundle()
{
diagnosestringencoded=`echo "$diagnosis"|base64 -i --wrap=0`
ordernotestringencoded=`echo "$studycomment"|base64 -i --wrap=0`

newtaskbundleout=`curl --silent --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir?_format=json' \
--header "Authorization: N3 $my_guid" \
--header "Content-Type: application/json" \
--data-raw '{
  "resourceType": "Bundle",
  "type": "transaction",
  "entry": [
    {
      "fullUrl": "urn:uuid:6aee3e4e-6d66-4818-a9d3-96959f47cc04",
      "resource": {
        "resourceType": "Task",
        "identifier": [
          {
            "system": "urn:oid:'$my_id'",
            "value": "'$accessionnumber'"
          }
        ],
        "intent": "original-order",
        "authoredOn": "'$currentdatetime'",
        "focus": {
          "reference": "urn:uuid:2c98670c-3494-4c63-bb29-71acd486da1d"
        },
        "for": {
          "reference": "Patient/'$n3hpatientid'"
        },
        "requester": {
          "reference": "Organization/'$my_idlpu'"
        },
        "owner": {
          "reference": "Organization/'$performer_idlpu'"
        },
		"note":
		[
		{
  "authorReference" : 
  {
 "reference":  "Practitioner/'$n3hpractitionerid'"
   },
   "time" : "'$currentdatetime'",
  "text" : "'$ordernotestringencoded'"
},
{
  "authorReference" : 
  {
 "reference":  "Organization/'$my_idlpu'"
   },
   "time" : "'$currentdatetime'",
  "text" : "'$studysku'"
}
]
      }
    },
    {
      "fullUrl": "urn:uuid:2c98670c-3494-4c63-bb29-71acd486da1d",
      "resource": {
        "resourceType": "ServiceRequest",
        "intent": "filler-order",
        "priority": "routine",
        "code": {
          "coding": [
            {
              "system": "urn:oid:1.2.643.2.69.1.1.1.57",
              "version": "1",
              "code": "'$studycodenmu'"
            }		
          ]
        },
        "orderDetail": [
          {
            "coding": [
              {
                "system": "urn:oid:1.2.643.2.69.1.1.1.32",
                "version": "1",
                "code": "3"
              }
            ]
          }
        ],
        "subject": {
          "reference": "Patient/'$n3hpatientid'"
        },
        "encounter": {
          "reference": "urn:uuid:f0ceca14-6847-4ea4-b128-7c86820da555"
        },
        "occurrenceTiming": {
          "event": [
            "'$currentdatetime'"
          ],
          "repeat": {
            "duration": 15
          }
        },
        "requester": {
          "reference": "PractitionerRole/'$n3hpractitionerroleid'"
        },
        "performer": [
          {
            "reference": "Device/'$n3hdeviceid'"
          }
        ],
        "supportingInfo": [
          {
            "reference": "urn:uuid:64d57862-f2c2-41ef-a5cf-27f2d5356555"
          },
          {
            "reference": "urn:uuid:651f0cdc-2e7f-4e3a-99b1-da68d2b196c3"
          },
          {
            "reference": "urn:uuid:651f0cdc-2e7f-4e3a-99b1-da68d2b196c4"
          }
        ],
        "bodySite": [
          {
            "coding": [
              {
                "system": "urn:oid:1.2.643.2.69.1.1.1.58",
                "version": "1",
                "code": "1"
              }
            ]
          }
        ],
        "note": [
          {
            "text": "Комментарий"
          }
        ]
      }
    },
    {
      "fullUrl": "urn:uuid:f0ceca14-6847-4ea4-b128-7c86820da555",
      "resource": {
        "resourceType": "Encounter",
        "identifier": [
          {
            "system": "urn:oid:'$my_id'",
            "value": "'$patientid'",
            "assigner": {
              "display": "'$patientid'"
            }
          }
        ],
        "status": "in-progress",
        "class": {
          "system": "urn:oid:2.16.840.1.113883.1.11.13955",
          "version": "1",
          "code": "AMB"
        },
        "type": [
          {
            "coding": [
              {
                "system": "urn:oid:1.2.643.2.69.1.1.1.35",
                "version": "3",
                "code": "2"
              }
            ]
          }
        ],
        "subject": {
          "reference": "Patient/'$n3hpatientid'"
        },
        "reasonCode": [
          {
            "coding": [
              {
                "system": "urn:oid:1.2.643.2.69.1.1.1.19",
                "version": "1",
                "code": "1"
              }
            ]
          }
        ],
        "diagnosis": [
          {
            "condition": {
              "reference": "urn:uuid:64d57862-f2c2-41ef-a5cf-27f2d5356555"
            }
          }
        ],
        "serviceProvider": {
          "reference": "Organization/'$my_idlpu'"
        }
      }
    },
    {
      "fullUrl": "urn:uuid:64d57862-f2c2-41ef-a5cf-27f2d5356555",
      "resource": {
        "resourceType": "Condition",
        "verificationStatus": {
          "coding": [
            {
              "system": "urn:oid:2.16.840.1.113883.4.642.1.1075",
              "version": "1",
              "code": "provisional"
            }
          ]
        },
        "category": [
          {
            "coding": [
              {
                "system": "urn:oid:1.2.643.2.69.1.1.1.36",
                "version": "1",
                "code": "diagnosis"
              }
            ]
          }
        ],
        "code": {
          "coding": [
            {
              "system": "urn:oid:1.2.643.2.69.1.1.1.2",
              "version": "184",
              "code": "Z00.8"
            }
          ]
        },
        "subject": {
          "reference": "Patient/'$n3hpatientid'"
        },
        "recordedDate": "'$currentdatetime'",
        "note": [
          {
            "text": "'$diagnosestringencoded'"
          }
        ]
      }
    },
    {
      "fullUrl": "urn:uuid:651f0cdc-2e7f-4e3a-99b1-da68d2b196c3",
      "resource": {
        "resourceType": "Observation",
        "status": "final",
        "code": {
          "coding": [
            {
              "system": "urn:oid:1.2.643.2.69.1.1.1.37",
              "version": "10",
              "code": "1"
            }
          ]
        },
        "valueQuantity": {
          "value": "'$patienthight'"
        }
      }
    },
    {
      "fullUrl": "urn:uuid:651f0cdc-2e7f-4e3a-99b1-da68d2b196c4",
      "resource": {
        "resourceType": "Observation",
        "status": "final",
        "code": {
          "coding": [
            {
              "system": "urn:oid:1.2.643.2.69.1.1.1.37",
              "version": "10",
              "code": "2"
            }
          ]
        },
        "valueQuantity": {
          "value": "'$patientweight'"
        }
      }
    }
  ]
}'`
if [[ $debug = 1 ]]; then
echo "reply from n3h for new task request:"
jq -r '.' <<< $newtaskbundleout
fi
n3htaskid=`jq '.entry[] | .fullUrl' <<< "$newtaskbundleout" |grep Task|tr -d '"'|cut -d '/' -f2`
}

#this function cancels early submitted task
taskcancel()
{
#first let's find out the id of corresponding task
foundtaskid=`curl --silent --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir/Task/_search?_format=json' \
--header "Authorization: N3 $my_guid" \
--header "Content-Type: application/json" \
--data-raw '{
    "resourceType": "Parameters",
    "parameter": [
        {
            "name": "intent",
            "valueString": "original-order"
        },
        {
            "name": "owner",
            "valueString": "Organization/'$performer_idlpu'"
        },
        {
            "name": "identifier",
            "valueString": "'$accessionnumber'"
        }
    ]
}'`
if [[ $debug = 1 ]]; then
echo "reply from n3h for task search request:"
jq -r '.' <<< $foundtaskid
fi
n3htaskidtocancel=`jq '.entry[] | .resource.id' <<< "$foundtaskid"|tr -d '"'`
if test -z "$n3htaskidtocancel"; then
echo "no task have been submitted yet, skipping"
else
echo "n3h found task id    : '$n3htaskidtocancel'"

#then let's cancel the task
canceltaskoutput=`curl --silent --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir/$updatestatus?_format=json' \
--header "Authorization: N3 $my_guid" \
--header "Content-Type: application/json" \
--data-raw '{
    "resourceType": "Parameters",
    "parameter": [
        {
            "name": "_id",
            "valueString": "'$n3htaskidtocancel'"
        },
        {
            "name": "status",
            "valueString": "cancelled"
        }
    ]
}'`
if [[ $debug = 1 ]]; then
echo "reply from n3h for task cancel request:"
jq -r '.' <<< $canceltaskoutput
fi
fi
}

addschedule()
{
echo "putting sending new schedule slot"

neweventscheduled=`curl --silent --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir/Schedule?_format=json' \
--header "Authorization: N3 $my_guid" \
--header "Content-Type: application/json" \
--data-raw '{
  "resourceType": "Schedule",
  "identifier": [
    {
      "system": "urn:oid:'$my_id'",
      "value": "'$accessionnumber'",
      "type": {
        "coding": [
          {
            "system": "urn:oid:1.2.643.2.69.1.1.1.122",
            "version": "1",
            "code": "ACSN"
          }

        ]
      },
      "assigner": {
        "reference": "Organization/'$my_idlpu'"
      }
    }
  ],
  "active": true,
  "serviceType": [
    {
      "coding": [
        {
          "system": "urn:oid:1.2.643.2.69.1.1.1.121",
          "version": "1",
          "code": "'$studymodality'"
        }
      ]
    }
  ],
  "actor": [
    {
      "reference": "Device/'$n3hdeviceid'"
    }
  ],
  "planningHorizon": {
    "start": "'$studydate'"
  },
  "comment": "'$studysku'"
}'`
if [[ $debug = 1 ]]; then
echo "reply from n3h for add schedule request:"
jq -r '.' <<< $neweventscheduled
fi
}

cancelschedule()
#Seemes there's no way to make schedule active=false
#So just changing SKU to cancelled in comment section
{
echo "cancelling schedule slot"
schedulecancelled=`curl --silent --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir/Schedule?_format=json' \
--header "Authorization: N3 $my_guid" \
--header "Content-Type: application/json" \
--data-raw '{
  "resourceType": "Schedule",
  "identifier": [
    {
      "system": "urn:oid:'$my_id'",
      "value": "'$accessionnumber'",
      "type": {
        "coding": [
          {
            "system": "urn:oid:1.2.643.2.69.1.1.1.122",
            "version": "1",
            "code": "ACSN"
          }

        ]
      },
      "assigner": {
        "reference": "Organization/'$my_idlpu'"
      }
    }
  ],
  "active": true,
  "serviceType": [
    {
      "coding": [
        {
          "system": "urn:oid:1.2.643.2.69.1.1.1.121",
          "version": "1",
          "code": "'$studymodality'"
        }
      ]
    }
  ],
  "actor": [
    {
      "reference": "Device/'$n3hdeviceid'"
    }
  ],
  "planningHorizon": {
    "start": "'$studydate'"
  },
  "comment": "cancelled"
}'`
if [[ $debug = 1 ]]; then
echo "reply from n3h for add schedule request:"
jq -r '.' <<< schedulecancelled
fi
}


searchschedule()
{

echo "searching schedule by his id: $accessionnumber"

schedulesearchresults=`curl --silent --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir/Schedule/_search?_format=json' \
--header "Authorization: N3 $my_guid" \
--header "Content-Type: application/json" \
--data-raw '{
    "resourceType": "Parameters",
    "parameter": [
        {
            "name": "identifier",
            "valueString": "'$accessionnumber'"
        }
    ]
}'`
if [[ $debug = 1 ]]; then
echo "reply from n3h for search schedule request:"
jq -r '.' <<< $schedulesearchresults
fi
scheduletocancel=`jq '.entry[] | .resource.id' <<< "$schedulesearchresults"|tr -d '"'`

}



#declare functions -


#the main loop
while true; do
#check if openvpn tunnel is up
openvpn_status=`ip addr|grep -c 172.26.0`
if [[ $openvpn_status = 1 ]]; then

#reset variables
taskcreate=0
taskconfirm=0
taskcancel=0

#wait for new message from kafka with kafkacat
if [[ $debug = 1 ]]; then
echo "waiting for new message........."
fi

newkafkamessagehiston3health=`kafkacat -C -b $kafkahost -G $kafkagroup_his_to_n3h -c 1 -q $kafkatopic_his_to_n3h`
currentdatetime=`date -u +"%Y-%m-%dT%H:%M:%S.%N"`

#output the raw message for debugging
if [[ $debug = 1 ]]; then
echo "recieved new message:"
echo "$newkafkamessagehiston3health"
fi

#check what have we recieved to run corresponding function
taskcreate=`echo "$newkafkamessagehiston3health"|grep -c task-create`
taskconfirm=`echo "$newkafkamessagehiston3health"|grep -c task-confirm`
taskcancel=`echo "$newkafkamessagehiston3health"|grep -c task-cancel`

#parse the message
tasksubject=`echo "$newkafkamessagehiston3health"|cut -d '|' -f1|tr -d '"'`
patientid=`echo "$newkafkamessagehiston3health"|cut -d '|' -f2`
patientlastname=`echo "$newkafkamessagehiston3health"|cut -d '|' -f4`
patientfirstname=`echo "$newkafkamessagehiston3health"|cut -d '|' -f5`
patientmiddlename=`echo "$newkafkamessagehiston3health"|cut -d '|' -f6`
patientgender=`echo "$newkafkamessagehiston3health"|cut -d '|' -f7`
patientbirthdate=`echo "$newkafkamessagehiston3health"|cut -d '|' -f8`
practitionerlastname=`echo "$newkafkamessagehiston3health"|cut -d '|' -f9`
practitionerfirstname=`echo "$newkafkamessagehiston3health"|cut -d '|' -f10`
practitionermiddlename=`echo "$newkafkamessagehiston3health"|cut -d '|' -f11`
practitionerid=`echo "$newkafkamessagehiston3health"|cut -d '|' -f12`
studydate=`echo "$newkafkamessagehiston3health"|cut -d '|' -f13`
patienthight=`echo "$newkafkamessagehiston3health"|cut -d '|' -f14`
patientweight=`echo "$newkafkamessagehiston3health"|cut -d '|' -f15`
diagnosis=`echo "$newkafkamessagehiston3health"|cut -d '|' -f16`
diagnosiscode=`echo "$newkafkamessagehiston3health"|cut -d '|' -f17`
studycomment=`echo "$newkafkamessagehiston3health"|cut -d '|' -f18`
studycodenmu=`echo "$newkafkamessagehiston3health"|cut -d '|' -f19`
studysku=`echo "$newkafkamessagehiston3health"|cut -d '|' -f20`
studymodality=`echo "$newkafkamessagehiston3health"|cut -d '|' -f21`
accessionnumber=`echo "$newkafkamessagehiston3health"|cut -d '|' -f22`

#output the parsed message for debugging
if [[ $debug = 1 ]]; then
echo "processing '$tasksubject' message from his
patient id............................: '$patientid'
patient last name.....................: '$patientlastname'
patiemt first name....................: '$patientfirstname'
patient middle name...................: '$patientmiddlename'
patient gender........................: '$patientgender'
patient birth date....................: '$patientbirthdate'
patient height (not used).............: '$patienthight'
patient weight (not used).............: '$patientweight'
practitioner last name................: '$practitionerlastname'
practitioner first name...............: '$practitionerfirstname'
practitioner middle name..............: '$practitionermiddlename'
practitioner id.......................: '$practitionerid'
study planned date....................: '$studydate'
submission diagnosis..................: '$diagnosis'
submission diagnosis code (not used)..: '$diagnosiscode'
study comment.........................: '$studycomment'
study code nmu........................: '$studycodenmu'
study his sku.........................: '$studysku'
study modality........................: '$studymodality'
study accession number................: '$accessionnumber'"
fi

#now let's decide what to do with the message
if [[ $taskcreate = 1 ]]; then
echo "task create job"
#when his sumbits new study we should send device and schedue
addevice
addschedule
elif [[ $taskconfirm = 1 ]]; then
echo "task confirm job"
addpatient
addpractitioner
addpractitionerrole
addevice
addtaskbundle
echo "n3h output for study with.............: '$accessionnumber':
n3h patient id........................: '$n3hpatientid'
n3h practitioner id...................: '$n3hpractitionerid'
n3h practitioner role.................: '$n3hpractitionerroleid'
n3h device id.........................: '$n3hdeviceid'
n3h task id...........................: '$n3htaskid'"
elif [[ $taskcancel = 1 ]]; then
echo "task cancel job"
#here we basically cancel schedule
#and also task if it has been submitted
addevice
cancelschedule
taskcancel
else
echo "exception. Unexpected output from message."
fi
else
echo "Openvpn is down, Sleeping 5 seconds"
sleep 5
fi
done
