#!/bin/bash

#######################################################################
# Copyright 2017 Internet2
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#######################################################################

#######################################################################
# Help message
#######################################################################

display_help () {
/bin/cat <<- HELP_MSG
	This script parses one or more SAML metadata files and 
	produces a JSON file of vital statistics. Each metadata file
	must contain the following attributes:
	
	  /md:EntitiesDescriptor/@validUntil
	  /md:EntitiesDescriptor/md:Extensions/mdrpi:PublicationInfo/@creationInstant
	
	The script depends on cached metadata. It will not fetch
	a metadata file from the server.
	
	Usage: ${0##*/} [-hv] -d OUT_DIR MD_LOCATION ...
	
	The script takes one or more metadata locations on the
	command line. For each location, the corresponding metadata
	is read from cache and parsed. The script produces a JSON 
	array, with one array element for each metadata location. 
	If successful, the resulting JSON file is finally moved 
	to the output directory specified on the command line.
	
	Options:
	   -h      Display this help message
	   -v      Enable DEBUG mode
	   -d      Specify the output directory

	Option -h is mutually exclusive of all other options.
	
	Option -d specifies the ultimate output directory, which is
	usually a web directory. This option is REQUIRED.
	
	ENVIRONMENT
	
	This script leverages a handful of environment variables:
	
	  LIB_DIR    A source library directory
	  CACHE_DIR  A persistent HTTP cache
	  TMPDIR     A temporary directory
	  LOG_FILE   A persistent log file
	  LOG_LEVEL  The global log level [0..5]
	
	All of the above environment variables are REQUIRED
	except LOG_LEVEL, which defaults to LOG_LEVEL=3.
	
	The following environment variables are REQUIRED:
	
	$( printf "  %s\n" ${env_vars[*]} )
	
	The following directories will be used:
	
	$( printf "  %s\n" ${dir_paths[*]} )
	
	The following log file will be used:
	
	$( printf "  %s\n" $LOG_FILE )
	
	INSTALLATION
	
	At least the following source library files MUST be installed 
	in LIB_DIR:
	
	$( printf "  %s\n" ${lib_filenames[*]} )
	
	Also, the following XSLT file MUST be installed in LIB_DIR:
	
	  $xsl_filename
	
	OUTPUT
	
	The script outputs a JSON file to OUT_DIR:
	
	  $out_filename
	  
	The JSON file contains a single array. Each array element is 
	a JavaScript object with the following fields:
	
	  successFlag                  boolean    success or failure?
	  message                      string     message string
	  metadataLocation             string     HTTP location
	  creationInstant              string     ISO 8601 dateTime
	  LastModified                 string     ISO 8601 dateTime
	  currentTime                  string     ISO 8601 dateTime
	  validUntil                   string     ISO 8601 dateTime
	  validityInterval             string     ISO 8601 duration
	  sinceCreation                string     ISO 8601 duration
	  untilExpiration              string     ISO 8601 duration
	  betweenCreationAndModified   string     ISO 8601 duration
	  
	For example:

	{
	  "successFlag": true,
	  "message": "Metadata successfully parsed",
	  "metadataLocation": "http://md.incommon.org/InCommon/InCommon-metadata.xml",
	  "creationInstant": "2017-06-12T18:47:48Z",
	  "LastModified": "2017-06-12T20:01:32Z",
	  "currentTime": "2017-06-13T12:20:23Z",
	  "validUntil": "2017-06-26T18:47:48Z",
	  "validityInterval": "P14DT0H0M0S",
	  "sinceCreation": "P0DT17H32M35S",
	  "untilExpiration": "P13DT6H27M25S",
	  "betweenCreationAndModified": "P0DT1H13M44S"
	}
	
	EXAMPLES
	
	  \$ ${0##*/} -h
	  \$ md_locations="http://md.incommon.org/InCommon/InCommon-metadata.xml
	  > http://md.incommon.org/InCommon/InCommon-metadata-export.xml"
	  \$ out_dir=/home/htdocs/www.incommonfederation.org/federation/metadata/
	  \$ ${0##*/} -d \$out_dir \$md_locations
HELP_MSG
}

#######################################################################
# Bootstrap
#######################################################################

script_name=${0##*/}  # equivalent to basename $0

# required environment variables
env_vars[1]="LIB_DIR"
env_vars[2]="CACHE_DIR"
env_vars[3]="TMPDIR"
env_vars[4]="LOG_FILE"

# check environment variables
for env_var in ${env_vars[*]}; do
	eval "env_var_val=\${$env_var}"
	if [ -z "$env_var_val" ]; then
		echo "ERROR: $script_name requires env var $env_var" >&2
		exit 2
	fi
done

# required directories
dir_paths[1]="$LIB_DIR"
dir_paths[2]="$CACHE_DIR"
dir_paths[3]="$TMPDIR"

# check required directories
for dir_path in ${dir_paths[*]}; do
	if [ ! -d "$dir_path" ]; then
		echo "ERROR: $script_name: directory does not exist: $dir_path" >&2
		exit 2
	fi
done

# check the log file
# devices such as /dev/tty and /dev/null are allowed
if [ ! -f "$LOG_FILE" ] && [[ $LOG_FILE != /dev/* ]]; then
	echo "ERROR: $script_name: file does not exist: $LOG_FILE" >&2
	exit 2
fi

# default to INFO logging
if [ -z "$LOG_LEVEL" ]; then
	LOG_LEVEL=3
fi

# library filenames
lib_filenames[1]="core_lib.sh"
lib_filenames[2]="http_tools.sh"
lib_filenames[3]="compatible_date.sh"

# check lib files
for lib_filename in ${lib_filenames[*]}; do
	lib_file="$LIB_DIR/$lib_filename"
	if [ ! -f "$lib_file" ]; then
		echo "ERROR: $script_name: file does not exist: $lib_file" >&2
		exit 2
	fi
done

# XSLT script
xsl_filename="entities_timestamps_txt.xsl"

# check XSLT script
xsl_file="$LIB_DIR/$xsl_filename"
if [ ! -f "$xsl_file" ]; then
	echo "ERROR: $script_name: file does not exist: $xsl_file" >&2
	exit 2
fi

# output filename
out_filename="md_vital_statistics.json"

#######################################################################
# Process command-line options and arguments
#######################################################################

help_mode=false; local_opts=
while getopts ":hvd:" opt; do
	case $opt in
		h)
			help_mode=true
			;;
		v)
			LOG_LEVEL=4
			local_opts="$local_opts -$opt"
			;;
		d)
			out_dir="$OPTARG"
			;;
		\?)
			echo "ERROR: $script_name: Unrecognized option: -$OPTARG" >&2
			exit 2
			;;
		:)
			echo "ERROR: $script_name: Option -$OPTARG requires an argument" >&2
			exit 2
			;;
	esac
done

if $help_mode; then
	display_help
	exit 0
fi

# check the output directory
if [ -z "$out_dir" ]; then
	echo "ERROR: $script_name: no output directory specified (option -d)" >&2
	exit 2
fi
if [ ! -d "$out_dir" ]; then
	echo "ERROR: $script_name: directory does not exist: $out_dir" >&2
	exit 2
fi

# at least one metadata location is required
shift $(( OPTIND - 1 ))
if [ $# -lt 1 ]; then
	echo "ERROR: $script_name: wrong number of arguments: $# (at least 1 required)" >&2
	exit 2
fi
	
#######################################################################
# Initialization
#######################################################################

# source lib files
for lib_filename in ${lib_filenames[*]}; do
	lib_file="$LIB_DIR/$lib_filename"
	source "$lib_file"
	status_code=$?
	if [ $status_code -ne 0 ]; then
		echo "ERROR: $script_name failed ($status_code) to source lib file $lib_file" >&2
		exit 2
	fi
done

# create a temporary subdirectory
tmp_dir="${TMPDIR%%/}/${script_name%%.*}_$$"
/bin/mkdir "$tmp_dir"
status_code=$?
if [ $status_code -ne 0 ]; then
	echo "ERROR: $script_name failed ($status_code) to create tmp dir $tmp_dir" >&2
	exit 2
fi

# specify temporary files
xml_file="${tmp_dir}/saml-metadata.xml"
out_file="${tmp_dir}/$out_filename"
header_file="${tmp_dir}/resource-header.txt"

#######################################################################
# Functions
#######################################################################

escape_special_json_chars () {
	local str="$1"
	
	# backslash (\) and double quote (") are special
	echo "$str" | $_SED -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

append_json_object () {
	local message=$( escape_special_json_chars "$message" )
	local metadataLocation=$( escape_special_json_chars "$md_location" )
	local creationInstant=$( escape_special_json_chars "$creationInstant" )
	local last_modified=$( escape_special_json_chars "$last_modified" )
	local currentTime=$( escape_special_json_chars "$currentTime" )
	local validUntil=$( escape_special_json_chars "$validUntil" )
	local validityInterval=$( escape_special_json_chars "$validityInterval" )
	local sinceCreation=$( escape_special_json_chars "$sinceCreation" )
	local untilExpiration=$( escape_special_json_chars "$untilExpiration" )
	local betweenCreationAndModified=$( escape_special_json_chars "$betweenCreationAndModified" )

	local boolean_value="true"
	! $success && boolean_value="false"
	
	/bin/cat <<- JSON_OBJECT
	  {
	    "successFlag": $boolean_value,
	    "message": "$message",
	    "metadataLocation": "$metadataLocation",
	    "creationInstant": "$creationInstant",
	    "LastModified": "$last_modified",
	    "currentTime": "$currentTime",
	    "validUntil": "$validUntil",
	    "validityInterval": "$validityInterval",
	    "sinceCreation": "$sinceCreation",
	    "untilExpiration": "$untilExpiration",
	    "betweenCreationAndModified": "$betweenCreationAndModified"
	  }
JSON_OBJECT
}

init_global_vars () {
	
	# success by default
	success=true
	message="Metadata successfully parsed"
	
	metadataLocation=
	last_modified=
	currentTime=
	validUntil=
	creationInstant=
	validityInterval=
	untilExpiration=
	sinceCreation=
	betweenCreationAndModified=
}

get_cached_resource () {

	local status_code

	md_location="$1"
	
	# TODO: Check if cache up-to-date (conditional_get -I)

	# get a cached content file
	conditional_get $local_opts -C -d "$CACHE_DIR" -T "$tmp_dir" "$md_location" > "$xml_file"
	status_code=$?
	if [ $status_code -eq 1 ]; then
		# resource must be cached
		success=false
		message="Resource not found"
		print_log_message -E "$script_name: resource not cached: $md_location"
		return 1
	fi
	if [ $status_code -gt 1 ]; then
		success=false
		message="Lookup failed"
		print_log_message -E "$script_name: conditional_get failed ($status_code) on location: $md_location"
		return 3
	fi

	# get a cached header file
	conditional_get $local_opts -CI -d "$CACHE_DIR" -T "$tmp_dir" "$md_location" > "$header_file"
	status_code=$?
	if [ $status_code -eq 1 ]; then
		# resource must be cached
		success=false
		message="Resource not found"
		print_log_message -E "$script_name: resource not cached: $md_location"
		return 1
	fi
	if [ $status_code -gt 1 ]; then
		success=false
		message="Lookup failed"
		print_log_message -E "$script_name: conditional_get failed ($status_code) on location: $md_location"
		return 3
	fi

	return 0
}

parse_cached_content () {

	local status_code
	local tstamps
	local validityIntervalSecs
	local secsUntilExpiration
	local secsSinceCreation

	print_log_message -I "$script_name parsing cached metadata for resource: $md_location"

	# extract @ID, @creationInstant, @validUntil (in that order)
	tstamps=$( /usr/bin/xsltproc $xsl_file $xml_file )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Unable to parse metadata"
		print_log_message -E "$script_name: xsltproc failed ($status_code) on script: $xsl_file"
		return 0
	fi

	# get @validUntil
	validUntil=$( echo "$tstamps" | $_CUT -f3 )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Unable to parse @validUntil"
		print_log_message -E "$script_name: cut failed ($status_code) on validUntil"
		return 0
	fi

	# if @validUntil is missing, then FAIL
	if [ -z "$validUntil" ]; then
		success=false
		message="XML attribute @validUntil not found"
		print_log_message -E "$script_name: @validUntil not found"
		return 0
	fi
	print_log_message -D "$script_name found @validUntil: $validUntil"

	# get @creationInstant
	creationInstant=$( echo "$tstamps" | $_CUT -f2 )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Unable to parse @creationInstant"
		print_log_message -E "$script_name: cut failed ($status_code) on creationInstant"
		return 0
	fi

	# if @creationInstant is missing, then FAIL
	if [ -z "$creationInstant" ]; then
		success=false
		message="XML attribute @creationInstant not found"
		print_log_message -E "$script_name: @creationInstant not found"
		return 0
	fi
	print_log_message -D "$script_name found @creationInstant: $creationInstant"

	# compute length of the validityInterval (in secs)
	validityIntervalSecs=$( secsUntil -b $creationInstant $validUntil )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Unable to compute validity interval"
		print_log_message -E "$script_name: secsUntil failed ($status_code) on validityInterval"
		return 0
	fi

	# convert secs to duration
	validityInterval=$( secs2duration $validityIntervalSecs )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Unable to convert validity interval"
		print_log_message -E "$script_name: secs2duration failed ($status_code) on validityInterval"
		return 0
	fi
	print_log_message -D "$script_name computed validity interval: $validityInterval"

	# compute current dateTime
	currentTime=$( dateTime_now_canonical )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Unable to compute current time"
		print_log_message -E "$script_name: dateTime_now_canonical failed ($status_code) on currentTime"
		return 0
	fi
	print_log_message -D "$script_name computed current time: $currentTime"

	# compute secsUntilExpiration
	secsUntilExpiration=$( secsUntil -b $currentTime $validUntil )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Unable to compute time to expiration"
		print_log_message -E "$script_name: secsUntil failed ($status_code) on untilExpiration"
		return 0
	fi

	# convert secs to duration
	untilExpiration=$( secs2duration "$secsUntilExpiration" )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Unable to convert secs until expiration"
		print_log_message -E "$script_name: secs2duration failed ($status_code) on untilExpiration"
		return 0
	fi
	print_log_message -D "$script_name computed time until expiration: $untilExpiration"

	# compute secsSinceCreation
	secsSinceCreation=$( echo $creationInstant | secsSince -e $currentTime )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Unable to compute time since creation"
		print_log_message -E "$script_name: secsSince failed ($status_code) on sinceCreation"
		return 0
	fi

	# convert secs to duration
	sinceCreation=$( secs2duration "$secsSinceCreation" )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Unable to convert secs since creation"
		print_log_message -E "$script_name: secs2duration failed ($status_code) on sinceCreation"
		return 0
	fi
	print_log_message -D "$script_name computed time since creation: $sinceCreation"
	
	return 0
}

parse_cached_headers () {

	local header_name
	local status_code
	local last_modified_apache
	local betweenCreationAndModifiedSecs

	print_log_message -I "$script_name parsing cached header for resource: $md_location"

	# get the Last-Modified response header
	header_name=Last-Modified
	last_modified_apache=$( get_header_value $header_file $header_name )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		print_log_message -E "$script_name: get_header_value failed ($status_code) to parse response header: $header_name"
	fi

	# convert LastModified date to canonical format
	last_modified=$( dateTime_apache2canonical "$last_modified_apache" )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Unable to convert LastModified date"
		print_log_message -E "$script_name: dateTime_apache2canonical failed ($status_code) on last_modified"
		return 0
	fi
	print_log_message -D "$script_name computed LastModified date: $last_modified"
	
	# compute the length of time between @creationInstant and LastModified (in secs)
	betweenCreationAndModifiedSecs=$( secsUntil -b $creationInstant $last_modified )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Unable to compute deployment lag"
		print_log_message -E "$script_name: secsUntil failed ($status_code) on betweenCreationAndModified"
		return 0
	fi

	# convert secs to duration
	betweenCreationAndModified=$( secs2duration "$betweenCreationAndModifiedSecs" )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Unable to convert deployment lag tim"
		print_log_message -E "$script_name: secs2duration failed ($status_code) on betweenCreationAndModified"
		return 0
	fi
	print_log_message -D "$script_name computed time between @creationInstant and LastModified: $betweenCreationAndModified"

	return 0
}

print_output_file () {

	local status_code

	# begin output list
	printf "[\n"

	while true; do
	
		init_global_vars
		get_cached_resource "$1"
		status_code=$?
		if [ $status_code -eq 0 ]; then
			parse_cached_content
			parse_cached_headers
		fi
		append_json_object
		
		shift; (( "$#" )) || break
		
		# print comma separator
		printf "  ,\n"
	done

	# end output list
	printf "]\n"
}

#######################################################################
# Main processing
#######################################################################

print_log_message -I "$script_name BEGIN"

# create the JSON output
print_output_file "$@" > "$out_file"
print_log_message -I "$script_name writing output file: $out_filename"

# move the output file to the web directory
print_log_message -I "$script_name moving output file to dir: $out_dir"
/bin/mv "$out_file" $out_dir
status_code=$?
if [ $status_code -ne 0 ]; then
	print_log_message -E "$script_name: mv failed ($status_code) to dir: $out_dir"
    clean_up_and_exit -d "$tmp_dir" $status_code
fi

print_log_message -I "$script_name END"
clean_up_and_exit -d "$tmp_dir" 0
