#!/bin/bash

#######################################################################
# Copyright 2013--2017 Internet2
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
#
# Given a web resource and a local cache, if the resource is cached, 
# request the resource using HTTP Conditional GET [RFC 7232], otherwise 
# issue an ordinary GET request for the resource. In either case, if 
# the server responds with 200, cache the resource and return the 
# response body. If the server responds with 304, return the cached 
# response body instead.
#
# Usage: conditional_get [-vFCcx] -d CACHE_DIR -T TMP_DIR HTTP_LOCATION
#
# This function requires two option arguments (CACHE_DIR and TMP_DIR)
# and a command-line argument (HTTP_LOCATION). The rest of the command
# line is optional.
#
# Options:
#   -v   verbose mode
#   -F   force cache update
#   -C   check cache freshness
#   -c   cache-only mode (no network)
#   -x   enable HTTP Compression
#   -d   the cache directory (REQUIRED)
#   -T   a temporary directory (REQUIRED)
#
# Options -F, -C, and -c are mutually exclusive of each other. 
# Options -v and -x may be used with any other option.
#
# Option -F forces the output of fresh content, that is, if option -F 
# is enabled and the server responds with 200, the function returns 
# normally. In that case, a cache write will occur. On the other hand,
# if option -F is enabled and the server responds with 304, the function
# quietly returns with a nonzero return code. See Quiet Failure Mode
# below.
#
# Option -C outputs cached content but only if the cache is up-to-date.
# An HTTP request is issued to determine if the cache content is stale.
# If the resource is not cached or the cache is not up-to-date, the 
# function quietly returns with a nonzero return code (i.e., Quiet
# Failure Mode).
#
# Option -c outputs cached content whether or not the cache is up-to-date.
# (Since no HTTP request is issued, this option is useful in offline mode.)
# If the resource is not cached, the function quietly returns with a 
# nonzero return code (i.e., Quiet Failure Mode).
#
# QUIET FAILURE MODE
#
# Options -F, -C, and -c exhibit Quiet Failure Mode. If one of these 
# mutually exclusive options is enabled, and a special error condition
# is detected, the function quietly returns error code 1 without emitting
# an error message of any kind.
#
# The error conditions that trigger Quiet Failure Mode are based on the
# following requirements:
#
#   Option -F: the HTTP response MUST be 200
#   Option -C: the HTTP response MUST be 304
#   Option -c: the resource MUST be cached
#
# If one of the above requirements is NOT met, the function quietly
# returns error code 1.
#
# Quiet Failure Mode guarantees the following:
#
#   Option -F: the cache has been updated (i.e., a cache write occurred)
#   Option -C: the resource is cached and the cache is up-to-date
#   Option -c: the resource is cached
#
# Note that options -C and -c do not write to cache in any case.
#
# HTTP COMPRESSION
#
# Option -x adds an Accept-Encoding header to the request; that is, if
# option -x is enabled, the client merely indicates its support for HTTP 
# Compression in the request. The server may or may not compress the 
# response, and in fact, this implementation does not check to see if
# the response compressed by the server. The HTTP response header will
# indicate if this is so.
#
# Important! This implementation treats compressed and uncompressed 
# requests for the same resource as two distinct resources. For example, 
# consider the following pair of function calls:
#
#   conditional_get ... $url
#   conditional_get -x ... $url
#
# The above requests result in two distinct cached resources, the content
# of which are identical. Assuming the server actually compressed the
# response of the latter, the headers will be different, however. In 
# particular, the Content-Length values will be different in each case. 
# Most importantly, the compressed response header will include a 
# Content-Encoding header (whose value is invariably "gzip").
#
# OUTPUT
#
# The output of the curl command-line tool is stored in the following 
# temporary files:
#
#   $TMP_DIR/conditional_get_curl_headers
#   $TMP_DIR/conditional_get_curl_content
#   $TMP_DIR/conditional_get_curl_stderr
#
# DEPENDENCIES
#
# This function requires the following library file:
#
# core_lib.sh
#
# The library file must be sourced BEFORE calling this function.
#
# RETURN CODES
#
#    0: success
#    1: Quiet Failure Mode:
#       option -F but no fresh resource available
#       option -C but no up-to-date cached resource available
#       option -c but no cached resource available
#    2: initialization failure
#    3: unspecified failure
#    4: hash operation failed
#    5: curl failed
#    6: call to get_header_value failed
#    7: call to get_response_code failed
#    8: copy to cache failed
#    9: unexpected HTTP response
#
#######################################################################

