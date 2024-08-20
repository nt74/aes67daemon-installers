#!/usr/bin/env bash
# Script: install-aes67daemon.sh
# Author: nikos.toutountzoglou@svt.se
# Description: AES67 Ravenna Daemon installer for Rocky Linux 9
# Revision: 1.1

# Stop script on NZEC
set -e
# Stop script if unbound variable found (use ${var:-} if intentional)
set -u
# By default cmd1 | cmd2 returns exit code of cmd2 regardless of cmd1 success
# This is causing it to fail
set -o pipefail

# Variables
PKGDIR="$HOME/src/aes67-daemon"
PKGNAME="aes67-linux-daemon"
PKGVER="2.0.1"
AES67_DAEMON_PKG="https://github.com/bondagit/${PKGNAME}/archive/refs/tags/v${PKGVER}.tar.gz"
AES67_DAEMON_PKG_MD5="01eaa463845e240609695fbf67359a9c"

# Modules Driver (Ver. 1.10)
RAVENNA_DRIVER_PKGVER="1.10"
RAVENNA_DRIVER_PKG="https://github.com/bondagit/ravenna-alsa-lkm/archive/refs/tags/v${RAVENNA_DRIVER_PKGVER}.tar.gz"
RAVENNA_DRIVER_MD5="b67cb0132776c1f4d8d55d1bd0b96dc0"

# Web-UI (Ver. 2.0.1)
WEBUI_PKG="https://github.com/bondagit/aes67-linux-daemon/releases/download/v${PKGVER}/webui.tar.gz"
WEBUI_PKG_MD5="7406813b6ac8c0e147e967b45b3367f9"

# HTTP-Lib (Git-commit: 07c6e58951931f8c74de8291ff35a3298fe481c4)
HTTPLIB_PKG="https://github.com/bondagit/cpp-httplib/archive/07c6e58951931f8c74de8291ff35a3298fe481c4.zip"
HTTPLIB_PKG_MD5="79507658cac131d441f0439a4c218a2d"

# Libraries for FAAC (Ver. 1.30)
FAAC_LIBS_PKG_1="https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Leap_15.6/Essentials/x86_64/libfaac0-1.30-150600.2.pm.4.x86_64.rpm"
FAAC_LIBS_MD5_1="89dbe0ba9f0c158e1d10175102f45191"
FAAC_LIBS_PKG_2="https://ftp.gwdg.de/pub/linux/misc/packman/suse/openSUSE_Leap_15.6/Essentials/x86_64/libfaac-devel-1.30-150600.2.pm.4.x86_64.rpm"
FAAC_LIBS_MD5_2="2b74ca1ce5b62d18c26f27aa667c18ad"

# Check Linux distro
if [ -f /etc/os-release ]; then
	# freedesktop.org and systemd
	. /etc/os-release
	OS=${ID}
	VERS_ID=${VERSION_ID}
	OS_ID="${VERS_ID:0:1}"
elif type lsb_release &>/dev/null; then
	# linuxbase.org
	OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
elif [ -f /etc/lsb-release ]; then
	# For some versions of Debian/Ubuntu without lsb_release command
	. /etc/lsb-release
	OS=$(echo ${DISTRIB_ID} | tr '[:upper:]' '[:lower:]')
elif [ -f /etc/debian_version ]; then
	# Older Debian/Ubuntu/etc.
	OS=debian
else
	# Unknown
	echo "Unknown Linux distro. Exiting!"
	exit 1
fi

# Check if distro is Rocky Linux 9
if [ $OS = "rocky" ] && [ $OS_ID = "9" ]; then
	echo "Detected 'Rocky Linux 9'. Continuing."
else
	echo "Could not detect 'Rocky Linux 9'. Exiting."
	exit 1
fi

# Prompt user with yes/no before proceeding
echo "Welcome to AES67 Ravenna Daemon version $PKGVER installer script for Rocky Linux 9."
while true; do
	read -r -p "Proceed with installation? (y/n) " yesno
	case "$yesno" in
	n | N) exit 0 ;;
	y | Y) break ;;
	*) echo "Please answer 'y/n'." ;;
	esac
done

# Create a working source dir
if [ -d "${PKGDIR}" ]; then
	while true; do
		echo "Source directory '${PKGDIR}' already exists."
		read -r -p "Delete it and reinstall? (y/n) " yesno
		case "$yesno" in
		n | N) exit 0 ;;
		y | Y) break ;;
		*) echo "Please answer 'y/n'." ;;
		esac
	done
fi

rm -fr ${PKGDIR}
mkdir -v -p ${PKGDIR}
cd ${PKGDIR}

# Update package repos cache
sudo dnf update -y

# Install all dependencies
echo "Installing all dependencies for building the AES67 Ravenna Daemon package."
sudo dnf install -y glibc mlocate psmisc clang cmake git npm boost-devel valgrind alsa-lib alsa-lib-devel pulseaudio-libs-devel linuxptp systemd-devel kernel-headers-$(uname -r)
sudo dnf --enablerepo=crb install -y avahi-devel

# Install libfaac (3rd party) dependencies
echo "Installing 'Freeware Advanced Audio Coder' libraries, licensed under 'GPL2'."
curl -o "libfaac0-1.30-150600.2.pm.4.x86_64.rpm" -sL ${FAAC_LIBS_PKG_1}
echo ${FAAC_LIBS_MD5_1} "libfaac0-1.30-150600.2.pm.4.x86_64.rpm" | md5sum -c || exit 1

