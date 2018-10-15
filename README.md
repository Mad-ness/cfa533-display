# CFA-533 display
The CFA-533 is an intelligent 16x2 character USB LCD with a keypad.
The repository provides a perl written program to set up the IP address/netmask, default gateway, 
and IPMI IP details of a server the LCD module is installed to.


More details about the LCD `this https://www.crystalfontz.com/product/cfa533tmiku-display-module-usb-16x2-character`.


Datasheet `https://www.crystalfontz.com/products/document/3737/CFA533TFHKUv1.4.pdf`.


## Repository information

Along with the provided source the repository contains *.spec* file to build a RPM package for CentOS 7/RHEL 7 and a built such package.


### File cfa533lcd-2.0-1.el7.noarch.rpm
This is a ready to install RPM package on RHEL 7/CentOS 7 system.

## File rpm/cfa533lcd-2.0.tar.gz
It is a compressed directory cfa533lcd-2.0 produced as ``tar czf cfa533lcd-2.0.tar.gz cfa533lcd-2.0/``.

### Directory cfa533lcd/
The directory contains files:
- lcd.pl – main executable program
- lcd.cfg – configuration file
- readwriteconfig – a heler which modifies files */etc/sysconfig/network-scripts/ifcfg-XXX* when needed
- cfa533lcd.service - implements a systemclt unit to start/stop *cfa533lcd* service

**Note:** *lcd.pl* has hard-coded paths to *lcd.cfg* and *readwriteconfig*. Currenty these are reffered to as */opt/cfa533lcd/lcd.cfg* and */opt/cfa533lcd/readwriteconfig*. 
*cfa533.lcd.service* has a path hard-coded the same way.
If you install the program into another place make sure these paths are properly updated.

All these files should be installed on a target system to work properly.

### Directory rpm/
It contains file *cfa533lcd.spec* which is needed to a RPM package and *cfa533lcd-2.0.tar.gz* which is needed to the same purpose.


## How to build an RPM package

**Step 1. Install required package**
```
$ sudo yum install -y rpm-build
```

**Step 2. Prepare file system**

On a build system create a non-privileged user, say *rpm*, and create required subdirectories in its home directory.
```
$ sudo useradd -m rpm
$ sudo su - rpm
$ mkdir ~/rpmbuild/{BUILD,RPMS,SOURCES,SPECS}
```

**Step 3. Copy source files**

Copy *.tar.gz* sources and *.spec* files into right places.
```
$ cp cfa533lcd-2.0.tar.gz ~/rpmbuild/SOURCES/
$ cp cfa533lcd.spec ~/rpmbuild/SPECS/
```

**Step 4. Build an RPM package**
```
$ cd ~/rpmbuild/SPECS
$ rpmbuild -ba cfa533lcd.spec
```
If everything goes without errors the build package will be placed as *~/rpmbuild/RPMS/cfa533lcd-2.0-1.el7.noarch.rpm*. 
See output logs for more details

## Installation
Install the package by any convinient way, for example
```
$ sudo yum install /path/to/rpm/cfa533lcd-2.0-1.el7.noarch.rpm
```
Enable it to be autoloadable when a target system boots
```
$ sudo systemctl enable cfa533lcd
```
And run it 
```
$ sudo systemctl start cfa533lcd
```
Check that it is running
```
$ systemctl status cfa533lcd
```
### Dependencies
The package depends on the basic tools usually presented into each CentOS and many other systems such as **perl** (*lcd.pl*) and **sed** (*readwriteconfig*).

### Test
This program is tested only on CentOS 7.

### Compatibility
These program probably might be run without modifications on any of Linux distributives.

