#!/bin/bash

set -e

command -v mysqldump >/dev/null 2>&1 || { echo >&2 "I require mysqldump but it's not installed ;("; exit 1; }

usage="Usage `basename $0` [--help] [-c -o] database -- Dump database

where:
    -c    compress output file (.tar.xz)
    -o	  path to output directory/s3 (default: `pwd`)
    -h    database host (default: 127.0.0.1)
    -P    database port (default: 3306)
    -u    database user (default: none)
    -p    prompt for database password
    -f    output filename format (default: current time and database name)
    -s    s3cmd options (default: none)
    --help    show this help text
    database  database name
"

if [ $# == 0 ] || [ $1 == "--help" ]; then
    echo "$usage"
    exit 0
fi

# Defaults
compress=false
password=false
outputdir=$(pwd)
databasehost="127.0.0.1"
databaseport=""
databaseuser=""
filename=""
s3params=""
ext="sql"
sss=false

while getopts :h:P:u:f:o:cp option
do
    case "${option}"
    in
        c) compress=true;;
        o) outputdir=${OPTARG};;
        p) password=true;;
        h) databasehost=${OPTARG};;
        P) databaseport=${OPTARG};;
        u) databaseuser=${OPTARG};;
        f) filename=${OPTARG};;
        s) s3params=${OPTARG};;
    esac
done

shift $(($OPTIND - 1))
database=$1

if [ -z "$filename" ]; then
    _now=$(date +"%y%m%d%H%M%S")
    filename="${_now}_$database"
fi

if [ ${outputdir:0:5} == "s3://" ]; then
    command -v s3cmd >/dev/null 2>&1 || { echo >&2 "I require s3cmd but it's not installed ;("; exit 1; }
    sss=true
fi

tmpdir=$(mktemp -d -t)

options="--max-allowed-packet=1073741824 --host=$databasehost"

if [ ! -z "$databaseuser" ]; then
    options="$options --user=$databaseuser"
fi

if [ ! -z "$databaseport" ]; then
    options="$options --port=$databaseport"
fi

if [ $password == true ]; then
    options="$options -p"
fi

echo "Creating database backup ..."
mysqldump $options $database > "$tmpdir/$filename.sql"

if [ $compress == true ]; then
    echo "Compressing database backup ..."
    tar -C $tmpdir/ -cJf $tmpdir/$filename.tar.xz $filename.sql 2>&1
    rm -rf $tmpdir/$filename.sql
    ext="tar.xz"
fi

if [ $sss == true ]; then
    echo "Sending file $filename.$ext to $outputdir"
    s3cmd put $tmpdir/$filename.$ext $outputdir
else
    mv $tmpdir/$filename.$ext $outputdir
fi

rm -rf $tmpdir
echo "Backup saved to $outputdir/$filename.$ext"
