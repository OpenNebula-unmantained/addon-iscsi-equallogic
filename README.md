# iSCSI Storage Driver for Equallogic PS series SAN


## Description

The iSCSI storage driver for Equallogic PS series SAN provides OpenNebula the support needed to use Equallogic volumes as block-devices for VM images. All the SAN pool image management is done from the OpenNebula front-end with the help of the Equallogic eqlscript utilities, so no special config at the host level is needed for the Equallogic SAN (except the setup for iSCSI mounting).


## Compatibility

This add-on is compatible with OpenNebula 4.4+


## Prerequisites

### OpenNebula Front-end

- python-paramiko
- eqlscript-1.0

### OpenNebula Hosts

- open-iscsi initiator

### Equallogic PS

- Create user with management permissions for the pool
- Grant CLI ssh access to the user
- Configure CHAP/PAP credentials for host iSCSI mounting


## Installation

### OpenNebula Front-End

Copy these files/directories: 

- `scripts_eqliscsi.sh` -> `/var/lib/one/remotes/scripts_eqliscsi.sh`
- `datastore/xpath_multi.rb`-> `/var/lib/one/remotes/datastore`
- `datastore/eqliscsi` -> `/var/lib/one/remotes/datastore/eqliscsi`
- `datastore/eqliscsi/eqlscsi.conf.sample` -> `/var/lib/one/remotes/datastore/eqliscsi/eqlscsi.conf`
- `tm/eqliscsi` -> `/var/lib/one/remotes/tm/eqliscsi`

> **WARNING**: Check the tm/shared/premigrate and postmigrate scripts before replace them with the eqliscsi supplied ones. If you have customized these scripts, the functions they perform are lost so they must be incorporated to the eqliscsi supplied scripts.

- `tm/shared/premigrate.eqliscsi` -> `/var/lib/one/remotes/tm/shared/premigrate`
- `tm/shared/postmigrate.eqliscsi` -> `/var/lib/one/remotes/tm/shared/postmigrate`

These scripts use a modified version of xpath.rb (xpath_multi.rb) to get all the instances of these atttributes from the VM template:

- /VM/TEMPLATE/DISK/TM_MAD
- /VM/TEMPLATE/DISK/SOURCE
- /VM/TEMPLATE/DISK/PERSISTENT

Then, the scripts call the TM premigrate/postmigrate script for every disk attached to the VM.

The eqliscsi driver needs to call the tm/eqlscsi/premigrate script to locate and login to the correct IQN from the SAN. The premigrate script does a iscsi discovery and login at the host before the VM migration can start. At this point, the SAN volume needs to accept a multiple login (this is the reason for the EQL_MULTIHOST="enable" parameter in eqliscsi.conf) to make the iscsi device available for the hosts involved for the VM migration.

### Hosts

Copy these files/directories: 

- `udev/rules.d/*` -> `/etc/udevvar/lib/one/remotes/scripts_eqliscsi.sh`

## Configuration

### Configuring the System Datastore

To use Equallogic iSCSI drivers, you must configure the system datastore as shared.

~~~
> cat ds.conf
DS_MAD = eqliscsi
TM_MAD = eqliscsi
EQL_HOST = <equallogic management IP address>
EQL_USER = <equallogic user name>
EQL_PASS = <equallogic password>
EQL_POOL = <equallogic pool name>


> onedatastore create ds.conf
ID: 100

> onedatastore list
  ID NAME            CLUSTER  IMAGES TYPE   TM    
   0 system          none     0      fs     shared
   1 default         none     3      fs     shared
 100 production      none     0      iscsi  shared
~~~

The DS and TM MAD can be changed later using the onedatastore update command. You can check more details of the datastore by issuing the onedatastore show command.

