# RHEL7 guide https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/7/html-single/rpm_packaging_guide/index
Name:           cfa533lcd
Version:        2.0
Release:        1%{?dist}
Summary:        Userspace daemon to interact with CFA-533 LCD module
Group:          Applications/Hardware
License:        Proprietary, not for public use
Source0:        %{name}-%{version}.tar.gz
Packager:       Dmitrii Mostovshchikov <dmadm2008@gmail.com>
BuildRoot:      %{_tmppath}/%{name}-root
Prefix:         %{_prefix}
BuildArch:      noarch
Requires:       perl sed


%description
The module provides a userspace program (daemon) and program the Crystalfontz CFA-533 16x2 LCD module.
It allows to set up ip and netmask on network interfaces and IPMI interface and to set up 
a default gateway.

%prep
%setup -q -n %{name}-%{version}

%install
test -d $RPM_BUILD_ROOT/opt/%{name} || mkdir -p $RPM_BUILD_ROOT/opt/%{name}
install -m 0755 lcd.pl $RPM_BUILD_ROOT/opt/%{name}/lcd.pl
install -m 0644 lcd.cfg $RPM_BUILD_ROOT/opt/%{name}/lcd.cfg
install -m 0755 readwriteconfig $RPM_BUILD_ROOT/opt/%{name}/readwriteconfig
test -d $RPM_BUILD_ROOT/usr/lib/systemd/system || mkdir -p $RPM_BUILD_ROOT/usr/lib/systemd/system
install -m 0644 %{name}.service $RPM_BUILD_ROOT/usr/lib/systemd/system/%{name}.service

%post
/usr/bin/systemctl daemon-reload

%postun
/usr/bin/systemctl daemon-reload

%clean
rm -rf $RPM_BUILD_ROOT

%files
%defattr(-,root,root,-)
%config(noreplace) /opt/%{name}/lcd.cfg
%dir /opt/%{name}/
/opt/%{name}/lcd.pl
/opt/%{name}/readwriteconfig
/usr/lib/systemd/system/%{name}.service

%changelog
* Sun Oct 14 2018 Dmitrii Mostovshchikov <dmadm2008@gmail.com>, Denis Zuev <flashdumper@gmail.com>
- Packaged all files into a RPM package
- Updated lcd.pl to correctly read and set IP/netmask information on OS network interfaces

