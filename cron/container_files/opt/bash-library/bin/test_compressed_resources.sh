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
	This script tests one or more resources for HTTP Compression
	by requesting a compressed response just-in-time. The compressed 
	response is compared to a cached response, which is assumed to 
	be uncompressed.
	
	Usage: ${0##*/} [-hv] -d OUT_DIR LOCATION ...
	
	The script takes one or more HTTP locations on the command line. 
	Each location is tested for HTTP Compression. The script produces 
	a JSON array, with one array element for each location. The 
	resulting JSON file is moved to the output directory specified 
	on the command line.
	
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
	except LOG_LEVEL, which defaults to LOG_LEVEL=3 (i.e. INFO).
	
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
	
	OUTPUT
	
	The script outputs a JSON file to OUT_DIR:
	
	  $out_filename
	  
	The JSON file contains a single array. Each array element is 
	a JavaScript object with the following fields:
	
	  successFlag       boolean    success or failure?
	  message           string     message string
	  location          string     HTTP location
	  ResponseCode      string     HTTP response code
	  Date              string     HTTP response header
	  LastModified      string     HTTP response header
	  ETag              string     HTTP response header
	  ContentLength     string     HTTP response header
	  ContentType       string     HTTP response header
	  ContentEncoding   string     HTTP response header
	  
	For example:
	
	  {
	    "successFlag": true,
	    "message": "Integrity of compressed metadata confirmed",
	    "location": "http://md.incommon.org/InCommon/InCommon-metadata.xml",
	    "ResponseCode": "200",
	    "Date": "Fri, 09 Jun 2017 20:04:12 GMT",
	    "LastModified": "Fri, 09 Jun 2017 19:05:16 GMT",
	    "ETag": "\"80bbff-5518ba6585320\"",
	    "ContentLength": "8436735",
	    "ContentType": "application/samlmetadata+xml",
	    "ContentEncoding": "gzip"
	  }
	
	EXAMPLES
	
	  \$ ${0##*/} -h
	  \$ locations="http://md.incommon.org/InCommon/InCommon-metadata.xml
	  > http://md.incommon.org/InCommon/InCommon-metadata-export.xml"
	  \$ out_dir=/home/htdocs/www.incommonfederation.org/federation/metadata/
	  \$ ${0##*/} -d \$out_dir \$locations
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

# check lib files
for lib_filename in ${lib_filenames[*]}; do
	lib_file="$LIB_DIR/$lib_filename"
	if [ ! -f "$lib_file" ]; then
		echo "ERROR: $script_name: file does not exist: $lib_file" >&2
		exit 2
	fi
done

# output filename
out_filename="compressed_response_headers.json"

#######################################################################
# Process command-line options and arguments
#######################################################################

help_mode=false
local_opts=; curl_opts="--silent"
while getopts ":hvd:" opt; do
	case $opt in
		h)
			help_mode=true
			;;
		v)
			LOG_LEVEL=4
			local_opts="$local_opts -$opt"
			curl_opts="--verbose --progress-bar"
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
out_file="${tmp_dir}/$out_filename"
compressed_content="${tmp_dir}/compressed-resource-content.xml"
uncompressed_content="${tmp_dir}/uncompressed-resource-content.xml"
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
	local location=$( escape_special_json_chars "$location" )
	local response_code=$( escape_special_json_chars "$response_code" )
	local response_date=$( escape_special_json_chars "$response_date" )
	local last_modified=$( escape_special_json_chars "$last_modified" )
	local etag=$( escape_special_json_chars "$etag" )
	local content_length=$( escape_special_json_chars "$content_length" )
	local content_type=$( escape_special_json_chars "$content_type" )
	local content_encoding=$( escape_special_json_chars "$content_encoding" )

	local boolean_value="true"
	! $success && boolean_value="false"
	
	/bin/cat <<- JSON_OBJECT
	  {
	    "successFlag": $boolean_value,
	    "message": "$message",
	    "location": "$location",
	    "ResponseCode": "$response_code",
	    "Date": "$response_date",
	    "LastModified": "$last_modified",
	    "ETag": "$etag",
	    "ContentLength": "$content_length",
	    "ContentType": "$content_type",
	    "ContentEncoding": "$content_encoding"
	  }
JSON_OBJECT
}

init_global_vars () {
	
	# success by default
	success=true
	message="Integrity of compressed metadata confirmed"
	
	location=
	ResponseCode=
	Date=
	LastModified=
	ETag=
	ContentLength=
	ContentType=
	ContentEncoding=
}

