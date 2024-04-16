#!/bin/bash
# Script: install-aes67daemon.sh
# Author: nikos.toutountzoglou@svt.se
# Description: AES67 Ravenna Daemon version 1.1.93 installer for Rocky Linux 9
# Revision: 1.0

# Stop script on NZEC
set -e
# Stop script if unbound variable found (use ${var:-} if intentional)
set -u
# By default cmd1 | cmd2 returns exit code of cmd2 regardless of cmd1 success
# This is causing it to fail
set -o pipefail

# Variables
PKGDIR="$HOME/src/aes67-daemon"
PKGVER="1.1.93"
DRIVERUSRC="https://github.com/bondagit/aes67-linux-daemon.git"

# Check Linux distro
if [ -f /etc/os-release ]; then
	# freedesktop.org and systemd
	. /etc/os-release
	OS=${ID}
	VERS_ID=${VERSION_ID}
	OS_ID="${VERS_ID:0:1}"
elif type lsb_release &> /dev/null; then
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
while true
do
	read -r -p "Proceed with installation? (y/n) " yesno
	case "$yesno" in
		n|N) exit 0;;
		y|Y) break;;
		*) echo "Please answer 'y/n'.";;
	esac
done

# Update package repos cache
sudo dnf update

# Install all dependencies
echo "Installing all dependencies for building the AES67 Ravenna Daemon package."
sudo dnf install psmisc clang cmake git npm boost-devel valgrind alsa-lib alsa-lib-devel pulseaudio-libs-devel linuxptp systemd-devel kernel-headers-$(uname -r)
sudo dnf --enablerepo=crb install avahi-devel

# Update ldconfig
echo "Updating 'ldconfig' and 'updatedb'."
sudo ldconfig
sudo updatedb

# Create a working source dir
mkdir -p $PKGDIR
cd $PKGDIR

# Download latest driver from upstream source
echo "Downloading latest driver from upstream source."
git clone $DRIVERUSRC
cd aes67-linux-daemon

# Download latest 3rdparty upstream source
cd 3rdparty

# cpp-httplib
git clone https://github.com/bondagit/cpp-httplib.git
cd cpp-httplib
git checkout 42f9f9107f87ad2ee04be117dbbadd621c449552
cd ..

# ravenna-driver-lkm
git clone --single-branch --branch aes67-daemon https://github.com/bondagit/ravenna-alsa-lkm.git
cd ravenna-alsa-lkm
# Fix issue with newer kernels
sed -i 's#include <stdarg.h>#include <linux/stdarg.h>#g' driver/MTAL_LKernelAPI.c
cd driver
make modules

# webui
cd ../../../webui
wget https://github.com/bondagit/aes67-linux-daemon/releases/latest/download/webui.tar.gz
tar -xzf webui.tar.gz
# npm install react-modal react-toastify react-router-dom
npm i
npm run build
rm webui.tar.gz

# daemon
cd ../daemon
# Fix compilation issue with i32ClockJitter
#sed -i 's/i32Jitter/i32ClockJitter/g' session_manager.cpp
#sed -i 's/i32Jitter/i32ClockJitter/g' driver_manager.cpp

# Build aes67-daemon
cmake -DCPP_HTTPLIB_DIR="$PKGDIR/aes67-linux-daemon/3rdparty/cpp-httplib" \
    -DRAVENNA_ALSA_LKM_DIR="$PKGDIR/aes67-linux-daemon/3rdparty/ravenna-alsa-lkm" \
    -DAVAHI_INCLUDE_DIR=/usr/lib64 \
    -DENABLE_TESTS=ON \
    -DWITH_AVAHI=ON \
    -DFAKE_DRIVER=OFF \
    -DWITH_SYSTEMD=ON .
make
cd ..

# Create systemd service and user
# Prompt user with yes/no before proceeding
while true
do
	read -r -p "Proceed with creating and enabling systemd service 'aes67-daemon.service' and user 'aes67-daemon'? (y/n) " yesno
	case "$yesno" in
		n|N) exit 0;;
		y|Y) break;;
		*) echo "Please answer 'y/n'.";;
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
echo "Successfully installed AES67 Daemon. Make sure to edit the following files:"
echo "A) /etc/daemon.conf and insert the correct interface_name parameter (i.e. eth0)"
echo "B) /etc/ptp4l.conf and insert the correct parameters (i.e. [eth0] etc)"
echo "Please reboot to activate the newly installed daemon."

exit 0
