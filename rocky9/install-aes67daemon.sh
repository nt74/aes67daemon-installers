#!/bin/bash
# Script: install-aes67daemon.sh
# Author: nikos.toutountzoglou@svt.se
# Description: AES67 Ravenna Daemon version 1.1.93 installer for Rocky Linux 9

# Stop script on NZEC
set -e
# Stop script if unbound variable found (use ${var:-} if intentional)
set -u
# By default cmd1 | cmd2 returns exit code of cmd2 regardless of cmd1 success
# This is causing it to fail
set -o pipefail

# Variables
PKGDIR="$HOME/src/aes67-daemon"
DRIVERUSRC="https://github.com/bondagit/aes67-linux-daemon.git"

# Enable Extra Packages for Enterprise Linux 9
echo "Welcome to AES67 Ravenna Daemon version 1.1.93 installer script for Rocky Linux 9."

# Update package repos cache
sudo dnf update

# Install all dependencies
echo "Installing all dependencies for building the AES67 Ravenna Daemon package."
sudo dnf install psmisc clang git npm boost-devel valgrind alsa-lib alsa-lib-devel pulseaudio-libs-devel linuxptp systemd-devel avahi-devel kernel-headers-$(uname -r)

# Create a working source dir
mkdir -p $PKGDIR
cd $PKGDIR

# Install latest cmake from source

# check if cmake is already installed
if ! command -v cmake >/dev/null
then
	echo "Installing latest version of cmake from upstream source."
	curl -LO https://github.com/Kitware/CMake/releases/download/v3.28.1/cmake-3.28.1.tar.gz
	tar -xzf cmake-3.28.1.tar.gz
	cd cmake-3.28.1
	./bootstrap --prefix=/usr
	make
	sudo make install
	cd ..
else
	echo "cmake is already installed. Recommended version 3.28.1, using:"
	cmake --version
fi

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
cd systemd
# Create a user for the daemon
sudo useradd -M -l aes67-daemon -c "AES67 Linux daemon"
# Copy the daemon binary (make sure -DWITH_SYSTEMD=ON)
sudo cp -v ../daemon/aes67-daemon /usr/local/bin/aes67-daemon
# Create the daemon webui and script directories
sudo install -v -d -o aes67-daemon /var/lib/aes67-daemon /usr/local/share/aes67-daemon/scripts/ /usr/local/share/aes67-daemon/webui/
# Copy the ptp script
sudo install -v -o aes67-daemon ../daemon/scripts/ptp_status.sh /usr/local/share/aes67-daemon/scripts/
# Copy the webui
sudo cp -v -r ../webui/dist/* /usr/local/share/aes67-daemon/webui/
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
