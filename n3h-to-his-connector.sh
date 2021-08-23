#!/bin/bash

#n3h-to-his connector script by Konstantin Kolomiytsev
#version 0.5 (21.08.2021)for http://b2b-demo.n3health.ru/
#kolomiytsev.k@alloroclinic.ru
#
#needs curl jq kafkacat dcmtk zip unzip packages
#polls n3h service for completed orders, informs his via kafka, downloads secondary captures and sends them to defined pacs
#should be pretty roubst
#assumes to be used one running script per one remote clinic in separate VM, LXC or docker or as different services on one host
#

configfile=$1
#declare arguments from config file
kafkahost=`cat $configfile|grep kafkahost|cut -d '"' -f2`                         
kafkatopic_n3h_to_his_result=`cat $configfile|grep kafkatopic_n3h_to_his_result|cut -d '"' -f2`
my_guid=`cat $configfile|grep guid|cut -d '"' -f2`                                
my_idlpu=`cat $configfile|grep idlpu|cut -d '"' -f2`                              
my_id=`cat $configfile|grep hisid|cut -d '"' -f2`                                 
performerid=`cat $configfile|grep performerid|cut -d '"' -f2`                                         
datafolder=`cat $configfile|grep datafolder|cut -d '"' -f2`
pollinginterval=`cat $configfile|grep pollinginterval|cut -d '"' -f2`
debug=`cat $configfile|grep debug|cut -d '"' -f2`
orthanchost=`cat $configfile|grep orthanchost|cut -d '"' -f2`
kafkatopic_n3h_to_his_status=`cat $configfile|grep kafkatopic_n3h_to_his_status|cut -d '"' -f2`
firstrun_search=`cat $configfile|grep firstrun_search|cut -d '"' -f2`
timesync_correction=`cat $configfile|grep timesync_correction|cut -d '"' -f2`
mysystem="urn:oid:$my_id"
#greetings to those who read the logfile
echo "n3h-to-his connector script by Konstantin Kolomiytsev
version 0.5 (21.08.2021)for http://b2b-demo.n3health.ru/"

#reading arguments
echo "reading arguments from config file $configfile:
kafkahost......................:$kafkahost
kafkatopic_n3h_to_his_result...:$kafkatopic_n3h_to_his_result
kafkatopic_n3h_to_his_status ..:$kafkatopic_n3h_to_his_status 
my_guid........................:$my_guid
my_idlpu.......................:$my_idlpu
my_id..........................:$my_id
performerid....................:$performerid
debug..........................:$debug
datafolder.....................:$datafolder
pollinginterval................:$pollinginterval
mysystem.......................:$mysystem
orthanchost....................:$orthanchost
firstrun_search................:$firstrun_search
timesync_correction............:$timesync_correction"


#checking if arguments are not null
if test -z "$timesync_correction"; then 
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$firstrun_search"; then 
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$kafkahost"; then 
echo "config file has missing arguments. exiting"
exit 1
fi
if test -z "$kafkatopic_n3h_to_his_result"; then 
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
if test -z "$performerid"; then
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
if test -z "$orthanchost"; then
echo "config file has missing arguments. exiting"
exit 1
fi

#checking subdirs and creating them if they don't exist
if [ -d "$datafolder" ]; then
echo "using folder '$datafolder'"
else
echo "creating folder structure in '$datafolder'"
mkdir -p $datafolder/cache/n3htohis
fi

#checking if openvpn is up
openvpn_status=`ip addr|grep -c 172.26.0`

#declare functions +

reporttohis()
{
if [[ $debug = 1 ]]; then
echo "finally got all details about report to push to his:
n3h order id.............:$newordernn3hid
his order id.............:$neworderhisid
ris report id............:$boreportrisid
ris report type..........:$boreporttype
submitted at.............:$ordersubmitted
patient..................:$hispatientfullname
practitioner.............:$practitionerfullname
report status............:$reportstatus
biary report available...:$binarydatafound"
fi
if [[ $boreporttype = "report" ]]; then
#assuming new report available, inform his
if [[ $debug = 1 ]]; then
echo "reporting to his:
new-report-available|$newordernn3hid|$neworderhisid|$boreportrisid|$ordersubmitted|$hispatientfullname|$practitionerfullname|$reportstring|$conclusionstring|$boreportdoctornotice|$binarydata|end"
sleep 3
fi

echo '"new-report-available|'$newordernn3hid'|'$neworderhisid'|'$boreportrisid'|'$ordersubmitted'|'$hispatientfullname'|'$practitionerfullname'|'$reportstring'|'$conclusionstring'|'$boreportdoctornotice'|'$binarydata'|end"' |kafkacat -P -b $kafkahost -t $kafkatopic_n3h_to_his_result -c 1


fi
}

