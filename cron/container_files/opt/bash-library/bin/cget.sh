#!/bin/bash

#######################################################################
# Copyright 2016--2017 Internet2
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
	This script retrieves and caches HTTP resources on disk. 
	A previously cached resource is retrieved via HTTP Conditional 
	GET [RFC 7232]. If the web server responds with HTTP 200 OK,
	the new resource is cached and written to stdout. If the web 
	server responds with 304 Not Modified, the cached resource 
	is output instead.
	
	Usage: ${0##*/} [-hvqFCIx] URL
	
	This script takes a single command-line argument. The URL 
	argument is the absolute URL of an HTTP resource. The script 
	requests the resource at the given URL using the curl 
	command-line tool.
	
	Options:
	   -h      Display this help message
	   -v      Log verbose messages
	   -q      Log no messages other than warnings or errors
	   -F      Enable "Fresh Content Mode"
	   -C      Enable "Cache Only Mode"
	   -I      Enable "Header Only Mode"
	   -x      Enable "Compressed Mode"

	Option -h is mutually exclusive of all other options.
	
	The default behavior of the script is modified by using 
	option -F, -C, or -I. Options -F and -C are mutually exclusive 
	of each other. Option -I may be used with option -C (but not 
	with option -F).
	
	Fresh Content Mode (option -F) forces the return of a fresh resource. 
	The resource is output on stdout if and only if the server responds 
	with 200. If the response is 304, the script silently fails with 
	status code 1.
	 
	Cache Only Mode (option -C) bypasses the GET request altogether 
	and goes directly to cache. If the resource resides in cache, 
	it is output on stdout, otherwise the script silently fails
	with exit code 1.
	
	Header Only Mode (option -I) issues a HEAD request instead of a GET 
	request, in which case, only the response headers are returned in the 
	output. Note that nothing is written to cache when option -I is used.
	
	Compressed Mode (option -x) enables HTTP Compression by adding an 
	Accept-Encoding header to the request; that is, if option -x is 
	enabled, the client merely indicates its support for HTTP Compression 
	in the request. The server may or may not compress the response.
	
	Important! This implementation treats compressed and uncompressed 
	requests for the same resource as two distinct resources.
	
	ENVIRONMENT
	
	This script leverages a handful of environment variables:
	
	  LIB_DIR    A source library directory
	  CACHE_DIR  A persistent HTTP cache
	  TMPDIR     A temporary directory
	  LOG_FILE   A persistent log file
	  LOG_LEVEL  The global log level [0..5]
	
	All of the above environment variables are REQUIRED
	except LOG_LEVEL, which defaults to LOG_LEVEL=3.
	
	LIBRARY
	
	Environment variable LIB_DIR specifies a directory containing at
	least the following library files, which act as helper scripts for 
	${0##*/}:

	$LIB_FILENAMES

	EXAMPLES
	
	  \$ url=http://md.incommon.org/InCommon/InCommon-metadata.xml
	  \$ ${0##*/} \$url      # Retrieve the resource using HTTP conditional GET
	  \$ ${0##*/} -F \$url   # Enable Fresh Content Mode
	  \$ ${0##*/} -C \$url   # Enable Cache Only Mode
	  \$ ${0##*/} -x \$url   # Enable Compressed Mode
	  
	Note that the first and last examples result in distinct cached
	resources. The content of a compressed resource will be the 
	same as the content of an uncompressed resource but the headers 
	will be different. In particular, a compressed header will include
	a Content-Encoding header.
HELP_MSG
}

#######################################################################
# Bootstrap
#######################################################################

script_name=${0##*/}  # equivalent to basename $0

# required directories
env_vars="LIB_DIR
CACHE_DIR
TMPDIR"

# check required directories
for env_var in $env_vars; do
	eval "env_var_val=\${$env_var}"
	if [ -z "$env_var_val" ]; then
		echo "ERROR: $script_name requires env var $env_var" >&2
		exit 2
	fi
	if [ ! -d "$env_var_val" ]; then
		echo "ERROR: $script_name: directory does not exist: $env_var_val" >&2
		exit 2
	fi
done

# check the log file
if [ -z "$LOG_FILE" ]; then
	echo "ERROR: $script_name requires env var LOG_FILE" >&2
	exit 2
fi
# devices such as /dev/tty and /dev/null are allowed
if [ ! -f "$LOG_FILE" ] && [[ $LOG_FILE != /dev/* ]]; then
	echo "ERROR: $script_name: file does not exist: $LOG_FILE" >&2
	exit 2
fi

# default to INFO logging
if [ -z "$LOG_LEVEL" ]; then
	LOG_LEVEL=3
fi

# library filenames (always list core_lib first)
LIB_FILENAMES="core_lib.sh
http_tools.sh"

#######################################################################
# Process command-line options and arguments
#######################################################################

help_mode=false; local_opts=
while getopts ":hvqFCIx" opt; do
	case $opt in
		h)
			help_mode=true
			;;
		v)
			LOG_LEVEL=4
			local_opts="$local_opts -$opt"
			;;
		q)
			LOG_LEVEL=2
			;;
		F)
			local_opts="$local_opts -$opt"
			;;
		C)
			local_opts="$local_opts -$opt"
			;;
		I)
			local_opts="$local_opts -$opt"
			;;
		x)
			local_opts="$local_opts -$opt"
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

# determine the location of the web resource
shift $(( OPTIND - 1 ))
if [ $# -ne 1 ]; then
	echo "ERROR: $script_name: wrong number of arguments: $# (1 required)" >&2
	exit 2
fi
location="$1"

#######################################################################
# Initialization
#######################################################################

# source lib files
for lib_filename in $LIB_FILENAMES; do
	lib_file="$LIB_DIR/$lib_filename"
	if [ ! -f "$lib_file" ]; then
		echo "ERROR: $script_name: lib file does not exist: $lib_file" >&2
		exit 2
	fi
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

# temporary file
tmp_file="${tmp_dir}/http_resource"

#######################################################################
# Main processing
#######################################################################

# Functions print_log_message and clean_up_and_exit are defined in core_lib.sh
# Function conditional_get is defined in http_tools.sh

# get the resource
print_log_message -I "$script_name requesting resource: $location"
conditional_get $local_opts -d "$CACHE_DIR" -T "$tmp_dir" "$location" > "$tmp_file"
status_code=$?
if [ $status_code -ne 0 ]; then
	if [ $status_code -gt 1 ]; then
		print_log_message -E "$script_name failed ($status_code) on location: $location"
	fi
	clean_up_and_exit -d "$tmp_dir" $status_code
fi

# output the resource
/bin/cat "$tmp_file"
status_code=$?
if [ $status_code -ne 0 ]; then
	print_log_message -E "$script_name: cat failed ($status_code)"
	clean_up_and_exit -d "$tmp_dir" $status_code
fi

clean_up_and_exit -d "$tmp_dir" 0
