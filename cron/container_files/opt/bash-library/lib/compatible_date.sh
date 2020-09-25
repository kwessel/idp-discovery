#!/bin/bash

#######################################################################
# Copyright 2012--2016 Internet2
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
# A compatibility wrapper around the date command.
#
# This script refers to the "canonical dateTime string format" given by:
#
#   YYYY-MM-DDThh:mm:ssZ
#
# where "T" and "Z" are literals. Such a date is implicitly an UTC
# dateTime string.
#
# This script is compatible with Mac OS and GNU/Linux.
#######################################################################

# today's date (UTC) in canonical string format (YYYY-MM-DD)
date_today () {
	local dateStr

	dateStr=$( /bin/date -u +%Y-%m-%d )

	local exit_status=$?
	if [ $exit_status -ne 0 ]; then
		echo "ERROR: ${0##*/}:$FUNCNAME failed to produce date string" >&2
		return $exit_status
	fi

	echo $dateStr
	return 0
}

# NOW in locale-specific string format
dateTime_now_locale () {
	local dateStr

	dateStr=$( /bin/date )

	local exit_status=$?
	if [ $exit_status -ne 0 ]; then
		echo "ERROR: ${0##*/}:$FUNCNAME failed to produce date string" >&2
		return $exit_status
	fi

	echo $dateStr
	return 0
}

# NOW in canonical dateTime string format
dateTime_now_canonical () {
	local dateStr

	dateStr=$( /bin/date -u +%Y-%m-%dT%TZ )

	local exit_status=$?
	if [ $exit_status -ne 0 ]; then
		echo "ERROR: ${0##*/}:$FUNCNAME failed to produce date string" >&2
		return $exit_status
	fi

	echo $dateStr
	return 0
}

# on a 32-bit system, the maximum representable dateTime in canonical string format
dateTime_max32_canonical () {
	echo 2038-01-19T03:14:07Z
	return 0
}

# convert openssl dateTime string to canonical dateTime string
dateTime_openssl2canonical () {
	local in_date="$1"
	if [ -z "${in_date}" ] ; then
		echo "ERROR: ${0##*/}:$FUNCNAME requires command-line arg" >&2
		return 1
	fi

	local dateStr
	if [[ ${OSTYPE} = darwin* ]] ; then
		dateStr=$( /bin/date -ju -f "%b %e %T %Y GMT" "${in_date}" +%Y-%m-%dT%TZ )
	elif [[ ${OSTYPE} = linux* ]] ; then
		# GNU date(1) understands openssl implicitly
		dateStr=$( /bin/date -u -d "${in_date}" +%Y-%m-%dT%TZ )
	else
		echo "Error: OS not supported: ${OSTYPE}" >&2
		return 1
	fi

	local exit_status=$?
	if [ $exit_status -ne 0 ]; then
		echo "ERROR: ${0##*/}:$FUNCNAME failed to convert date string ${in_date}" >&2
		return $exit_status
	fi

	echo $dateStr
	return 0
}

# convert apache dateTime string to canonical dateTime string
dateTime_apache2canonical () {
	local in_date="$1"
	if [ -z "${in_date}" ] ; then
		echo "ERROR: ${0##*/}:$FUNCNAME requires command-line arg" >&2
		return 1
	fi

	local dateStr
	if [[ ${OSTYPE} = darwin* ]] ; then
		dateStr=$( /bin/date -ju -f "%a, %e %b %Y %T GMT" "${in_date}" +%Y-%m-%dT%TZ )
	elif [[ ${OSTYPE} = linux* ]] ; then
		# GNU date(1) understands apache implicitly UNTESTED
		dateStr=$( /bin/date -u -d "${in_date}" +%Y-%m-%dT%TZ )
	else
		echo "Error: OS not supported: ${OSTYPE}" >&2
		return 1
	fi

	local exit_status=$?
	if [ $exit_status -ne 0 ]; then
		echo "ERROR: ${0##*/}:$FUNCNAME failed to convert date string ${in_date}" >&2
		return $exit_status
	fi

	echo $dateStr
	return 0
}