curl -o "libfaac-devel-1.30-150600.2.pm.4.x86_64.rpm" -sL ${FAAC_LIBS_PKG_2}
echo ${FAAC_LIBS_MD5_2} "libfaac-devel-1.30-150600.2.pm.4.x86_64.rpm" | md5sum -c || exit 1

rpm --nosignature -Uvh "libfaac0-1.30-150600.2.pm.4.x86_64.rpm" || echo $0
rpm --nosignature -Uvh "libfaac-devel-1.30-150600.2.pm.4.x86_64.rpm" || echo $0

# Update ldconfig (Req. glibc, mlocate)
echo "Updating 'ldconfig' and 'updatedb'."
sudo ldconfig
sudo updatedb

# Download latest driver from upstream source
echo "Downloading latest driver from upstream source."
curl -o "${PKGNAME}-${PKGVER}.tar.gz" -sL ${AES67_DAEMON_PKG}
echo ${AES67_DAEMON_PKG_MD5} "${PKGNAME}-${PKGVER}.tar.gz" | md5sum -c || exit 1
tar -xf "${PKGNAME}-${PKGVER}.tar.gz"

# Cd to sourcedir
cd ${PKGNAME}-${PKGVER}

# Download latest 3rdparty upstream source
cd 3rdparty

# Cpp-httplib
curl -o "cpp-httplib.zip" -sL ${HTTPLIB_PKG}
echo ${HTTPLIB_PKG_MD5} "cpp-httplib.zip" | md5sum -c || exit 1
unzip -q "cpp-httplib.zip"
mv cpp-httplib-* cpp-httplib
# Move sourcefile to working directory
mv "cpp-httplib.zip" ${PKGDIR}

# Ravenna-driver-lkm
curl -o "ravenna-alsa-lkm-${RAVENNA_DRIVER_PKGVER}.tar.gz" -sL ${RAVENNA_DRIVER_PKG}
echo ${RAVENNA_DRIVER_MD5} "ravenna-alsa-lkm-${RAVENNA_DRIVER_PKGVER}.tar.gz" | md5sum -c || exit 1
tar -xf "ravenna-alsa-lkm-${RAVENNA_DRIVER_PKGVER}.tar.gz"
rm -f "ravenna-alsa-lkm-${RAVENNA_DRIVER_PKGVER}.tar.gz"
cd ravenna-alsa-lkm-${RAVENNA_DRIVER_PKGVER}
# Fix issue with newer kernels
sed -i 's#include <stdarg.h>#include <linux/stdarg.h>#g' driver/MTAL_LKernelAPI.c
cd driver
make modules

# Webui
cd ../../../webui

curl -o "webui.tar.gz" -sL ${WEBUI_PKG}
echo ${WEBUI_PKG_MD5} "webui.tar.gz" | md5sum -c || exit 1
tar -xf webui.tar.gz
# npm install react-modal react-toastify react-router-dom
npm install --cache "${PKGDIR}/npm-cache"
npm run build
# Move sourcefile to working directory
mv "webui.tar.gz" ${PKGDIR}

# Daemon
cd ../daemon

# Build aes67-daemon
cmake -DCPP_HTTPLIB_DIR="${PKGDIR}/${PKGNAME}-${PKGVER}/3rdparty/cpp-httplib" \
	-DRAVENNA_ALSA_LKM_DIR="${PKGDIR}/${PKGNAME}-${PKGVER}/3rdparty/ravenna-alsa-lkm-${RAVENNA_DRIVER_PKGVER}" \
	-DAVAHI_INCLUDE_DIR=/usr/lib64 \
	-DENABLE_TESTS=ON \
	-DWITH_AVAHI=ON \
	-DFAKE_DRIVER=OFF \
	-DWITH_SYSTEMD=ON .
make
cd ..

# Create systemd service and user
# Prompt user with yes/no before proceeding
while true; do
	read -r -p "Proceed with creating and enabling systemd service 'aes67-daemon.service' and user 'aes67-daemon'? (y/n) " yesno
	case "$yesno" in
	n | N) exit 0 ;;
	y | Y) break ;;
	*) echo "Please answer 'y/n'." ;;
	esac
done

cd systemd
# Create a user for the daemon
sudo useradd -M -l aes67-daemon -c "AES67 Linux daemon"
# Copy the daemon binary (make sure -DWITH_SYSTEMD=ON)
sudo cp -v ../daemon/aes67-daemon /usr/local/bin/aes67-daemon
# Create the daemon webui and script directories
sudo install -v -d -o aes67-daemon /var/lib/aes67-daemon /usr/local/share/aes67-daemon/scripts /usr/local/share/aes67-daemon/webui
# Copy the ptp script
sudo install -v -o aes67-daemon ../daemon/scripts/ptp_status.sh /usr/local/share/aes67-daemon/scripts
# Copy the webui
sudo cp -v -r ../webui/dist/* /usr/local/share/aes67-daemon/webui
# Copy daemon configuration and status files
sudo install -v -o aes67-daemon status.json daemon.conf /etc
# Copy the daemon systemd service definition
sudo cp -v aes67-daemon.service /etc/systemd/system

# Enable the daemon service
sudo systemctl enable aes67-daemon
sudo systemctl daemon-reexec

# Before starting the daemon edit /etc/daemon.conf and make sure the interface_name parameter is set to your ethernet interface.
# Prompt about final steps
echo "Successfully installed AES67 Daemon. All sources are located in '${PKGDIR}'"
echo "Make sure to edit the following files:"
echo "A) /etc/daemon.conf and insert the correct interface_name parameter (i.e. eth0)"
echo "B) /etc/ptp4l.conf and insert the correct parameters (i.e. [eth0] etc)"
echo "Please reboot to activate the newly installed daemon."

exit 0
