# iSCSI Storage Driver for Equallogic PS series SAN

## Description

The iSCSI storage driver for Equallogic PS series SAN provides OpenNebula the support needed to use Equallogic volumes as block-devices for VM images. All the SAN pool image management is done from the OpenNebula front-end with the help of the Equallogic eqlscript utilities, so no special config at the host level is needed for the Equallogic SAN (except the setup for iSCSI mounting).

## Author
  * Joaquin Villanueva (ACB) jvillanueva@acb.es

## Compatibility

This add-on is compatible with OpenNebula 4.4+

## Prerequisites

### OpenNebula Front-end

- python-paramiko
- eqlscript-1.0 from Equallogic Host Integration Tools for Linux (http://support.equallogic.com)
- open-iscsi initiator

### OpenNebula Hosts

- open-iscsi initiator

### Equallogic PS

- Create user with management permissions for the pool
- Grant CLI ssh access to the user
- Configure CHAP/PAP credentials for host iSCSI mounting

## Installation

### OpenNebula Front-End

* Copy these files/directories: 

    - `scripts_eqliscsi.sh` -> `/var/lib/one/remotes/scripts_eqliscsi.sh`
    - `datastore/xpath_multi.rb`-> `/var/lib/one/remotes/datastore`
    - `datastore/eqliscsi` -> `/var/lib/one/remotes/datastore/eqliscsi`
    - `datastore/eqliscsi/eqlscsi.conf.sample` -> `/var/lib/one/remotes/datastore/eqliscsi/eqlscsi.conf`
    - `tm/eqliscsi` -> `/var/lib/one/remotes/tm/eqliscsi`  
    
    > **WARNING**: Check the tm/shared/premigrate and postmigrate scripts before replace them with the eqliscsi supplied ones. If you have customized these scripts, the functions they perform are lost so they must be incorporated to the eqliscsi supplied scripts.  
    
    - `tm/shared/premigrate.eqliscsi` -> `/var/lib/one/remotes/tm/shared/premigrate`
    - `tm/shared/postmigrate.eqliscsi` -> `/var/lib/one/remotes/tm/shared/postmigrate`

        Premigrate/portmigrate scripts use a modified version of xpath.rb (xpath_multi.rb) to get all the instances of these atttributes from the VM template:

        /VM/TEMPLATE/DISK/TM_MAD  
        /VM/TEMPLATE/DISK/SOURCE  
        /VM/TEMPLATE/DISK/PERSISTENT  

        Then, the scripts call the TM premigrate/postmigrate script for every disk attached to the VM.

    The eqliscsi driver needs to call the tm/eqlscsi/premigrate script to locate and login to the correct IQN from the SAN. The premigrate script does a iscsi discovery and login at the host before the VM migration can start. At this point, the SAN volume needs to accept a multiple login (this is the reason for the EQL_MULTIHOST="enable" parameter in eqliscsi.conf) to make the iscsi device available for the hosts involved for the VM migration.

- Configure /etc/iscsi/iscsid.conf. Suggested settings for iscsid.conf:

    ```
    node.startup = manual  
    node.session.auth.authmethod = CHAP  
    node.session.auth.username = username  
    node.session.auth.password = password  
    discovery.sendtargets.auth.authmethod = CHAP  
    discovery.sendtargets.auth.username = username  
    discovery.sendtargets.auth.password = password  
    node.session.cmds_max = 1024  
    node.session.queue_depth = 128  
    node.session.iscsi.FastAbort = No
    ```

    Node startup method must be "manual" to prevent automatic login to discovered targets. Login / logout is managed from the eqliscsi drivers.  
Set authentication method and credentials to match Equallogic pool settings.  
cmds_max, queue_depth and FastAbort are suggested values for correct volume operation with Equallogic SAN.  

- Configure iscsi interface. The eqliscsi driver uses the same iscsi interface for all volume operations. Create one at each host using iscsiadm and set the value of EQL_IFACE in eqlscsi.conf:

    ```
    iscsiadm -m iface -I <eql_iface_name> -o new  
    iscsiadm -m iface -I <eql_iface_name> -o update -n iface.net_ifacename -v <network iscsi iface: eth0, eth1...> -n iface.mtu -v 9000
    ```

- Test target discovery and login


### Hosts

- Copy these directories: 

    `udev/rules.d/*` -> `/etc/udev/rules.d/`

- Configure /etc/iscsi/iscsid.conf (same as front-end config)

- Add oneadmin user to disk group (needed to avoid permission problems with qemu)

## Configuration

### eqlscsi.conf

#### Volume settings

These settings are default values used for volume creation and access. All of them can be overrided at datastore level or image level, setting the new values as attributes.
  
The eqliscsi driver use the next precedence for overriding values:  

`eqlscsi.conf values -> datastore attrs -> image attrs`

- `EQL_HOST`: Management IP of Equallogic SAN 
- `EQL_POOL`: Default volume pool
- `EQL_USER`: Default management user
- `EQL_PASS`: Default management user password

- `EQL_MULTIHOST`: "`enable|disable`"  
  Volume can be logged in from multiple hosts or not. Default value if not set = "enable". If disabled, live migration ends with error as the migration host receiver can't mount the volume. Value set for new volumes.
- `EQL_SECURITY_ACCESS`: "`apply-to <volume|snapshot|both> authmethod <chap|none> username <user_name> ipaddress <ip_address> initiator <initiator_name>`"  
  Security values applied for new volumes. Can be used to apply network/initiator/user restrictions for login, e.g. "`ipaddress 192.168.100.*`"

- `EQL_THINPROVISION`: Sets the thin provisioning values for the volume, if desired.  
  e.g. "`thin-provision thin-min-reserve 50%`"

For more info about the `EQL_SECURITY_ACCESS` and `EQL_THINPROVISION`, see http://psonlinehelp.equallogic.com/V3.3/volume_create.htm

#### eqliscsi settings

- `EQL_BASE_DEVICE="/dev/iscsi"` : path were udev iscsi rules and script link the volume after iscsiadm log-in at hosts
- `EQL_IFACE="eql00"` : Default iscsi network interface used for discovery and connections
- `EQL_WAIT_TIME=1` : Seconds to wait after login/logout operations
- `EQLADM=EqlCliExec.py` : Equallogic CLI utility path/name