> Note that datastores are not associated to any cluster by default, and they are supposed to be accessible by every single host. If you need to configure datastores for just a subset of the hosts take a look to the [Cluster guide](http://opennebula.org/documentation:rel4.4:cluster_guide).

### Configuring DS_MAD and TM_MAD

These values must be added to `/etc/one/oned.conf`

First we add `iscsi` as an option, replace:

~~~
TM_MAD = [
    executable = "one_tm",
    arguments = "-t 15 -d dummy,lvm,shared,fs_lvm,qcow2,ssh,vmfs,ceph"
]
~~~

With:

~~~
TM_MAD = [
    executable = "one_tm",
    arguments = "-t 15 -d dummy,lvm,shared,fs_lvm,qcow2,ssh,vmfs,ceph,iscsi"
]
~~~

After that create a new TM_MAD_CONF section:

~~~
TM_MAD_CONF = [
    name        = "iscsi",
    ln_target   = "NONE",
    clone_target= "SELF",
    shared      = "yes"
]
~~~

Now we add `iscsi` as a new `DATASTORE_MAD` option, replace:

~~~
DATASTORE_MAD = [
    executable = "one_datastore",
    arguments  = "-t 15 -d dummy,fs,vmfs,lvm,ceph"
]
~~~

With:

~~~
DATASTORE_MAD = [
    executable = "one_datastore",
    arguments  = "-t 15 -d dummy,fs,vmfs,lvm,ceph,iscsi"
]
~~~



### Configuring Default Values

The default values can be modified in `/var/lib/one/remotes/datastore/iscsi/iscsi.conf`:

* **HOST**: Default iSCSI target host. Default: `localhost`
* **BASE_IQN**: Default IQN path. Default: `iqn.2012-02.org.opennebula`
* **VG_NAME**: Default volume group. Default: `vg-one`
* **NO_ISCSI**: Lists of hosts (separated by spaces) for which no iscsiadm login or logout is performed. Default: `$HOSTNAME`
* **TARGET_CONF**: File where the iSCSI configured is dumped to (`tgt-admin –dump`). If it poings to `/dev/null`, iSCSI targets will not be persistent. Default: `/etc/tgt/targets.conf`

## Usage 

The iSCSI transfer driver will issue a iSCSI discover command in the target server with iscsiadm. Once the block device is available in the host, the driver will login, mount it and link it to disk.i.

![ds_iscsi](images/ds_iscsi.png)

### Host Configuration

The hosts must have [Open-iSCSI](http://www.open-iscsi.org/) installed, which provides `iscsiadm`.

In order for `iscsiadm` to work, it needs to be able to make a connection on the default iSCSI port (3260) with the iSCSI target server. Firewalls should be adjusted to allow this connection to take place.

The `oneadmin` user must have sudo permissions to execute `iscsiadm`.

## Tuning & Extending

System administrators and integrators are encouraged to modify these drivers in order to integrate them with their iSCSI SAN/NAS solution. To do so, the following is a list of files that may be adapted:

Under `/var/lib/one/remotes/`:

* `datastore/iscsi/iscsi.conf`: Default values for iSCSI parameters
    * **HOST**: Default iSCSI target host
    * **BASE_IQN**: Default IQN path
    * **VG_NAME**: Default volume group
    * **BASE_TID**: Starting TID for iSCSI targets
    * **NO_ISCSI**: Lists of hosts (separated by spaces) for which no iscsiadm login or logout.
* `scripts_common.sh`: includes all the iSCSI methods:
    * `tgt_admin_dump_config` (file): Dumps the configuration to a file
    * `tgt_setup_lun_install` (host, base_path): checks if tgt-setup-lun-one is installed in host. It creates a file to avoid further ssh connections if it's installed.
    * `tgt_setup_lun` (iqn, dev): creates a new iSCSI target using the tgt-setup-lun-one script.
    * `iscsiadm_discovery` (host): Issues iscsiadm discovery.
    * `iscsiadm_login` (iqn, target_host): Logins to an already discovered IQN.
    * `iscsiadm_logout` (target_it): Logs out from an IQN.
    * `is_iscsi` (host): Returns 0 if logins/logouts should be performed on that host.
    * `iqn_get_lv_name` (iqn): Extracts the logical volume name which is encoded in the IQN.
    * `iqn_get_vg_name` (iqn): Extracts the volume group name which is encoded in the IQN.
    * `iqn_get_host` (iqn): Extracts the iSCSI target host which is encoded in the IQN.
* `datastore/iscsi/cp`: Registers a new image. Creates a new logical volume under LVM and sets an iSCSI target for it.
* `datastore/iscsi/mkfs`: Makes a new empty image. Creates a new logical volume under LVM and sets an iSCSI target for it.
* `datastore/iscsi/rm`: Removes the iSCSI target and removes the logical volume.
* `tm/iscsi/ln`: iscsiadm discover and logs in.
* `tm/iscsi/clone`: Creates a new iSCSI target cloning the source underlying LVM logical volumen.
* `tm/iscsi/mvds`: Logs out for shutdown, cancel, delete, stop and migrate.

> All the actions that perform a change in the iSCSI target server dump the configuration at the end of the action, so the iSCSI server configuration remains persistent. This can be disabled by modifying `/var/lib/one/remotes/datastore/iscsi/iscsi.conf`.


## License

  Copyright 2014, Asociacion Clubs Baloncesto (acb.com)

  Author: Joaquin Villanueva

  Portions copyright OpenNebula Project (OpenNebula.org), CG12 Labs

  Licensed under the Apache License, Version 2.0 (the "License"); you may
  not use this file except in compliance with the License. You may obtain
  a copy of the License at

  http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

## Author Contact
  * Joaquin Villanueva
  * jvillanueva@acb.es
