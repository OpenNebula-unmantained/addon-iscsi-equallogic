# -------------------------------------------------------------------------- #
# Copyright 2014, Asociacion Clubs Baloncesto (acb.com)                      #
# Author: Joaquin Villanueva                                                 #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #

# ------------------------------------------------------------------------------
# Debug functions
# ------------------------------------------------------------------------------

# Debug calls if ONE_MAD_DEBUG and EQL_MAD_DEBUG enabled (set on every script to log)
function eql_log_debug {
    if [ $ONE_MAD_DEBUG -eq 1 ] && [ $EQL_MAD_DEBUG -eq 1 ]; then
	local EQL_LOG_FILE="/var/log/one/one_eqliscsi.log"
	local SCRIPT_NAME="$0"
	local TIMESTAMP=$(date +"[%F %T]")
	local DEBUG_MSG="$*"
	echo ${TIMESTAMP} ${SCRIPT_NAME}: "${DEBUG_MSG}" >> ${EQL_LOG_FILE}
    fi
}

function eql_log {
    eql_log_debug "[I]" "$*"
    log "$*"
}

function eql_error_message {
    eql_log_debug "[E]" "$*"
    error_message "$*"
}


# ------------------------------------------------------------------------------
# iSCSI functions
# ------------------------------------------------------------------------------
#
# Common global variables used:
#
#   EQL_HOST - Equallogic GROUP HOST
#   EQL_USER - Equallogic USER
#   EQL_PASS - Equallogic PASSWORD
#   EQL_MULTIHOST - Enable multihost access for volume. If empty, defaults to enabled.
#   EQL_SECURITY_ACCESS - Security settings for volume. See Equallogic CLI docs for options. If empty, defaults to unrestricted.
#   EQL_BASE_DEVICE - Base path used by Equallogic HIT tools to mount targets
#
#   Default values set at remotes/datastore/eqliscsi/eqliscsi.conf file
#
# echoes Error text / Command output for debug / value return
#
# returns 0:ok
#         1:failed
#
#-------------------------------------------------------------------------------


# ------------------------------------------------------------------------------
# iSCSI functions executed on target Equallogic group controller
#       using EqlCliExec.py (ssh)
# ------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Creates lock files to prevent more than 8 ssh commands to Equallogic
#-------------------------------------------------------------------------------
function eql_cmd_lock() {
    # Prevent more than 7 parallel executions of EQLCMD
    local lock_dir="/var/lib/one/.eql_lock"
    local lock_file="eql-$(date +%Y%m%d%H%M%S%N)"
    local max_locks=7
    local wait_time=5
    local timeout=6 # 30 secs
    local num_locks=0

    # Check and create lock dir
    [[ -d ${lock_dir} ]] || mkdir -p ${lock_dir}

    # Count lock files
    num_locks=$(ls -1 ${lock_dir} | wc -l)
    # If less than 7, it's ok to continue
    # Wait until num_locks is less than 7 or timeout
    local x=0
    while [ "${num_locks}" -ge ${max_locks} -a "${x}" -lt ${timeout} ]; do
        sleep ${wait_time}
        x=$((x+1))
        num_locks=$(ls -1 ${lock_dir} | wc -l)
    done
    if [[ ${x} -lt ${timeout} ]]; then
        touch "${lock_dir}/${lock_file}"
        echo $lock_file
    fi
}

function eql_cmd_lock_release() {
    local lock_dir="/var/lib/one/.eql_lock"
    rm ${lock_dir}/${1}
}