parsebinary()
{
echo "parsing......$binaryreference (binary data)"
binaryreferenceoutput=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$binaryreference --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "reply from n3h for binary $binaryreference:"
jq -r '.' <<< "$binaryreferenceoutput"
sleep 1
fi
binarydata=`jq '.data' <<< "$binaryreferenceoutput" |tr -d '"'`

if [[ $debug = 1 ]]; then
echo "binarydata:
$binarydata"
sleep 1
fi

if [[ $binarydata = null ]]; then
echo "exception. no Binary data found"
binarydatafound="no"
else
binarydatafound="yes"
fi
alreadycheckedboorders+=($boorder)
reporttohis
}

parseconclusion()
{
echo "parsing......$conclusionreference (conclusion)"
conclusionreferenceoutput=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$conclusionreference --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "reply from n3h for conclusion $conclusionreference:"
jq -r '.' <<< "$conclusionreferenceoutput"
sleep 1
fi
conclusionstring=` jq '.valueString' <<< "$conclusionreferenceoutput" |tr -d '"'|base64 -d`
}


parsereport()
{
echo "parsing......$reportreference (report)"
reportreferenceoutput=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$reportreference --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "reply from n3h for report $reportreference:"
jq -r '.' <<< "$reportreferenceoutput"
fi
reportstring=` jq '.valueString' <<< "$reportreferenceoutput" |tr -d '"'|base64 -d`
}





getorderdetails()
{
echo "parsing......Task/$newordernn3hid (original order)"
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
        }
    ]
}'`
if [[ $debug = 1 ]]; then
echo "reply from n3h for search orders based on $newordernn3hid:"
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
                    echo "skipping.....Task/$boorder"
                    else
                    echo "parsing......Task/$boorder from performer site."
					boorderoutput=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/Task/$boorder --header "Authorization: N3 $my_guid"`
                            if [[ $debug = 1 ]]; then
                            echo "parced Task/$boorder "
                            jq -r '.' <<< "$boorderoutput"
							sleep 1
                            fi
                    boreportrisid=`jq '.identifier[0] .value ' <<< "$boorderoutput" |tr -d '"'`
                    boreportdoctornotice=`jq '.note[] .text' <<< "$boorderoutput" |tr -d '"'|base64 -d`
					risidtype=`echo $boreportrisid |grep -c report`
					ordersubmitted=`jq -r '.authoredOn' <<< "$boorderoutput"`
					if [[ $risidtype = 1 ]]; then
					boreporttype="report"
					else
					boreporttype="secondarycaptures"
					fi
						
                    echo "parsing......$bodiagnisticreport"
                    referenceurloutput=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$bodiagnisticreport --header "Authorization: N3 $my_guid"`
                            if [[ $debug = 1 ]]; then
                            echo "parced $bodiagnisticreport"
                            jq -r '.' <<< "$referenceurloutput"
							sleep 1
                            fi
							performer=` jq '.performer[] .reference' <<< "$referenceurloutput"|tr -d '"'`
							reportreference=` jq '.result[0] .reference' <<< "$referenceurloutput"|tr -d '"'`
							conclusionreference=` jq '.result[1] .reference' <<< "$referenceurloutput"|tr -d '"'`
							binaryreference=` jq  '.presentedForm[] .url' <<< "$referenceurloutput"|tr -d '"'`
							reportstatus=` jq  '.status' <<< "$referenceurloutput"|tr -d '"'`
							getneworderdetails
							parsepractitionerrole
							parsereport
							parseconclusion
							parsebinary
							
							
					#getneworderdetails
                    #parseimagingstudy
                           
				    
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
sleep 1
fi
}

