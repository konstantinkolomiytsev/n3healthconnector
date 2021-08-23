#!/bin/bash

#n3h-to-ris connector script by Konstantin Kolomiytsev
#version 0.5 (19.08.2021)for http://b2b-demo.n3health.ru/
#kolomiytsev.k@alloroclinic.ru
#
#needs curl jq kafkacat dcmtk zip unzip packages
#polls n3h service for new orders, informs ris via kafka, downloads studies and sends them to defined pacs
#should be pretty roubst
#assumes to be used one running script per one remote clinic in separate VM, LXC or docker or as different services on one host
#

configfile=$1
#declare arguments from config file
kafkahost=`cat $configfile|grep kafkahost|cut -d '"' -f2`                         
kafkatopic_n3h_to_ris=`cat $configfile|grep kafkatopic_n3h_to_ris_studies|cut -d '"' -f2`
my_guid=`cat $configfile|grep guid|cut -d '"' -f2`                                
my_idlpu=`cat $configfile|grep idlpu|cut -d '"' -f2`                              
my_id=`cat $configfile|grep risid|cut -d '"' -f2`                                 
requester_idlpu=`cat $configfile|grep requester|cut -d '"' -f2`                                         
datafolder=`cat $configfile|grep datafolder|cut -d '"' -f2`
pollinginterval=`cat $configfile|grep pollinginterval|cut -d '"' -f2`
pacshost=`cat $configfile|grep pacshost|cut -d '"' -f2`
pacsport=`cat $configfile|grep pacsport|cut -d '"' -f2`
pacsaet=`cat $configfile|grep pacsaet|cut -d '"' -f2`
myaet=`cat $configfile|grep myaet|cut -d '"' -f2`
debug=`cat $configfile|grep debug|cut -d '"' -f2`
ftpuser=`cat $configfile|grep sftpuser|cut -d '"' -f2`
ftppassword=`cat $configfile|grep sftppassword|cut -d '"' -f2`
 
mysystem="urn:oid:$my_id"
#greetings to those who read the logfile
echo "ris-to-n3h connector script by Konstantin Kolomiytsev
version 0.1 (17.08.2021)for http://b2b-demo.n3health.ru/"

#reading arguments
echo "reading arguments from config file $configfile:
kafkahost......................: $kafkahost
kafkatopic_n3h_to_ris..........: $kafkatopic_n3h_to_ris
my_guid........................: $my_guid
my_idlpu.......................: $my_idlpu
my_id..........................: $my_id
requester_idlpu................: $requester_idlpu
debug..........................: $debug
datafolder.....................: $datafolder
pollinginterval................: $pollinginterval
mysystem.......................: $mysystem
pacshost.......................: $pacshost
pacsport.......................: $pacsport
pacsaet........................: $pacsaet
myaet..........................: $myaet"


#checking if arguments are not null
if test -z "$ftpuser"; then 
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$ftppasswordmore /"; then 
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$kafkahost"; then 
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$kafkatopic_n3h_to_ris"; then
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
if test -z "$pollinginterval"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$pacshost"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$pacsport"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$pacsaet"; then
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$myaet"; then
echo "config file has missing arguments. exiting"
exit 1
fi

#checking subdirs and creating them if they don't exist
if [ -d "$datafolder" ]; then
echo "using folder '$datafolder'"
else
echo "creating folder structure in '$datafolder'"
mkdir $datafolder
mkdir $datafolder/dicom/
fi

#checking if openvpn is up
openvpn_status=`ip addr|grep -c 172.26.0`

#declare functions +

reporttoris()
{
if [[ $debug = 1 ]]; then
echo "finally got all details about planned study to push to ris:
patient:
n3hpatientid.............:$n3hpatientid
his ID...................:$hsipatientid
his last name............:$hispatientlastname
his first name...........:$hispatientfirstname
his middle name..........:$hispatientmiddlename
his gender...............:$hispatientgender
his birth date...........:$hispatientbirthdate
study:
n3h order id.............:$newordernn3hid
his order id.............:$neworderhisid
study sku from his.......:$studyskufromhis
study code nmu...........:$requestedcodenmu
submitted at.............:$ordersubmitted
modality.................:$imagingdevicemodality
practitioner.............:$practitionerfullname
study instance uid.......:$studyinstanceuidfound
endpoint address.........:$endpointdownloadaddress
dicom status.............:$dicomstatus
"
fi

#now pushing all collected stuff to kafka
echo "new-imaes-available|study-section|$newordernn3hid|$neworderhisid|$ordersubmitted|$imagingdevicemodality|$studyskufromhis|$requestedcodenmu|\
$studyinstanceuidfound|$endpointdownloadaddress|$dicomstatus|$practitionerfullname|$neworderstudynote|\
patient-section|$n3hpatientid|$hsipatientid|$patientsnils|$hispatientlastname|$hispatientfirstname|$hispatientmiddlename|\
$hispatientgender|$hispatientbirthdate|$patientphone|$patientemail|end"|kafkacat -P -b $kafkahost -t $kafkatopic_n3h_to_ris -c 1
}

