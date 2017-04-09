#!/bin/sh

/sbin/lsmod | grep ^zfs > /dev/null
if [ $? -eq 0 ]; then
	echo "Zfs is installed..."
	exit
fi

cd /local/build

rm -rf spl-0.6.5.9
tar -xzf spl-0.6.5.9.tar.gz
cd spl-0.6.5.9
sh  ./autogen.sh 
./configure --with-spec=generic
make && make pkg-utils pkg-kmod
yum localinstall *.`arch`.rpm

rm -rf zfs-0.6.5.9
tar xvf zfs-0.6.5.9.tar.gz 
cd zfs-0.6.5.9
sh autogen.sh 
./configure --with-spl=/local/build/spl-0.6.5.9 --with-spec=generic
make && make pkg-utils pkg-kmod
yum localinstall *.`arch`.rpm
/sbin/modprobe zfs
