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
# Given a file of HTTP headers (such as that output by the curl
# command-line tool), convert the headers to a JSON object.
#
# Usage: convert_http_headers_json FILE
#
#######################################################################
convert_http_headers_json () {

	# external dependencies
	if [ "$(type -t print_log_message)" != function ]; then
		echo "ERROR: $FUNCNAME: function print_log_message not found" >&2
		return 2
	fi
	if [ "$(type -t get_response_code)" != function ]; then
		echo "ERROR: $FUNCNAME: function get_response_code not found" >&2
		return 2
	fi
	if [ "$(type -t get_header_value)" != function ]; then
		echo "ERROR: $FUNCNAME: function get_header_value not found" >&2
		return 2
	fi

	local headers_file
	local header_name
	local response_code
	local response_date
	local last_modified
	local etag
	local content_length
	local content_type
	local content_encoding
	local status_code
	
	# check arguments
	if [ $# -ne 1 ]; then
		echo "ERROR: $FUNCNAME: wrong number of arguments: $# (1 required)" >&2
		return 2
	fi
	headers_file="$1"
	
	# check file
	if [ ! -f "$headers_file" ]; then
		echo "ERROR: $FUNCNAME: file does not exist: $headers_file" >&2
		return 2
	fi
	
	# get the HTTP response code
	response_code=$( get_response_code $headers_file )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		print_log_message -E "$FUNCNAME: get_response_code failed ($status_code) to parse response code from response: $headers_file"
	fi

	# get the Date response header
	header_name=Date
	response_date=$( get_header_value $headers_file $header_name )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		print_log_message -E "$FUNCNAME: get_header_value failed ($status_code) to parse $header_name from response: $headers_file"
	fi

	# get the Last-Modified response header
	header_name=Last-Modified
	last_modified=$( get_header_value $headers_file $header_name )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		print_log_message -E "$FUNCNAME: get_header_value failed ($status_code) to parse $header_name from response: $headers_file"
	fi

	# get the ETag response header
	header_name=ETag
	etag=$( get_header_value $headers_file $header_name )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		print_log_message -E "$FUNCNAME: get_header_value failed ($status_code) to parse $header_name from response: $headers_file"
	fi

	# get the Content-Length response header
	header_name=Content-Length
	content_length=$( get_header_value $headers_file $header_name )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		print_log_message -E "$FUNCNAME: get_header_value failed ($status_code) to parse $header_name from response: $headers_file"
	fi

	# get the Content-Type response header
	header_name=Content-Type
	content_type=$( get_header_value $headers_file $header_name )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		print_log_message -E "$FUNCNAME: get_header_value failed ($status_code) to parse $header_name from response: $headers_file"
	fi

	response_code=$( escape_special_json_chars "$response_code" )
	response_date=$( escape_special_json_chars "$response_date" )
	last_modified=$( escape_special_json_chars "$last_modified" )
	etag=$( escape_special_json_chars "$etag" )
	content_length=$( escape_special_json_chars "$content_length" )
	content_type=$( escape_special_json_chars "$content_type" )

	# get the Content-Encoding response header
	header_name=Content-Encoding
	content_encoding=$( get_header_value $headers_file $header_name )
	status_code=$?
	if [ $status_code -ne 0 ]; then
		print_log_message -E "$FUNCNAME: get_header_value failed ($status_code) to parse $header_name from response: $headers_file"
	fi
	
	echo  # emit a blank line
	if [ -n "$content_encoding" ]; then
	
		content_encoding=$( escape_special_json_chars "$content_encoding" )
		
		/bin/cat <<- JSON_OBJECT
		    {
		      "ResponseCode": "$response_code",
		      "Date": "$response_date",
		      "LastModified": "$last_modified",
		      "ETag": "$etag",
		      "ContentLength": "$content_length",
		      "ContentType": "$content_type",
		      "ContentEncoding": "$content_encoding"
		    }
		JSON_OBJECT
	else
	
		/bin/cat <<- JSON_OBJECT
		    {
		      "ResponseCode": "$response_code",
		      "Date": "$response_date",
		      "LastModified": "$last_modified",
		      "ETag": "$etag",
		      "ContentLength": "$content_length",
		      "ContentType": "$content_type"
		    }
		JSON_OBJECT
	fi
	
	return	
}

escape_special_json_chars () {
	local str="$1"
	
	# backslash (\) and double quote (") are special
	echo "$str" | $_SED -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
