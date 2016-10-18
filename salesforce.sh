#!/bin/bash

set -e

function login()
{
xml=$(cat << EOL
<?xml version="1.0" encoding="utf-8" ?>
<env:Envelope xmlns:xsd="http://www.w3.org/2001/XMLSchema"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xmlns:env="http://schemas.xmlsoap.org/soap/envelope/">
  <env:Body>
    <n1:login xmlns:n1="urn:partner.soap.sforce.com">
     <n1:username>$1</n1:username>
     <n1:password>$2</n1:password>
    </n1:login>
  </env:Body>
</env:Envelope>
EOL
)
resp=$(curl -s -XPOST -H "Content-Type: text/xml; charset=UTF-8" -H "SOAPAction: login" -d "$xml" "https://login.salesforce.com/services/Soap/u/37.0")
echo $resp
}

# Arguments: serverUrl, orgId, sessionId
function download_index()
{
    response=$(curl -s -H "Cookie: oid=$2; sid=$3" -XGET $1/servlet/servlet.OrgExport)
    echo $response
}

# Arguments: serverUrl, orgId, sessionId, url, outputdir
function download()
{
    filename=$(echo $4 | grep -oPm1 "(?<=fileName=)[^&]+")
    wget --continue --header "Cookie: sid=$3; oid=$2" $1/$4 -O "$5/$filename"
}

usage="Usage `basename $0` [--help] [-o -f -s -u -t] -- Download and send to s3 salesforce organization backup

where:
    -o	    path to output directory/s3 (default: `pwd`)
    -f      output filename format (default: current time and name, avaiable when -c)
    -u      salesforce username
    -t      salesforce token (concatanated password+security token)
    -s      s3cmd options (default: none)
    --help  show this help text
"

if [ $# == 0 ] || [ $1 == "--help" ]; then
    echo "$usage"
    exit 0
fi

compress=false
outputdir=$(pwd)
filename=""
s3params=""
username=""
token=""
sss=false

while getopts :o:f:s:u:t: option
do
    case "${option}"
    in
        o) outputdir=${OPTARG};;
        f) filename=${OPTARG};;
        s) s3params=${OPTARG};;
        u) username=${OPTARG};;
        t) token=${OPTARG};;
    esac
done

if [ -z "$filename" ]; then
    filename=$(date +"%y%m%d%H%M%S")
fi

output=$outputdir
if [ ${outputdir:0:5} == "s3://" ]; then
    command -v s3cmd >/dev/null 2>&1 || { echo >&2 "I require s3cmd but it's not installed ;("; exit 1; }
    sss=true
    output=$(mktemp -d -t)
fi

loginResp=$(login $username $token)

sessionId=""
orgId=""

sessionId=$(echo $loginResp | grep -oPm1 "(?<=<sessionId>)[^<]+")
orgId=$(echo $loginResp | grep -oPm1 "(?<=<organizationId>)[^<]+")
serverUrl=$(echo $loginResp | grep -oPm1 "(?<=<serverUrl>)[^<]+" | grep -oPm1 "(https://[^/]+)")
files=$(download_index $serverUrl $orgId $sessionId)

IFS=" " read -ra ARGSS <<< "$files"
for i in "${ARGSS[@]}"; do
    download $serverUrl $orgId $sessionId $i $output
done

#if [ $sss == true ]; then
#    s3cmd put $tmpdir/$filename.$ext $outputdir
#    echo "File sent"
#fi