# convert canonical dateTime string to seconds past the epoch
dateTime_canonical2secs () {
	local in_date="$1"
	if [ -z "${in_date}" ] ; then
		echo "ERROR: ${0##*/}:$FUNCNAME requires command-line arg" >&2
		return 1
	fi

	local secs
	if [[ ${OSTYPE} = darwin* ]] ; then
		secs=$( /bin/date -ju -f %Y-%m-%dT%TZ "${in_date}" +%s )
	elif [[ ${OSTYPE} = linux* ]] ; then
		# The GNU date(1) command will not parse a "canonical dateTime
		# string" so we convert the input string to a string that the
		# GNU date(1) command will understand: 'YYYY-MM-DD hh:mm:ss UTC'
		in_date=$( echo ${in_date} | /bin/sed 's/^\([^T]*\)T\([^Z]*\)Z$/\1 \2 UTC/' )
		secs=$( /bin/date -u -d "${in_date}" +%s )
	else
		echo "Error: OS not supported: ${OSTYPE}" >&2
		return 1
	fi

	local exit_status=$?
	if [ $exit_status -ne 0 ]; then
		echo "ERROR: ${0##*/}:$FUNCNAME failed to convert date string ${in_date}" >&2
		return $exit_status
	fi

	echo $secs
	return 0
}

# convert seconds past the epoch to canonical dateTime string
dateTime_secs2canonical () {
	local in_secs="$1"
	if [ -z "${in_secs}" ] ; then
		echo "ERROR: ${0##*/}:$FUNCNAME requires command-line arg" >&2
		return 1
	fi

	local dateStr
	if [[ ${OSTYPE} = darwin* ]] ; then
		dateStr=$( /bin/date -ju -r ${in_secs} +%Y-%m-%dT%TZ )
	elif [[ ${OSTYPE} = linux* ]] ; then
		dateStr=$( /bin/date -u -d "1970-01-01 ${in_secs} seconds" +%Y-%m-%dT%TZ )
	else
		echo "Error: OS not supported: ${OSTYPE}" >&2
		return 1
	fi

	local exit_status=$?
	if [ $exit_status -ne 0 ]; then
		echo "ERROR: ${0##*/}:$FUNCNAME failed to convert seconds ${in_secs}" >&2
		return $exit_status
	fi

	echo $dateStr
	return 0
}

