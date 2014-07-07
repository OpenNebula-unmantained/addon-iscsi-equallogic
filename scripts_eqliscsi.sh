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

# Path for utilities
TR=tr

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
#
#-------------------------------------------------------------------------------
# Get pool size and free space
#
#   @param $1 - Equallogic POOL
#-------------------------------------------------------------------------------
function eqladm_free_space {
    local EQL_POOL="$1"

    local CMD=""
    local RETVAL=""

    # Volume creation
    CMD="$EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS pool select $EQL_POOL show"
    RETVAL=$($SUDO $CMD)
    ERROR=$?
    if [[ "$RETVAL" == *"Error"* ]] || [[ "$ERROR" -ne 0 ]]; then
	log_error "Error getting free space on pool $EQL_POOL $RETVAL"
	return 1
    fi

    # Get size and free space from returned value
    RETVAL=`echo "$RETVAL" | grep -e '^TotalCapacity: ' -e '^FreeSpace: '`
    RETVAL=${RETVAL//MB/}
    RETVAL=${RETVAL/TotalCapacity:/TOTAL_MB}
    RETVAL=${RETVAL/FreeSpace:/FREE_MB}
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

    # If no security policy, defaults to unrestricted access
    if [ -z "$EQL_SECURITY_ACCESS" ]; then
	ACCESS="unrestricted"
    fi

    # Volume creation
    CMD="$EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS volume create $EQL_VOLUME $SIZE description '$EQL_VOL_DESCRIPTION' online $ACCESS pool $EQL_POOL $EQL_THINPROVISION"
    RETVAL=$($SUDO $CMD)
    ERROR=$?
    if [[ "$RETVAL" == *"Error"* ]] || [[ "$ERROR" -ne 0 ]]; then
	log_error "Error creating volume $EQL_VOLUME on $EQL_HOST $RETVAL"
	return 1
    fi

    # Get volume IQN from returned value
    RETVAL=`echo "$RETVAL" | $SED '/iSCSI/,/./ !d' | $TR -d '\n' | $CUT -d' ' -f5`
    RETVAL=${RETVAL%?}

    # Set multihost and access rules
    eqladm_set_access $EQL_VOLUME
    ERROR=$?
    if [ "$ERROR" -ne 0 ]; then
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

    # If no security policy, defaults to unrestricted access
    if [ -z "$EQL_SECURITY_ACCESS" ]; then
	ACCESS="unrestricted"
    fi

    # Volume cloning
    CMD="$EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS volume select $EQL_VOLUME clone $EQL_NEW_VOLUME description '$EQL_VOL_DESCRIPTION' online $ACCESS"
    RETVAL=$($SUDO $CMD)
    ERROR=$?
    if [[ "$RETVAL" == *"Error"* ]] || [[ "$ERROR" -ne 0 ]]; then
	log_error "Error cloning $EQL_VOLUME to $EQL_NEW_VOLUME on $EQL_HOST $RETVAL"
	return 1
    fi

    # Get volume IQN from returned value
    RETVAL=`echo "$RETVAL" | $SED '/iSCSI/,/./ !d' | $TR -d '\n' | $CUT -d' ' -f5`
    RETVAL=${RETVAL%?}
    log_error "$RETVAL"

    # Set multihost and access rules
    eqladm_set_access $EQL_NEW_VOLUME
    ERROR=$?
    if [ "$ERROR" -ne 0 ]; then
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

    # Set volume offline before deleting
    CMD="$EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS volume select $EQL_VOLUME offline"
    RETVAL=$($SUDO $CMD)
    ERROR=$?
    if [[ "$RETVAL" == *"Error"* ]] || [[ "$ERROR" -ne 0 ]]; then
	log_error "Error setting volume $EQL_VOLUME offline on $EQL_HOST $RETVAL"
	return 1
    fi

    # Delete volume
    CMD="$EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS volume delete $EQL_VOLUME"
    RETVAL=$($SUDO $CMD)
    if [[ "$RETVAL" == *"% Error"* ]]; then
	log_error "Error deleting volume $EQL_VOLUME on $EQL_HOST $RETVAL"
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

    # Multihost access
    if [ -z "$EQL_MULTIHOST" ]; then
	EQL_MULTIHOST="enable"
    fi
    CMD="$EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS volume select $EQL_VOLUME multihost-access $EQL_MULTIHOST"
    RETVAL=$($SUDO $CMD)
    ERROR=$?
    if [[ "$RETVAL" == *"Error"* ]] || [[ "$ERROR" -ne 0 ]]; then
	log_error "Error setting volume $EQL_VOLUME multihost access on $EQL_HOST $RETVAL"
	return 1
    fi
    # Set access rules
    CMD="$EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS volume select $EQL_VOLUME access create $EQL_SECURITY_ACCESS"
    RETVAL=$($SUDO $CMD)
    if [[ "$RETVAL" == *"% Error"* ]]; then
	log_error "Error setting access rules to $EQL_VOLUME volume on $EQL_HOST $RETVAL"
	return 1
    fi
    return 0
}


# ------------------------------------------------------------------------------
# iSCSI functions executed on client hosts using iscsiadm and ehcmcli.
#       Construct and echo commands, not executed.
# ------------------------------------------------------------------------------

# Discover targets
function eqliscsi_discovery {
    #echo "$ISCSIADM -m discovery -t st -p $EQL_HOST"
    echo "$ISCSIADM -m discoverydb -t st -p $EQL_HOST -I $EQL_IFACE -o new -o delete --discover"
}


# Login to target using ehcmcli (@param $1 - Target IQN)
function eqliscsi_login {
    local IQN="$1"
    #echo "$EQLEHCM login --target $IQN --portal $EQL_HOST"
    echo "$ISCSIADM -m node -T $IQN -p $EQL_HOST -I $EQL_IFACE -l"
}

# Logout from target using ehcmcli (@param $1 - Target IQN)
function eqliscsi_logout {
    local IQN="$1"
    #echo "$EQLEHCM logout --target $IQN"
    echo "$ISCSIADM -m node -T $IQN -I $EQL_IFACE -u"
}


# ------------------------------------------------------------------------------
# iSCSI information functions executed on client hosts using iscsiadm and ehcmcli.
#       Returns IQN values or commands to retrieve values.
# ------------------------------------------------------------------------------

# Returns IQN of volume from EQL_HOST (@param $1 - Volume name)
function eqliscsi_get_iqn_target {
    local EQL_VOLUME="$1"
    echo `$SUDO $EQLADM -g $EQL_HOST -a $EQL_USER -p $EQL_PASS "volume show $EQL_VOLUME" | grep "iSCSI Name" | $CUT -d' ' -f3`
}

# Returns IQN of volume from discovery database (iscsiadm) (@param $1 - Volume name)
function eqliscsi_get_iqn_client {
    local EQL_VOLUME="$1"
    echo `$SUDO $ISCSIADM -m discoverydb -t st -p $EQL_HOST -I $EQL_IFACE -o new -o delete --discover | grep $EQL_VOLUME$ | $CUT -d' ' -f2`
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
    echo "${VOLUME// /-}"
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
    echo "$(eql_clean_volume_name $(echo $SRC | $CUT -d: -f3 | $CUT -b37-))"
}


# Returns command to retrieve volume from device path (@param $1 - linked datastore device path)
function eql_link_get_volume {
    local LINK_PATH="$1"
    echo "readlink $LINK_PATH | awk -F$EQL_BASE_DEVICE/ '{ print \$2 }'"
}

# ------------------------------------------------------------------------------
# Misc functions
# ------------------------------------------------------------------------------

# Executes a command, if it fails returns error message and returns
# If a second parameter is present it is used as the error message when
# the command fails
#
# Copied from scripts_common.sh, but uses return instead of exit to let the main
# script handle the error if third param is "exit"
function eql_exec_and_log
{
    message=$2
    shopt -s nocasematch
    exit_if_error=0 && [[ $3 == "exit" ]] && exit_if_error=1
    shopt -u nocasematch

    EXEC_LOG_ERR=`$1 2>&1 1>/dev/null`
    EXEC_LOG_RC=$?

    if [ $EXEC_LOG_RC -ne 0 ]; then
        log_error "Command \"$1\" failed: $EXEC_LOG_ERR"

        if [ -n "$2" ]; then
            error_message "$2"
        else
            error_message "Error executing $1: $EXEC_LOG_ERR"
        fi
	if [ $exit_if_error -eq 0 ]; then 
    	    return $EXEC_LOG_RC
	else
    	    exit $EXEC_LOG_RC
	fi
    fi
}

# Like exec_and_log but the first argument is the number of seconds
# before here is timeout and kills the command
#
# NOTE: if the command is killed because a timeout the return code
# will be 143 = 128+15 (SIGHUP)
#
# Copied from scripts_common.sh, but uses return instead of exit to let the main
# script handle the error if third param is "exit"
function eql_timeout_exec_and_log
{
    TIMEOUT=$1
    shift

    CMD="$1"
    shopt -s nocasematch
    exit_if_error=0 && [[ $2 == "exit" ]] && exit_if_error=1
    shopt -u nocasematch

    # Call original exec_and_log, to maintain behavior
    exec_and_log "$CMD" &
    CMD_PID=$!

    # timeout process
    (
        sleep $TIMEOUT
        kill $CMD_PID 2>/dev/null
        log_error "Timeout executing $CMD"
        error_message "Timeout executing $CMD"
        exit -1
    ) &
    TIMEOUT_PID=$!

    # stops the execution until the command finalizes
    wait $CMD_PID 2>/dev/null
    CMD_CODE=$?

    # if the script reaches here the command finished before it
    # consumes timeout seconds so we can kill timeout process
    kill $TIMEOUT_PID 2>/dev/null 1>/dev/null
    wait $TIMEOUT_PID 2>/dev/null

    # checks the exit code of the command and returns if it is not 0
    if [ "x$CMD_CODE" != "x0" ]; then
	if [ $exit_if_error -eq 0 ]; then 
    	    return $CMD_CODE
	else
    	    exit $CMD_CODE
	fi
    fi
}

#This function executes $2 at $1 host and report error $3
# Copied from scripts_common.sh, but uses return instead of exit to let the main
# script handle the error if fourth param is "exit"
function eql_ssh_exec_and_log
{
    shopt -s nocasematch
    exit_if_error=0 && [[ $4 == "exit" ]] && exit_if_error=1
    shopt -u nocasematch

    SSH_EXEC_ERR=`$SSH $1 sh -s 2>&1 1>/dev/null <<EOF
$2
EOF`
    SSH_EXEC_RC=$?

    if [ $SSH_EXEC_RC -ne 0 ]; then
        log_error "Command \"$2\" failed: $SSH_EXEC_ERR"

        if [ -n "$3" ]; then
            error_message "$3"
        else
            error_message "Error executing $2: $SSH_EXEC_ERR"
        fi

	if [ $exit_if_error -eq 0 ]; then
    	    return $SSH_EXEC_RC
	else
    	    exit $SSH_EXEC_RC
	fi
    fi
}

#Creates path ($2) at $1
# Copied from scripts_common.sh, but uses return instead of exit to let the main
# script handle the error if third param is "exit"
function eql_ssh_make_path
{
    shopt -s nocasematch
    exit_if_error=0 && [[ $3 == "exit" ]] && exit_if_error=1
    shopt -u nocasematch

    SSH_EXEC_ERR=`$SSH $1 sh -s 2>&1 1>/dev/null <<EOF
if [ ! -d $2 ]; then
   mkdir -p $2
fi
EOF`
    SSH_EXEC_RC=$?

    if [ $? -ne 0 ]; then
        error_message "Error creating directory $2 at $1: $SSH_EXEC_ERR"

	if [ $exit_if_error -eq 0 ]; then 
    	    return $SSH_EXEC_RC
	else
    	    exit $SSH_EXEC_RC
	fi
    fi
}


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
