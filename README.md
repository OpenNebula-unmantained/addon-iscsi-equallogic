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

Copy these directories: 

- `udev/rules.d/*` -> `/etc/udev/rules.d/`


## Configuration


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