conditional_get () {

	if [ "$_COMPATIBILITY_MODE" != true ]; then
		echo "ERROR: $FUNCNAME: compatibility mode not enabled" >&2
		return 2
	fi
	
	# external dependency
	if [ "$(type -t print_log_message)" != function ]; then
		echo "ERROR: $FUNCNAME: function print_log_message not found" >&2
		return 2
	fi

	local script_version="1.0"
	local user_agent_string="HTTP Conditional GET client $script_version"
	
	local hash
	local exit_code
	local return_code
	local cached_header_file
	local cached_content_file
	local conditional_get_mode
	local tmp_header_file
	local tmp_content_file
	local tmp_stderr_file
	local curl_opts
	local adjective
	local do_conditional_get
	local header_value
	local cmd
	local response_code
	local declared_content_length
	local actual_content_length

	local verbose_mode=false
	local force_refresh_mode=false
	local check_cache_mode=false
	local cache_only_mode=false
	local compressed_mode=false
	local cache_dir
	local tmp_dir
	local location
	
	# an undocumented feature
	# 'conditional_get -I' === 'conditional_head'
	# (the -I notation was borrowed from curl)
	local conditional_head_mode=false

	local opt
	local OPTARG
	local OPTIND
	while getopts ":vIFCcxd:T:" opt; do
		case $opt in
			v)
				verbose_mode=true
				;;
			I)
				if $force_refresh_mode; then
					echo "ERROR: $FUNCNAME: options -I and -F may not be used together" >&2
					return 2
				fi
				conditional_head_mode=true
				;;
			F)
				if $conditional_head_mode; then
					echo "ERROR: $FUNCNAME: options -F and -I may not be used together" >&2
					return 2
				fi
				if $check_cache_mode; then
					echo "ERROR: $FUNCNAME: options -F and -C may not be used together" >&2
					return 2
				fi
				if $cache_only_mode; then
					echo "ERROR: $FUNCNAME: options -F and -c may not be used together" >&2
					return 2
				fi
				force_refresh_mode=true
				;;
			C)
				if $force_refresh_mode; then
					echo "ERROR: $FUNCNAME: options -C and -F may not be used together" >&2
					return 2
				fi
				if $cache_only_mode; then
					echo "ERROR: $FUNCNAME: options -C and -c may not be used together" >&2
					return 2
				fi
				check_cache_mode=true
				;;
			c)
				if $force_refresh_mode; then
					echo "ERROR: $FUNCNAME: options -c and -F may not be used together" >&2
					return 2
				fi
				if $check_cache_mode; then
					echo "ERROR: $FUNCNAME: options -c and -C may not be used together" >&2
					return 2
				fi
				cache_only_mode=true
				;;
			x)
				compressed_mode=true
				;;
			d)
				cache_dir="$OPTARG"
				;;
			T)
				tmp_dir="$OPTARG"
				;;
			\?)
				echo "ERROR: $FUNCNAME: Unrecognized option: -$OPTARG" >&2
				return 2
				;;
			:)
				echo "ERROR: $FUNCNAME: Option -$OPTARG requires an argument" >&2
				return 2
				;;
		esac
	done
	
	# a temporary directory is required
	if [ -z "$tmp_dir" ]; then
		echo "ERROR: $FUNCNAME: no temporary directory specified" >&2
		return 2
	fi
	if [ ! -d "$tmp_dir" ]; then
		echo "ERROR: $FUNCNAME: directory does not exist: $tmp_dir" >&2
		return 2
	fi
	print_log_message -D "$FUNCNAME using temporary directory $tmp_dir"

	# a cache directory is required
	if [ -z "$cache_dir" ]; then
		echo "ERROR: $FUNCNAME: no cache directory specified" >&2
		return 2
	fi
	if [ ! -d "$cache_dir" ]; then
		echo "ERROR: $FUNCNAME: directory does not exist: $cache_dir" >&2
		return 2
	fi
	print_log_message -D "$FUNCNAME using cache directory $cache_dir"

	# determine the URL location
	shift $(( OPTIND - 1 ))
	if [ $# -ne 1 ]; then
		echo "ERROR: $FUNCNAME: wrong number of arguments: $# (1 required)" >&2
		return 2
	fi
	location="$1"
	if [ -z "$location" ] ; then
		echo "ERROR: $FUNCNAME: empty URL argument" >&2
		return 2
	fi
	print_log_message -D "$FUNCNAME using location $location"
	
	#######################################################################
	#
	# Determine the cache files (which may or may not exist at this point)
	#
	# This cache implementation uses separate files for the header and
	# body content. It also uses a separate pair of files if option -x
	# (i.e., HTTP Compression) is specified on the command line.
	#
	# Open Questions
	#   Does it make sense to cache a single file instead?
	#   Should we use SHA-1 instead of MD5?
	#
	#######################################################################

	hash=$( echo -n "$location" \
		| /usr/bin/openssl dgst -md5 -hex \
		| $_CUT -d' ' -f2
	)
	exit_code=$?
	if [ $exit_code -ne 0 ]; then
		print_log_message -E "$FUNCNAME failed to hash the location URL (exit code: $exit_code)"
		return 4
	fi

	# use distinct cache filenames for compressed mode
	if $compressed_mode; then
		cached_header_file="$cache_dir/${hash}_headers_compressed"
		cached_content_file="$cache_dir/${hash}_content_compressed"
		adjective="compressed "
	else
		cached_header_file="$cache_dir/${hash}_headers"
		cached_content_file="$cache_dir/${hash}_content"
		adjective=
	fi

	print_log_message -D "$FUNCNAME using cached header file: $cached_header_file"
	print_log_message -D "$FUNCNAME using cached content file: $cached_content_file"

	# check if the resource is cached
	if [ -f "$cached_header_file" ] && [ -f "$cached_content_file" ]; then
	
		# read from cache without checking resource freshness
		if $cache_only_mode; then
			if $conditional_head_mode; then
				print_log_message -I "$FUNCNAME reading cached header file: $cached_header_file"
				/bin/cat "$cached_header_file"
			else
				print_log_message -I "$FUNCNAME reading cached content file: $cached_content_file"
				/bin/cat "$cached_content_file"
			fi
			exit_code=$?
			if [ $exit_code -ne 0 ]; then
				print_log_message -E "$FUNCNAME unable to cat output ($exit_code)"
				return 3
			fi
			return 0
		fi
		
		conditional_get_mode=true
	else
		# ensure cache integrity
		/bin/rm -f "$cached_header_file" "$cached_content_file" >&2
		
		# quiet failure mode
		if $cache_only_mode || $check_cache_mode; then
			print_log_message -W "$FUNCNAME: ${adjective}resource not cached: $location"
			return 1
		fi
		
		conditional_get_mode=false
	fi

	#######################################################################
	#
	# Initialization
	#
	#######################################################################

	tmp_header_file="$tmp_dir/${FUNCNAME}_curl_headers"
	tmp_content_file="$tmp_dir/${FUNCNAME}_curl_content"
	tmp_stderr_file="$tmp_dir/${FUNCNAME}_curl_stderr"

	print_log_message -D "$FUNCNAME using temp header file: ${tmp_header_file}"
	print_log_message -D "$FUNCNAME using temp content file: ${tmp_content_file}"
	print_log_message -D "$FUNCNAME using temp stderr file: ${tmp_stderr_file}"

	#######################################################################
	#
	# Issue a GET request for the web resource
	# If option -I was used, issue HEAD request instead
	#
	# This implementation issues an conditional request
	# (GET or HEAD) iff the resource is cached.
	#
	#######################################################################

	# init curl command-line options
	if $verbose_mode; then
		curl_opts="--verbose --progress-bar"
	else
		curl_opts="--silent --show-error"
	fi
	curl_opts="${curl_opts} --user-agent '${user_agent_string}'"
	
	# set curl --compressed option if necessary
	$compressed_mode && curl_opts="${curl_opts} --compressed"

	# always capture the header in a file
	curl_opts="${curl_opts} --dump-header '${tmp_header_file}'"
	
	# capture the output iff the client issues a GET request
	if $conditional_head_mode; then
		print_log_message -I "$FUNCNAME issuing HEAD request for ${adjective}resource: $location"
		curl_opts="${curl_opts} --head"
		curl_opts="${curl_opts} --output '/dev/null'"
	else
		print_log_message -I "$FUNCNAME issuing GET request for ${adjective}resource: $location"
		curl_opts="${curl_opts} --output '${tmp_content_file}'"
	fi

	# always capture stderr in a file
	curl_opts="${curl_opts} --stderr '${tmp_stderr_file}'"

	# If the resource is cached, issue a conditional request.
	# Since "A recipient MUST ignore If-Modified-Since if the 
	# request contains an If-None-Match header field," the
	# latter takes precedence in the following code block.
	do_conditional_get=false
	if $conditional_get_mode; then
		header_value=$( get_header_value "$cached_header_file" 'ETag' )
		return_code=$?
		if [ $return_code -ne 0 ]; then
			print_log_message -E "$FUNCNAME: get_header_value (return code: $return_code)"
			return 6
		fi
		if [ -n "$header_value" ]; then
			do_conditional_get=true
			curl_opts="${curl_opts} --header 'If-None-Match: $header_value'"
		else
			header_value=$( get_header_value "$cached_header_file" 'Last-Modified' )
			return_code=$?
			if [ $return_code -ne 0 ]; then
				print_log_message -E "$FUNCNAME: get_header_value (return code: $return_code)"
				return 6
			fi
			if [ -n "$header_value" ]; then
				do_conditional_get=true
				curl_opts="${curl_opts} --header 'If-Modified-Since: $header_value'"
			fi
		fi
	fi

	# invoke curl
	cmd="/usr/bin/curl $curl_opts $location"
	print_log_message -D "$FUNCNAME issuing curl command: $cmd"
	eval $cmd
	exit_code=$?
	if [ $exit_code -ne 0 ]; then
		print_log_message -E "$FUNCNAME: curl failed (exit code: $exit_code)"
		return 5
	fi

	#######################################################################
	#
	# Response processing
	#
	#######################################################################

	# sanity check
	if [ ! -f "$tmp_header_file" ]; then
		print_log_message -E "$FUNCNAME unable to find header file $tmp_header_file"
		return 3
	fi

	response_code=$( get_response_code "$tmp_header_file" )
	return_code=$?
	if [ $return_code -ne 0 ]; then
		print_log_message -E "$FUNCNAME: get_response_code failed (return code: $return_code)"
		return 7
	fi
	print_log_message -I "$FUNCNAME received response code: $response_code"

	# output the header received from the server
 	if $conditional_head_mode && ! $check_cache_mode; then
 		/bin/cat "$tmp_header_file"
 		exit_code=$?
 		if [ $exit_code -ne 0 ]; then
 			print_log_message -E "$FUNCNAME unable to cat output ($exit_code)"
 			return 3
 		fi
 		return 0
 	fi

	#######################################################################
	#
	# Update the cache
	#
	# Open questions:
	#   What if the response contains a "no-store" cache directive?
	#   If Check Cache Mode is enabled but the response is 200,
	#   should the cache be refreshed as a side effect?
	#   (for now the answer is no)
	#
	#######################################################################

	if [ "$response_code" = "200" ]; then

		# quiet failure mode
		if $check_cache_mode; then
			print_log_message -W "$FUNCNAME: ${adjective}resource is not up-to-date: $location"
			return 1
		fi
		
		# compute the length of the downloaded content
		actual_content_length=$( /bin/cat "$tmp_content_file" \
			| /usr/bin/wc -c \
			| $_SED -e 's/^[ ]*//' -e 's/[ ]*$//'
		)
		return_code=$?
		if [ $return_code -ne 0 ]; then
			print_log_message -E "$FUNCNAME: length calculation failed (return code: $return_code)"
			return 3
		fi
		print_log_message -D "$FUNCNAME downloaded ${actual_content_length} bytes"

		# this sanity check is applied only if option -x was NOT used
		if ! $compressed_mode; then
			declared_content_length=$( get_header_value "$tmp_header_file" 'Content-Length' )
			return_code=$?
			if [ $return_code -ne 0 ]; then
				print_log_message -E "$FUNCNAME: get_header_value failed (return code: $return_code)"
				return 6
			fi
			if [ -n "$declared_content_length" ]; then
				if [ "$declared_content_length" != "$actual_content_length" ]; then
					print_log_message -E "$FUNCNAME failed content length check"
					return 3
				fi
			else
				print_log_message -W "$FUNCNAME: Content-Length response header missing"
			fi
		fi

		if $do_conditional_get; then
			print_log_message -D "$FUNCNAME refreshing cache files"
		else
			print_log_message -D "$FUNCNAME initializing cache files"
		fi

		# update the cache; maintain cache integrity at all times
		/bin/cp -f "$tmp_header_file" "$cached_header_file" >&2
		exit_code=$?
		if [ $exit_code -ne 0 ]; then
			/bin/rm -f "$cached_header_file" "$cached_content_file" >&2
			print_log_message -E "$FUNCNAME failed copy to file $cached_header_file (exit code: $exit_code)"
			return 8
		fi
		print_log_message -I "$FUNCNAME writing cached content file: ${cached_content_file}"
		/bin/cp -f "$tmp_content_file" "$cached_content_file" >&2
		exit_code=$?
		if [ $exit_code -ne 0 ]; then
			/bin/rm -f "$cached_header_file" "$cached_content_file" >&2
			print_log_message -E "$FUNCNAME failed copy to file $cached_content_file (exit code: $exit_code)"
			return 8
		fi

	elif [ "$response_code" = "304" ]; then
	
		# quiet failure mode
		if $force_refresh_mode; then
			print_log_message -W "$FUNCNAME: fresh resource not available: $location"
			return 1
		fi
		
		print_log_message -D "$FUNCNAME downloaded 0 bytes (cache is up-to-date)"
	else
		print_log_message -E "$FUNCNAME failed with HTTP response code $response_code"
		return 9
	fi

	#######################################################################
	#
	# Return the cached resource
	# (since the cache is now up-to-date)
	#
	#######################################################################

	if $conditional_head_mode; then
		print_log_message -I "$FUNCNAME reading cached header file: $cached_header_file"
		/bin/cat "$cached_header_file"
	else
		print_log_message -I "$FUNCNAME reading cached content file: $cached_content_file"
		/bin/cat "$cached_content_file"
	fi
	exit_code=$?
	if [ $exit_code -ne 0 ]; then
		print_log_message -E "$FUNCNAME unable to cat output ($exit_code)"
		return 3
	fi
	return 0
}