#-------------------------------------------------------------------------------
# Get pool size and free space
#
#   @param $1 - Equallogic POOL
#-------------------------------------------------------------------------------
function eqladm_free_space {
    local EQL_POOL="$1"

    local CMD=""
    local RETVAL=""

    # Check pool free space
    local eql_lock=""
    eql_lock=$(eql_cmd_lock)
    if [[ -z ${eql_lock} ]]; then
	eql_error_message "Timeout getting free space on pool $EQL_POOL"
	return 1
    fi
    CMD="$EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS pool select $EQL_POOL show"
    RETVAL=$($SUDO $CMD)
    RC=$?

    eql_cmd_lock_release ${eql_lock}
    if [ "$RETVAL" == *"Error"* ] || [ "$RC" -ne 0 ]; then
	eql_error_message "Error getting free space on pool $EQL_POOL $RETVAL"
	return 1
    fi

    # Get size and free space from returned value
    RETVAL=`echo "$RETVAL" | grep -e '^TotalCapacity: ' -e '^FreeSpace: ' | sed 's/TB/*1024*1024/;s/GB/*1024/'`
    RETVAL=${RETVAL//MB/}
    RETVAL=${RETVAL/TotalCapacity:/TOTAL_MB}
    RETVAL=${RETVAL/FreeSpace:/FREE_MB}
    TOTAL=$(echo $RETVAL | awk '{ print $2}' | bc)
    FREE=$(echo $RETVAL | awk '{ print $4}' | bc)
    RETVAL="TOTAL_MB $TOTAL FREE_MB $FREE"
    # Return pool size and free space
    echo "$RETVAL"
    return 0
}


#-------------------------------------------------------------------------------
# Create new volume and set it online & read-write with access rules
#
#   @param $1 - Equallogic POOL
#   @param $2 - Volume name
#   @param $3 - Size (MB)
#   @param $4 - Volume description
#-------------------------------------------------------------------------------

function eqladm_target_new {
    local EQL_POOL="$1"
    local EQL_VOLUME="$2"
    local SIZE="$3"
    local EQL_VOL_DESCRIPTION="$4"

    local CMD=""
    local RETVAL=""
    local ACCESS=""
    local RC=""

    # If no security policy, defaults to unrestricted access
    if [ -z "$EQL_SECURITY_ACCESS" ]; then
	ACCESS="unrestricted"
    fi

    # Volume creation
    local eql_lock=""
    eql_lock=$(eql_cmd_lock)
    if [[ -z ${eql_lock} ]]; then
	eql_error_message "Timeout creating volume $EQL_VOLUME on $EQL_HOST"
	return 1
    fi
    CMD="$EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS volume create $EQL_VOLUME $SIZE description '$EQL_VOL_DESCRIPTION' online $ACCESS pool $EQL_POOL $EQL_THINPROVISION"
    RETVAL=$($SUDO $CMD)
    RC=$?

    eql_cmd_lock_release ${eql_lock}
    if [[ "$RETVAL" == *"Error"* ]] || [[ "$RC" -ne 0 ]]; then
	eql_error_message "Error creating volume $EQL_VOLUME on $EQL_HOST $RETVAL"
	return 1
    fi

    # Get volume IQN from returned value
    RETVAL=`echo "$RETVAL" | $SED '/iSCSI/,/./ !d' | $TR -d '\n' | $CUT -d' ' -f5`
    RETVAL=${RETVAL%?}
    eql_log "New volume IQN: ${RETVAL}"

    # Set multihost and access rules
    eqladm_set_access $EQL_VOLUME
    RC=$?
    if [ "$RC" -ne 0 ]; then
        return 1
    fi

    # Return volume IQN
    echo "$RETVAL"
    return 0
}


#-------------------------------------------------------------------------------
# Clone volume and set it online & read-write with access rules
#
#   @param $1 - Source volume
#   @param $2 - New volume
#   @param $3 - New volume description
#-------------------------------------------------------------------------------

function eqladm_target_clone {
    local EQL_VOLUME="$1"
    local EQL_NEW_VOLUME="$2"
    local EQL_VOL_DESCRIPTION="$3"

    local CMD=""
    local RETVAL=""
    local ACCESS=""
    local RC=""

    # If no security policy, defaults to unrestricted access
    if [ -z "$EQL_SECURITY_ACCESS" ]; then
	ACCESS="unrestricted"
    fi

    # Volume cloning
    local eql_lock=""
    eql_lock=$(eql_cmd_lock)
    if [[ -z ${eql_lock} ]]; then
	eql_error_message "Timeout cloning volume $EQL_VOLUME on $EQL_HOST"
	return 1
    fi
    CMD="$EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS volume select $EQL_VOLUME clone $EQL_NEW_VOLUME description '$EQL_VOL_DESCRIPTION' online $ACCESS"
    RETVAL=$($SUDO $CMD)
    RC=$?

    eql_cmd_lock_release ${eql_lock}
    if [[ "$RETVAL" == *"Error"* ]] || [[ "$RC" -ne 0 ]]; then
	eql_error_message "Error cloning $EQL_VOLUME to $EQL_NEW_VOLUME on $EQL_HOST $RETVAL"
	return 1
    fi

    # Get volume IQN from returned value
    RETVAL=`echo "$RETVAL" | $SED '/iSCSI/,/./ !d' | $TR -d '\n' | $CUT -d' ' -f5`
    RETVAL=${RETVAL%?}
    eql_log "New volume IQN: ${RETVAL}"

    # Set multihost and access rules
    eqladm_set_access $EQL_NEW_VOLUME
    RC=$?
    if [ "$RC" -ne 0 ]; then
        return 1
    fi

    # Return new volume IQN
    echo "$RETVAL"
    return 0
}


#-------------------------------------------------------------------------------
# Delete volume
#
#   @param $1 - Volume name
#-------------------------------------------------------------------------------

function eqladm_target_delete {
    local EQL_VOLUME="$1"

    local CMD=""
    local RETVAL=""
    local RC=""

    # Set volume offline before deleting
    local eql_lock=""
    eql_lock=$(eql_cmd_lock)
    if [[ -z ${eql_lock} ]]; then
	eql_error_message "Timeout setting volume $EQL_VOLUME offline on $EQL_HOST"
	return 1
    fi
    CMD="$EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS volume select $EQL_VOLUME offline"
    RETVAL=$($SUDO $CMD)
    RC=$?

    eql_cmd_lock_release ${eql_lock}
    if [[ "$RETVAL" == *"Error"* ]] || [[ "$RC" -ne 0 ]]; then
	eql_error_message "Error setting volume $EQL_VOLUME offline on $EQL_HOST $RETVAL"
	return 1
    fi

    # Delete volume
    eql_lock=$(eql_cmd_lock)
    if [[ -z ${eql_lock} ]]; then
	eql_error_message "Timeout deleting volume $EQL_VOLUME on $EQL_HOST"
	return 1
    fi
    CMD="$EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS volume delete $EQL_VOLUME"
    RETVAL=$($SUDO $CMD)

    eql_cmd_lock_release ${eql_lock}
    if [[ "$RETVAL" == *"% Error"* ]]; then
	eql_error_message "Error deleting volume $EQL_VOLUME on $EQL_HOST $RETVAL"
	return 1
    fi
    return 0
}


#-------------------------------------------------------------------------------
# Set multihost option and security access rules
#   Global EQL_MULTIHOST and EQL_SECURITY_ACCESS used
#
#   @param $1 - Volume name
#-------------------------------------------------------------------------------

function eqladm_set_access {
    local EQL_VOLUME="$1"

    local CMD=""
    local RETVAL=""
    local RC=""

    # Multihost access
    if [ -z "$EQL_MULTIHOST" ]; then
	EQL_MULTIHOST="enable"
    fi
    local eql_lock=""
    eql_lock=$(eql_cmd_lock)
    if [[ -z ${eql_lock} ]]; then
	eql_error_message "Timeout setting volume $EQL_VOLUME multihost access on $EQL_HOST"
	return 1
    fi
    CMD="$EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS volume select $EQL_VOLUME multihost-access $EQL_MULTIHOST"
    RETVAL=$($SUDO $CMD)
    RC=$?

    eql_cmd_lock_release ${eql_lock}
    if [[ "$RETVAL" == *"Error"* ]] || [[ "$RC" -ne 0 ]]; then
	eql_error_message "Error setting volume $EQL_VOLUME multihost access on $EQL_HOST $RETVAL"
	return 1
    fi
    # Set access rules
    eql_lock=$(eql_cmd_lock)
    if [[ -z ${eql_lock} ]]; then
	eql_error_message "Timeout setting volume $EQL_VOLUME access rules on $EQL_HOST"
	return 1
    fi
    CMD="$EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS volume select $EQL_VOLUME access create $EQL_SECURITY_ACCESS"
    RETVAL=$($SUDO $CMD)

    eql_cmd_lock_release ${eql_lock}
    if [[ "$RETVAL" == *"% Error"* ]]; then
	eql_error_message "Error setting access rules to $EQL_VOLUME volume on $EQL_HOST $RETVAL"
	return 1
    fi
    return 0
}


# ------------------------------------------------------------------------------
# iSCSI functions executed on client hosts using iscsiadm.
#       Construct and echo commands, not executed.
# ------------------------------------------------------------------------------

# Discover targets
function eqliscsi_discovery {
    echo "$ISCSIADM -m discoverydb -t st -p $EQL_HOST -I $EQL_IFACE -o new -o delete --discover"
}

# Get IQN from iscsiadm database: seek volume name
function eqliscsi_get_iqn_from_node {
    local VOLUME="$1"
    echo "$ISCSIADM -m node | $GREP '"${VOLUME}"$' | $CUT -d' ' -f2"
}

# Login to target (@param $1 - Target IQN)
function eqliscsi_login {
    local IQN="$1"
    echo "$ISCSIADM -m node -T $IQN -p $EQL_HOST -I $EQL_IFACE -l"
}

# Logout from target (@param $1 - Target IQN)
function eqliscsi_logout {
    local IQN="$1"
    echo "$ISCSIADM -m node -T $IQN -I $EQL_IFACE -u"
}


# ------------------------------------------------------------------------------
# iSCSI information functions executed on client hosts using iscsiadm.
#       Returns IQN values or commands to retrieve values.
# ------------------------------------------------------------------------------

# Returns IQN of volume from EQL_HOST (@param $1 - Volume name)
function eqliscsi_get_iqn_target {
    local EQL_VOLUME="$1"
    local eql_lock=""
    eql_lock=$(eql_cmd_lock)
    if [[ -z ${eql_lock} ]]; then
	return
    fi
    echo `$SUDO $EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS "volume show $EQL_VOLUME" | grep "iSCSI Name" | $CUT -d' ' -f3`
    eql_cmd_lock_release ${eql_lock}
}

# Returns IQN of volume from discovery database (iscsiadm) (@param $1 - Volume name)
function eqliscsi_get_iqn_client {
    local EQL_VOLUME="$1"
    echo `$SUDO $ISCSIADM -m discoverydb -t st -p $EQL_HOST -I $EQL_IFACE -o new -o delete --discover | grep ${EQL_VOLUME}$ | $CUT -d' ' -f2`
}

# Returns command to retrieve IQN of volume from client host sessions (@param $1 - Volume name)
function eqliscsi_get_session_iqn {
    local EQL_VOLUME="$1"
    echo "$ISCSIADM -m session | grep $EQL_VOLUME\$ | awk -F' ' 'NR>1{ print \$4 }'"
}

# Returns command to retrieve EQL_HOST of volume from client host sessions (@param $1 - Volume name)
function eqliscsi_get_session_host {
    local EQL_VOLUME="$1"
    echo "$ISCSIADM -m session | grep $EQL_VOLUME\$ | awk -F' ' 'NR>1{ print \$3 }' | $CUT -d':' -f1"
}


# ------------------------------------------------------------------------------
# Utility functions
# ------------------------------------------------------------------------------

#-------------------------------------------------------------------------------
# Converts volume name to lowercase and replace spaces with scores
#   @param $1 - Volume name to convert
#   @return Text converted
#-------------------------------------------------------------------------------
function eql_clean_volume_name {
    local VOLUME="$1"
    VOLUME=$(echo $VOLUME | $TR '[:upper:]' '[:lower:]')
    VOLUME=${VOLUME// /-}
    VOLUME=${VOLUME//./-}
    VOLUME=${VOLUME//_/-}
    echo "${VOLUME}"
}


# Returns host part from source (@param $1 - source value in <host:iqn> format)
function eql_src_get_host {
    local SRC="$1"
    echo "$(echo $SRC | $CUT -d: -f1)"
}


# Returns iqn part from source (@param $1 - source value in <host:iqn> format)
function eql_src_get_iqn {
    local SRC="$1"
    echo "$(echo $SRC | $CUT -d: -f2-3)"
}


# Returns volume part from source (@param $1 - source value in <host:iqn> format)
function eql_src_get_volume {
    local SRC="$1"
    if [[ $SRC == *:iqn* ]]; then
	# If uses old name, clean out (deprecated)
	echo "$(eql_clean_volume_name $(echo $SRC | $CUT -d: -f3 | $CUT -b37-))"
    else
	if [[ $SRC == *:* ]]; then
	    echo "$(echo $SRC | $CUT -d: -f2)"
	else 
	    echo "$SRC"
	fi
    fi
}


# Returns command to retrieve volume from device path (@param $1 - linked datastore device path)
function eql_link_get_volume {
    local LINK_PATH="$1"
    echo "readlink $LINK_PATH | awk -F$EQL_BASE_DEVICE/ '{ print \$2 }'"
}

# ------------------------------------------------------------------------------
# Misc functions
# ------------------------------------------------------------------------------

function string_to_array
{
    local IFS=";"
    local item
    for item in $1
    do
	echo "$item "
    done
    unset IFS
}


# ------------------------------------------------------------------------------
# Debug calls if ONE_MAD_DEBUG and EQL_MAD_DEBUG enabled (set on every script to log)
# ------------------------------------------------------------------------------
eql_log_debug "[C]" "$*"