#######################################################################
# Compute the elapsed time (in secs) between two dateTime values.
#
# Usage: tspan dateTime1 dateTime2
#
# The arguments are given in "canonical dateTime string format"
# as described above.
#
# If dateTime1 < dateTime2, the function returns a positive integer.
# If dateTime1 > dateTime2, the function returns a negative integer.
# If dateTime1 == dateTime2, the function returns zero.
#######################################################################
tspan () {

	local dateTime1
	local dateTime2
	local secs1
	local secs2
	local dateTime1confirm
	local dateTime2confirm
	
	# make sure there are two (and only two) command-line arguments
	if [ $# -eq 2 ]; then
		dateTime1="$1"
		dateTime2="$2"
	else
		echo "ERROR: $FUNCNAME: incorrect number of arguments: $# (2 required)" >&2
		return 2
	fi
	
	# convert dateTime1 to seconds past the Epoch
	secs1=$( dateTime_canonical2secs $dateTime1 )

	# sanity check (for logging)
	dateTime1confirm=$( dateTime_secs2canonical $secs1 )

	# convert dateTime1 to seconds past the Epoch
	secs2=$( dateTime_canonical2secs $dateTime2 )

	# sanity check (for logging)
	dateTime2confirm=$( dateTime_secs2canonical $secs2 )

	# compute time difference (which may be negative)
	echo $(( secs2 - secs1 ))

	return 0
}	

#######################################################################
# Given a time instant, compute the time interval (in secs) between 
# the current time (NOW) and the time instant.
#
# Usage: secsUntil [-b begDateTime] [endDateTime]
#
# The arguments begDateTime and endDateTime are expected to be  
# in "canonical dateTime string format" as described above.
#
# If the -b option is omitted, the function computes the time
# interval between NOW and endDateTime. If the latter is omitted
# on the command line, its value is taken from stdin.
#
# Presumably endDateTime is a time instant in the future but the 
# function does not check this. If endDateTime is in the past, 
# and option -b is omitted, the output of this function will be 
# negative.
#
# If the -b option is present, the time interval between
# begDateTime and endDateTime is computed. In this case,
# the output will be positive if (and only if) endDateTime is 
# chronologically later than begDateTime.
#######################################################################
secsUntil () {

	local dateTime
	local now
	local d
	
	local opt
	local OPTARG
	local OPTIND
	while getopts ":b:" opt; do
		case $opt in
			b)
				now="$OPTARG"
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

	# make sure there is at most one command-line argument
	shift $(( OPTIND - 1 ))
	if [ $# -eq 0 ]; then
		# take input from stdin
		dateTime=$( /bin/cat - )
	elif [ $# -eq 1 ]; then
		dateTime="$1"
	else
		echo "ERROR: $FUNCNAME: incorrect number of arguments: $# (0 or 1 required)" >&2
		return 2
	fi
	
	# compute NOW if necessary
	if [ -z "$now" ]; then
		# compute dateTime NOW
		now=$( /bin/date -u +%Y-%m-%dT%TZ )
	fi

	# compute time until the given time instant
	d=$( tspan "$now" "$dateTime" )
	echo $d

	return 0
}	

#######################################################################
# Given a time instant, compute the time interval (in secs) between 
# the time instant and the current time (NOW).
#
# Usage: secsSince [-e endDateTime] [begDateTime]
#
# The arguments begDateTime and endDateTime are expected to be  
# in "canonical dateTime string format" as described above.
#
# If the -e option is omitted, the function computes the time
# interval between begDateTime and NOW. If the former is omitted
# on the command line, its value is taken from stdin.
#
# Presumably begDateTime is a time instant in the past but the 
# function does not check this. If begDateTime is in the future, 
# and option -e is omitted, the output of this function will be 
# negative.
#
# If the -e option is present, the time interval between
# begDateTime and endDateTime is computed. In this case,
# the output will be positive if (and only if) endDateTime is 
# chronologically later than begDateTime.
#######################################################################
secsSince () {

	local dateTime
	local now
	local d
	
	local opt
	local OPTARG
	local OPTIND
	while getopts ":e:" opt; do
		case $opt in
			e)
				now="$OPTARG"
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

	# make sure there is at most one command-line argument
	shift $(( OPTIND - 1 ))
	if [ $# -eq 0 ]; then
		# take input from stdin
		dateTime=$( /bin/cat - )
	elif [ $# -eq 1 ]; then
		dateTime="$1"
	else
		echo "ERROR: $FUNCNAME: incorrect number of arguments: $# (0 or 1 required)" >&2
		return 2
	fi
	
	# compute NOW if necessary
	if [ -z "$now" ]; then
		# compute dateTime NOW
		now=$( /bin/date -u +%Y-%m-%dT%TZ )
	fi

	# compute time until invalid in secs
	d=$( tspan $dateTime $now )
	echo $d

	return 0
}	

#######################################################################
# Convert seconds into an ISO 8061 duration.
#
# Usage: secs2duration SECONDS
#
#######################################################################
secs2duration () {

	local days
	local hours
	local mins
	local secs
	
	# make sure there is exactly one command-line argument
	if [ $# -eq 1 ]; then
		secs="$1"
	else
		echo "ERROR: $FUNCNAME: incorrect number of arguments: $# (1 required)" >&2
		return 2
	fi
	
	# convert seconds to days, hours, minutes, seconds
	days=$(( secs/86400 ))
	hours=$(( secs%86400/3600 ))
	mins=$(( secs%3600/60 ))
	secs=$(( secs%60 ))
	
	# an ISO 8601 duration
	printf 'P%dDT%dH%dM%dS\n' $days $hours $mins $secs
	
	return
}