#######################################################################
#
# This function is analogous to the conditional_get function except
# that this function issues a HEAD request instead of a GET request.
# Consequently, this function always outputs the HTTP header, not
# the response body.
#
# Usage: conditional_head [-vCcx] -d CACHE_DIR -T TMP_DIR HTTP_LOCATION
#
# Note that the command-line options and arguments are similar to
# those of the conditional_get function. The only difference is that
# option -F is not allowed since it effectively forces a cache write.
# For details about available options, see the documentation for the
# conditional_get function.
#
# IMPORTANNT! This function may read the header from cache (depending
# on options) but it NEVER writes to cache.
#
# With no options, this function sends a conditional HEAD request to
# the server and outputs the header received from the server on stdout.
# The response code will be either 200 or 304. In either case, the
# cache is not accessed.
#
# Option -C causes the function to read the header from cache. The
# cached header is output on stdout if (and only if) the cache is
# up-to-date. If the resource is not cached or the cache is not
# up-to-date, the function quietly returns error code 1. This is
# called Quiet Error Mode. See the documentation for the
# conditional_get function for details.
#
# To determine if the cache is up-to-date, the client sends a
# conditional HEAD request to the server. The cache is up-to-date
# if (and only if) the server responds with 304.
#
# Note that the cached header (if it exists) will always indicate
# a 200 response since a 304 response is never cached.
#
# Option -c reads the header directly from cache and outputs the
# cached header on stdout. If the resource is not cached, the
# function quietly returns error code 1 (i.e., Quiet Error Mode).
# Note that no network access is required if option -c is used.
#
# Option -x adds an Accept-Encoding header to the HEAD request,
# that is, when option -x is enabled, the client merely indicates
# its support for HTTP Compression in the request. The server may
# or may not indicate compression in the response header.
#
#######################################################################