downloadstudy()
{
echo "downloading study $studyinstanceuidfound"
rm -rf /tmp/$requester_idlpu
mkdir  /tmp/$requester_idlpu
mkdir  /tmp/$requester_idlpu/tempdownload
mkdir  /tmp/$requester_idlpu/tempunzip
mkdir  /tmp/$requester_idlpu/tempdicom
sshpass -p "$ftppassword" scp $ftpuser@$endpointdownloadaddress/$studyinstanceuidfound.zip /tmp/$requester_idlpu/tempdownload
if [[ $? != 0 ]]; then
dicomstatus="download-failed"
else
    if [[ $debug = 1 ]]; then
    unzip /tmp/$requester_idlpu/tempdownload/$studyinstanceuidfound.zip -d /tmp/$requester_idlpu/tempunzip
          if [[ $? != 0 ]]; then
          dicomstatus="unzip-failed"
		  mv /tmp/$requester_idlpu/tempdownload/$studyinstanceuidfound.zip $datafolder/dicom/ 
          else
          echo "searching for dicom files and sending them to pacs"
          allfileslistfromziparchive=(`find /tmp/$requester_idlpu/tempunzip/ -type f`)
               if (( ${#allfileslistfromziparchive[@]} = 0 )); then
               dicomstatus="unzip-empty"
			   mv /tmp/$requester_idlpu/tempdownload/$studyinstanceuidfound.zip $datafolder/dicom/ 
               else
                   echo "Here is what's inside"
                   for (( y=0; y<${#allfileslistfromziparchive[@]}; y++ ));
                   do
                   echo "${allfileslistfromziparchive[y]}"
                   mv ${allfileslistfromziparchive[y]} /tmp/$requester_idlpu/tempdicom
                   done
                   ls /tmp/$requester_idlpu/tempdicom
				   storescu --verbose  --no-halt -aet $myaet -aec $pacsaet $pacshost $pacsport /tmp/$requester_idlpu/tempdicom/*
                       if [[ $? != 0 ]]; then
					   dicomstatus="cstore-failed"
					   mv /tmp/$requester_idlpu/tempdownload/$studyinstanceuidfound.zip $datafolder/dicom/ 
                       else
                       sleep 1
                       findscu -S  -aet $myaet -aec $pacsaet $pacshost $pacsport --key 0020,000d="$studyinstanceuidfound"
                          if [[ $? != 0 ]]; then
                          dicomstatus="cfind-failed"
						  else
						  dicomstatus="cfind-success"
                          fi
					   fi
			    fi
			fi
    else
    unzip -qq /tmp/$requester_idlpu/tempdownload/$studyinstanceuidfound.zip -d /tmp/$requester_idlpu/tempunzip
         if [[ $? != 0 ]]; then
         dicomstatus="unzip-failed"
		 mv /tmp/$requester_idlpu/tempdownload/$studyinstanceuidfound.zip $datafolder/dicom/ 
         else
		 numuncompressedfiles=`ls /tmp/$requester_idlpu/tempunzip/*|wc -l`
		      if [[ $numuncompressedfiles = 0 ]]; then   
              dicomstatus="unzip-empty"
			  mv /tmp/$requester_idlpu/tempdownload/$studyinstanceuidfound.zip $datafolder/dicom/ 
              else
			  allfileslistfromziparchive=(`find /tmp/$requester_idlpu/tempunzip/ -type f`)
              for (( y=0; y<${#allfileslistfromziparchive[@]}; y++ ));
              do
              mv ${allfileslistfromziparchive[y]} /tmp/$requester_idlpu/tempdicom
              done
              storescu --log-level error --no-halt -aet $myaet -aec $pacsaet $pacshost $pacsport /tmp/$requester_idlpu/tempdicom/*
			      if [[ $? != 0 ]]; then
                  dicomstatus="cstore-failed"
				  mv /tmp/$requester_idlpu/tempdownload/$studyinstanceuidfound.zip $datafolder/dicom/ 
                  else
                  storescu --log-level error --no-halt -aet $myaet -aec $pacsaet $pacshost $pacsport /tmp/$requester_idlpu/tempdicom/*
                      if [[ $? != 0 ]]; then
                      dicomstatus="cstore-failed"
                      else
                      sleep 1
                      findscu -S -aet $myaet -aec $pacsaet $pacshost $pacsport --key 0020,000d="$studyinstanceuidfound"
                         if [[ $? != 0 ]]; then
                         dicomstatus="cfind-failed"
						 else
						 dicomstatus="cfind-success"
                        fi
                      fi
				   fi
			   fi
	    fi
    fi
fi
echo "dicom status......$dicomstatus"
alreadycheckedboorders+=($boorder)
reporttoris

}

#this function parses Endpiont and gets the url for study
parseendpiont()
{
if test -z "$endpiontreference"; then
echo "exception. no Endpiont found"
else
echo "parsing......$endpiontreference"
endpiontreferenceoutput=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$endpiontreference --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "parsing Endpiont:"
jq -r '.' <<< $endpiontreferenceoutput
fi
endpointdownloadaddress=`jq '.address' <<< $endpiontreferenceoutput |tr -d '"'`
downloadstudy
fi
}

#this function parses Imaging study
parseimagingstudy()
{
imagingstudyreference=`jq -r '.imagingStudy[] .reference' <<< "$referenceurloutput"|tr -d '"'`
if test -z "$imagingstudyreference"; then
echo "exception. no imaging study found"
else
echo "parsing......$imagingstudyreference"
imagingstudyoutput=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$imagingstudyreference --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "parsing ImagingStudy:"
jq -r '.' <<< $imagingstudyoutput
fi
studyinstanceuidfound=`jq '.' <<< $imagingstudyoutput |grep -A2 "urn:dicom:uid" |grep "value"|xargs|cut -d ':' -f4`
echo "Study Instance UID found: $studyinstanceuidfound"
endpiontreference=`jq '.endpoint[] .reference' <<< $imagingstudyoutput |tr -d '"'`
parseendpiont
fi
}

getorderdetails()
{
echo "searching orders based on original-order $newordernn3hid"
ordersbasedon=`curl --silent --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir/Task/_search?_format=json' \
--header "Authorization: N3 $my_guid" \
--header "Content-Type: application/json" \
--data-raw '{
    "resourceType": "Parameters",
    "parameter": [
        {
            "name": "intent",
            "valueString": "reflex-order"
        },
        {
            "name": "based-on",
            "valueString": "'$newordernn3hid'"
        },
        {
            "name": "_count",
            "valueString": "10000"
        }, 
    { 
      "name": "_lastUpdated", 
      "valueString": "ge2021-08-18" 
    }
    ]
}'`
if [[ $debug = 1 ]]; then
echo "reply from n3h for search orders based on newordernn3hid:"
jq -r '.' <<< "$ordersbasedon"
fi
#making arrays from reply
thereissomething=`jq '.entry[0] | .resource.id' <<< "$ordersbasedon" |tr -d '"'|xargs`

if [[ $thereissomething = null ]]; then
echo "no reflex-orders found for original-order $newordernn3hid"
else
n3hordersbasedon=(`jq '.entry[] | .resource.id' <<< "$ordersbasedon" |tr -d '"'`)
n3hordersbasedonauhor=(`jq -r '.entry[] .resource.identifier[0] .system' <<< "$ordersbasedon" |tr -d '"'`)
n3hordersbasedonreference=(`jq -r '.entry[] .resource.focus.reference' <<< "$ordersbasedon" |tr -d '"'`)
echo "found ${#n3hordersbasedon[@]} reflex-orders for original-order $investigateorder:"
for (( z=0; z<${#n3hordersbasedon[@]}; z++ ));
do
echo "task id...:${n3hordersbasedon[$z]}   system...:${n3hordersbasedonauhor[$z]}  reference...:${n3hordersbasedonreference[$z]}"
done

for (( z=0; z<${#n3hordersbasedon[@]}; z++ ));
do

boorder=${n3hordersbasedon[z]}
bodiagnisticreport=${n3hordersbasedonreference[z]}
boauthor=${n3hordersbasedonauhor[z]}

for (( k=0; k<${#alreadycheckedboorders[@]}; k++ ));
do
newbo=1
thisalreadycheckedboorder=${alreadycheckedboorders[k]}

                if [[ $thisalreadycheckedboorder = $boorder ]]; then
                echo "$boorder have been already parsed, skipping"
				newbo=0
                break
                fi
done				

            if [[ $newbo = 1 ]]; then
                    if [[ $boauthor = $mysystem ]]; then
                    echo "This task is from our site. maybe secondary captures"
                    else
                    echo "parsing......Task/$boorder from requester site."
                    echo "parsing......$bodiagnisticreport"
referenceurloutput=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$bodiagnisticreport --header "Authorization: N3 $my_guid"`
                            if [[ $debug = 1 ]]; then
                            echo "parsing......"$referenceurloutput""
                            jq -r '.' <<< "$referenceurloutput"
                            fi
					getneworderdetails
                    parseimagingstudy
                           
				    
                fi
            fi
done
fi


}

parsesupportinginfo()
{
echo "parsing......$hissuportinginfo"
supprtinginfotoparse=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$hissuportinginfo --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "reply from n3h for get supportinginfo request:"
jq -r '.' <<< "$supprtinginfotoparse"
fi
}

parseimagingdevice()
{
echo "parsing......$hisimagingdevice"
imagingdevicetoparse=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$hisimagingdevice --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "reply from n3h for get device request:"
jq -r '.' <<< "$imagingdevicetoparse"
fi
imagingdevicemodality=`jq '.type.coding[] .code' <<< "$imagingdevicetoparse"|tr -d '"'`
}

parsepractitionerrole()
{
echo "parsing......$practitionerrolereference"
practitionerrolereference=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$practitionerrolereference --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "reply from n3h for get practitioner role request:"
jq -r '.' <<< "$practitionerrolereference"
fi
practitionerreference=`jq '.practitioner .reference' <<< "$practitionerrolereference" |tr -d '"'`


echo "parsing......$practitionerreference"
practitionerreference=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$practitionerreference --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "reply from n3h for get practitioner request:"
jq -r '.' <<< "$practitionerreference"
fi

practitionerlastname=`jq -r '.name[] .family' <<< "$practitionerreference"`
practitionerfirstname=`jq -r '.name[] .given[0]' <<< "$practitionerreference"`
practitionermiddlename=`jq -r '.name[] .given[1]' <<< "$practitionerreference"`
practitionerfullname=`echo "$practitionerlastname $practitionerfirstname $practitionermiddlename"`

}

parseservicerequest()
{
echo "parsing......$servicerequestrefernce"
servicerequesttoparse=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$servicerequestrefernce --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "reply from n3h for get patient request:"
jq -r '.' <<< "$servicerequesttoparse"
fi
requestedcodenmu=`jq -r '.' <<< "$servicerequesttoparse"|grep -A3 "1.2.643.2.69.1.1.1.57" |grep "code" |cut -d '"' -f4`
hisimagingdevice=`jq -r '.performer[] .reference' <<< "$servicerequesttoparse"`
n3hencounter=`jq '.encounter .reference' <<< "$servicerequesttoparse"|tr -d '"'`
hissuportinginfo=`jq -r '.supportingInfo[] .reference' <<< "$servicerequesttoparse"`
practitionerrolereference=`jq '.requester .reference' <<< "$servicerequesttoparse" |tr -d '"'`
parseimagingdevice
parsepractitionerrole
}

parsepatient()
{
echo "parsing......$patientreference"
patienttoparse=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$patientreference --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "reply from n3h for get patient request:"
jq -r '.' <<< "$patienttoparse"
fi
hsipatientid=`jq '.identifier[]'  <<< "$patienttoparse" |grep -A1 "1.2.643.5.1.13.2.7.100.5"|grep value|cut -d '"' -f4`
hispatientgender=`jq '.gender'  <<< "$patienttoparse" |tr -d '"'`
hispatientbirthdate=`jq '.birthDate'  <<< "$patienttoparse" |tr -d '"'`
hispatientlastname=`jq '.name[] .family'  <<< "$patienttoparse"|tr -d '"'`
hispatientfirstname=`jq '.name[] .given[0]'  <<< "$patienttoparse"|tr -d '"'`
hispatientmiddlename=`jq '.name[] .given[1]'  <<< "$patienttoparse"|tr -d '"'`
}

getneworderdetails()
{
echo "parsing......Task/$newordernn3hid"
newordern3hid=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/Task/$newordernn3hid --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "reply from n3h for get task request:"
jq -r '.' <<< "$newordern3hid"
fi
ordersubmitted=`jq -r '.authoredOn' <<< "$newordern3hid"`
patientreference=`jq -r '.for .reference' <<< "$newordern3hid"`
n3hpatientid=`jq -r '.for .reference' <<< "$newordern3hid"`
servicerequestrefernce=`jq -r '.focus .reference' <<< "$newordern3hid"`
parsepatient
parseservicerequest


}

queryn2hforchangedoriginalorders()
{
echo "searching original-orders recently changed"
n3htaskquery=`curl --silent --location --request POST 'http://b2b-demo.n3health.ru/imaging/api/fhir/Task/_search?_format=json' \
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
            "name": "requester",
            "valueString": "Organization/'$requester_idlpu'"
        },
        {
            "name": "status",
            "valueString": "in-progress"
        },
        {
            "name": "_count",
            "valueString": "10000"
        }
    ]
}'`
if [[ $debug = 1 ]]; then
echo "reply from n3h for search request:"
jq -r '.' <<< "$n3htaskquery"
fi

thereissomething=`jq '.entry[0] | .resource.id' <<< "$n3htaskquery" |tr -d '"'`
if [[ $thereissomething = null ]]; then
echo "no original-orders found from requester $requester_idlpu"
else

#making arrays from reply
n3horders=(`jq '.entry[] | .resource.id' <<< "$n3htaskquery" |tr -d '"'`)
hisorders=(`jq -r '.entry[] .resource.identifier[0] .value' <<< "$n3htaskquery" |tr -d '"'`)
orderstatus=(`jq -r '.entry[] .resource.status' <<< "$n3htaskquery" |tr -d '"'`)
n3hstudynotefrominitialtask=(`jq '.entry[] .resource.note[0] .text' <<< "$n3htaskquery" |tr -d '"'`)
studyskufromhisarray=(`jq '.entry[] .resource.note[1] .text' <<< "$n3htaskquery" |tr -d '"'`)
echo "found ${#n3horders[@]} original-orders:"
for (( i=0; i<${#n3horders[@]}; i++ ));
do
echo "his id...:${hisorders[$i]}   n3h id...:${n3horders[$i]}   n3h status...:${orderstatus[$i]}"
done

for (( i=0; i<${#n3horders[@]}; i++ ));
do
#echo "status-update|${hisorders[$i]}|${n3horders[$i]}|${orderstatus[$i]}|end" |kafkacat -P -b $kafkahost -t $kafkatopic_n3h_to_ris -c 1
if [[ ${orderstatus[i]} = "requested" ]]; then
#if tast status is requested then we need to know at least what this guys are going to do
#and their patient id so that we can check if we have priors for this guy
echo "this is a new order, will inform ris for scheduling"
elif [[ ${orderstatus[i]} = "in-progress" ]]; then
#in-progress order contains all metadata together with study from his
#in case order has changed it's state from nothing to requested to in-progress
#between our requests we should consider to parse it as a requested order first
#then dig into reflex-orders to find studies
newordernn3hid=${n3horders[i]}
neworderhisid=${hisorders[i]}
neworderstudynote=${n3hstudynotefrominitialtask[i]}
studyskufromhis=${studyskufromhisarray[i]}
echo "checking what's inside in-progress order"
getorderdetails
elif [[ ${orderstatus[i]} = "cancelled" ]]; then
#if status is cancelled, then assumnig that we already have all details about it, just inform ris (not used)
echo "notify ris about cancelled order"
echo "status-update|${hisorders[$i]}|${n3horders[$i]}|${orderstatus[$i]}|end" |kafkacat -P -b $kafkahost -t $kafkatopic_n3h_to_ris -c 1
else
echo "exception, this should not have happened: task status is not requested or in-progress or cancelled; very wired crap"
fi
done
fi

}

forgetoldprocessedorders()
{
if [[ $debug = 1 ]]; then
echo "buffersize before cleanup ${#alreadycheckedboorders[@]}"
if (( ${#alreadycheckedboorders[@]} > 1000 )); then
for (( m=0; m<500; m++ ));
do
echo "forgetting ${alreadycheckedboorders[m]}"
unset alreadycheckedboorders[$m]
done
fi
echo "buffersize after cleanup ${#alreadycheckedboorders[@]}"
sleep 5

else
ordersbuffersize=${#alreadycheckedboorders[@]}
if (( ${#alreadycheckedboorders[@]} > 1000 )); then
for (( m=0; m<500; m++ ));
do
unset alreadycheckedboorders[$m]
done
fi
fi
}

#declare functions -

alreadycheckedboorders=()
alreadycheckedboorders[0]='dummy'

#the main loop
while true; do
#check if openvpn tunnel is up
openvpn_status=`ip addr|grep -c 172.26.0`
if [[ $openvpn_status = 1 ]]; then
queryn2hforchangedoriginalorders
forgetoldprocessedorders

echo "sleeping............"
sleep $pollinginterval
else
echo "Openvpn is down, Sleeping 5 seconds"
sleep 5
fi
done