get_compressed_response () {

	local status_code
	local response_code

	location="$1"

	# get the uncompressed resource header
	conditional_get $local_opts -I -d "$CACHE_DIR" -T "$tmp_dir" "$location" > "$header_file"
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Request for uncompressed resource failed"
		print_log_message -E "$script_name: conditional_get failed ($status_code) on location: $location"
		return 3
	fi

	# get and test the HTTP response code
	response_code=$( get_response_code $header_file )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Response code unknown"
		print_log_message -E "$script_name: unknown response_code on resource: $location"
		return 3
	fi
	if [ "$response_code" -ne 304 ]; then
		success=false
		message="Unexpected response code: $response_code"
		print_log_message -E "$script_name: unexpected response ($response_code) on resource: $location"
		return 3
	fi
	print_log_message -I "$script_name successfully requested (uncompressed) resource: $location"

	# get the compressed resource
	print_log_message -I "$script_name requesting cached and compressed resource: $location"
	/usr/bin/curl $curl_opts --compressed --dump-header $header_file $location > $compressed_content
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Request for compressed content failed"
		print_log_message -E "$script_name: curl failed ($status_code) on resource: $location"
		return 3
	fi
	
	return 0
}

parse_compressed_response () {

	local header_name
	local status_code

	# get the HTTP response code
	response_code=$( get_response_code $header_file )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		print_log_message -E "$script_name: get_response_code failed ($status_code) to parse response code"
	fi

	# get the Date response header
	header_name=Date
	response_date=$( get_header_value $header_file $header_name )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		print_log_message -E "$script_name: get_header_value failed ($status_code) to parse response header: $header_name"
	fi

	# get the Last-Modified response header
	header_name=Last-Modified
	last_modified=$( get_header_value $header_file $header_name )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		print_log_message -E "$script_name: get_header_value failed ($status_code) to parse response header: $header_name"
	fi

	# get the ETag response header
	header_name=ETag
	etag=$( get_header_value $header_file $header_name )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		print_log_message -E "$script_name: get_header_value failed ($status_code) to parse response header: $header_name"
	fi

	# get the Content-Length response header
	header_name=Content-Length
	content_length=$( get_header_value $header_file $header_name )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		print_log_message -E "$script_name: get_header_value failed ($status_code) to parse response header: $header_name"
	fi

	# get the Content-Type response header
	header_name=Content-Type
	content_type=$( get_header_value $header_file $header_name )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		print_log_message -E "$script_name: get_header_value failed ($status_code) to parse response header: $header_name"
	fi

	# get the Content-Encoding response header
	header_name=Content-Encoding
	content_encoding=$( get_header_value $header_file $header_name )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		print_log_message -E "$script_name: get_header_value failed ($status_code) to parse response header: $header_name"
	fi
	
	return 0
}

test_compressed_response () {

	local status_code

	# was the response actually compressed?
	if [ "$response_code" -ne 200 ]; then
		success=false
		message="Unexpected response code: $response_code"
		print_log_message -E "$script_name: unexpected response ($response_code) on resource: $location"
		return 0
	elif [ -z "$content_encoding" ]; then
		success=false
		message="Content-Encoding response header not found"
		print_log_message -E "$script_name: Content-Encoding response header not found"
		return 0
	fi

	# TODO: Check the cached resource for Content-Encoding response header
	
	# get the cached resource
	conditional_get $local_opts -C -d "$CACHE_DIR" -T "$tmp_dir" "$location" > "$uncompressed_content"
	status_code=$?
	if [ $status_code -eq 1 ]; then
		# metadata must be cached
		success=false
		message="Uncompressed content not found"
		print_log_message -E "$script_name: metadata file not cached: $location"
		return 0
	fi
	if [ $status_code -gt 1 ]; then
		success=false
		message="Request for uncompressed content failed"
		print_log_message -E "$script_name: conditional_get failed ($status_code) on location: $location"
		return 0
	fi

	# compare the compressed and uncompressed content
	print_log_message -D "$script_name comparing compressed and uncompressed content"
	/usr/bin/diff -q $compressed_content $uncompressed_content
	status_code=$?
	if [ $status_code -ne 0 ]; then
		success=false
		message="Integrity of compressed metadata NOT confirmed"
		print_log_message -C "$script_name: diff failed ($status_code) on resource: $location"
		return 0
	fi
	print_log_message -D "$script_name: compressed and uncompressed resources are identical"
	
	return 0
}

print_output_file () {

	local status_code

	# begin output list
	printf "[\n"

	while true; do
	
		init_global_vars
		get_compressed_response "$1"
		status_code=$?
		if [ $status_code -eq 0 ]; then
			parse_compressed_response
			test_compressed_response
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