conditional_head () {
	conditional_get -I "$@"
}

#######################################################################
#
# This function takes a file containing an HTTP response header and  
# returns the HTTP response code.
#
# Usage: get_response_code FILE
#
# This function requires the following library files:
#
# core_lib.sh
#
# These library files must be sourced BEFORE calling this function.
#
#######################################################################

get_response_code () {

	if [ "$_COMPATIBILITY_MODE" != true ]; then
		echo "ERROR: $FUNCNAME: compatibility mode not enabled" >&2
		return 2
	fi
	
	# check the number of arguments
	if [ $# -ne 1 ]; then
		echo "ERROR: incorrect number of arguments: $# (1 required)" >&2
		return 2
	fi
	
	# make sure the file exists
	if [ ! -f "$1" ]; then
		echo "ERROR: file does not exist: $1" >&2
		return 2
	fi
	
	# extract the response code from the header
	/bin/cat "$1" \
		| /usr/bin/head -1 \
		| $_SED -e 's/^[^ ]* \([^ ]*\) .*$/\1/'
		
	return 0
}

#######################################################################
#
# This function takes a file containing an HTTP response header and
# a header name, and then returns the header value (if any).
#
# Usage: get_header_value FILE HEADER_NAME
#
# This function requires the following library files:
#
# core_lib.sh
#
# These library files must be sourced BEFORE calling this function.
#
#######################################################################

get_header_value () {

	if [ "$_COMPATIBILITY_MODE" != true ]; then
		echo "ERROR: $FUNCNAME: compatibility mode not enabled" >&2
		return 2
	fi
	
	# check the number of arguments
	if [ $# -ne 2 ]; then
		echo "ERROR: incorrect number of arguments: $# (2 required)" >&2
		return 2
	fi
	
	# make sure the file exists
	if [ ! -f "$1" ]; then
		echo "ERROR: file does not exist: $1" >&2
		return 2
	fi
	
	# extract the desired value from the header
#	/bin/cat "$1" \
#		| $_GREP -F "$2" \
#		| /usr/bin/tr -d "\r" \
#		| $_SED -e 's/^[^:]*: [ ]*//' -e 's/[ ]*$//'
	/bin/cat "$1" \
		| $_GREP "^$2:" \
		| $_SEDEXT -e 's/^[^:]+:[[:space:]]+//' \
		| $_SEDEXT -e 's/[[:space:]]*$//'
		
	return 0
}

#######################################################################
# This function percent-encodes all characters in its string argument
# except the "Unreserved Characters" defined in section 2.3 of RFC 3986.
#
# See: https://gist.github.com/cdown/1163649
#      https://en.wikipedia.org/wiki/Percent-encoding
#######################################################################
percent_encode () {
    # percent_encode <string>
	
	# make sure there is one (and only one) command-line argument
	if [ $# -ne 1 ]; then
		echo "ERROR: $FUNCNAME: incorrect number of arguments: $# (1 required)" >&2
		return 2
	fi
	
	# this implementation assumes a particular collating sequence
	local LC_COLLATE=C
	
	local length
	local c

	length="${#1}"
	for (( i = 0; i < length; i++ )); do
		c="${1:i:1}"
		case "$c" in
			[a-zA-Z0-9.~_-]) printf "$c" ;;
			*) printf '%%%02X' "'$c"
		esac
	done
}

#######################################################################
# This function is the inverse of the percent_encode function, that 
# is, it percent-decodes all percent-encoded characters in its string 
# argument.
#######################################################################
percent_decode () {
    # percent_decode <string>

	# make sure there is one (and only one) command-line argument
	if [ $# -ne 1 ]; then
		echo "ERROR: $FUNCNAME: incorrect number of arguments: $# (1 required)" >&2
		return 2
	fi
	
    printf '%b' "${1//%/\\x}"
}