parsepractitionerrole()
{
echo "parsing......$performer"
practitionerrolereference=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$performer --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "reply from n3h for get practitioner role request:"
jq -r '.' <<< "$practitionerrolereference"
sleep 1
fi
practitionerreference=`jq '.practitioner .reference' <<< "$practitionerrolereference" |tr -d '"'`


echo "parsing......$practitionerreference"
practitionerreference=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/$practitionerreference --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "reply from n3h for get practitioner request:"
jq -r '.' <<< "$practitionerreference"
sleep 1
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
sleep 1
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
sleep 1
fi
hsipatientid=`jq '.identifier[]'  <<< "$patienttoparse" |grep -A1 "1.2.643.5.1.13.2.7.100.5"|grep value|cut -d '"' -f4`
hispatientgender=`jq '.gender'  <<< "$patienttoparse" |tr -d '"'`
hispatientbirthdate=`jq '.birthDate'  <<< "$patienttoparse" |tr -d '"'`
hispatientlastname=`jq '.name[] .family'  <<< "$patienttoparse"|tr -d '"'`
hispatientfirstname=`jq '.name[] .given[0]'  <<< "$patienttoparse"|tr -d '"'`
hispatientmiddlename=`jq '.name[] .given[1]'  <<< "$patienttoparse"|tr -d '"'`
hispatientfullname=`echo "$hispatientlastname $hispatientfirstname $hispatientmiddlename"`
}

getneworderdetails()
{
echo "parsing......Task/$newordernn3hid"
newordern3hid=`curl --silent --location --request GET http://b2b-demo.n3health.ru/imaging/api/fhir/Task/$newordernn3hid --header "Authorization: N3 $my_guid"`
if [[ $debug = 1 ]]; then
echo "reply from n3h for get task request:"
jq -r '.' <<< "$newordern3hid"
sleep 1
fi
patientreference=`jq -r '.for .reference' <<< "$newordern3hid"`
n3hpatientid=`jq -r '.for .reference' <<< "$newordern3hid"`
servicerequestrefernce=`jq -r '.focus .reference' <<< "$newordern3hid"`
parsepatient
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
            "valueString": "Organization/'$my_idlpu'"
        },
        {
            "name": "status",
            "valueString": "completed"
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
echo "reply from n3h for search request:"
jq -r '.' <<< "$n3htaskquery"
sleep 1
fi

thereissomething=`jq '.entry[0] | .resource.id' <<< "$n3htaskquery" |tr -d '"'`
if [[ $thereissomething = null ]]; then
echo "no completed original-orders found from Organization/$performerid"
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
if [[ ${orderstatus[i]} = "requested" ]]; then
#echo "status-update|${hisorders[$i]}|${n3horders[$i]}|${orderstatus[$i]}|end" |kafkacat -P -b $kafkahost -t "$kafkatopic_n3h_to_his" -c 1
#if tast status is requested then we need to know at least what this guys are going to do
#and their patient id so that we can check if we have priors for this guy
echo "this is a new order, skipping"
elif [[ ${orderstatus[i]} = "completed" ]]; then
#in-progress order contains all metadata together with study from his
#in case order has changed it's state from nothing to requested to in-progress
#between our requests we should consider to parse it as a requested order first
#then dig into reflex-orders to find studies
newordernn3hid=${n3horders[i]}
neworderhisid=${hisorders[i]}
neworderstudynote=${n3hstudynotefrominitialtask[i]}
studyskufromhis=${studyskufromhisarray[i]}
getorderdetails
elif [[ ${orderstatus[i]} = "cancelled" ]]; then
#if status is cancelled, then assumnig that we already have all details about it, just inform ris (not used)
echo "notify ris about cancelled order"
echo "status-update|${hisorders[$i]}|${n3horders[$i]}|${orderstatus[$i]}|end" |kafkacat -P -b $kafkahost -t "$kafkatopic_n3h_to_his" -c 1
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

#get lastupdatetime from cached file
currentdatetime=`cat $datafolder/cache/hisreportlastupdate`
if test -z "$currentdatetime"; then
currentdatetime="$firstrun_search"
fi
echo "first search since $currentdatetime"



#the main loop
while true; do
#check if openvpn tunnel is up
openvpn_status=`ip addr|grep -c 172.26.0`
if [[ $openvpn_status = 1 ]]; then
queryn2hforchangedoriginalorders
forgetoldprocessedorders
currentdatetime=`date -u +"%Y-%m-%dT%H:%M:%S.00+00:0$timesync_correction"`
echo $currentdatetime > $datafolder/cache/hisreportlastupdate
echo "sleeping............"
sleep $pollinginterval
else
echo "Openvpn is down, sleeping 5 seconds"
sleep 5
fi
done
