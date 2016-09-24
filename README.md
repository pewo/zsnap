# zsnap.pl

## Introduction

This is(was) a small script to help me syncronice a zfs filsystems on 
two systems not connected to each other.
The script uses different zfs commands, and has only been tested with zfsonlinux.

## How it works

Some steps on how it's done.

First we take a snapshot of a zfs filesystem, this snapshot is then sent to a file.
Optionally we can compress the file. Next step is splitting the file into smaller
pieces. For all files we create checksum files to be used "on the other side".
When all files are created, they are moved to a transit directory.
This directory could be an USB drive, or some other media that could be moved to
the destination system.

Move the drive or the files to the destination system.

Now all files are check using checksums. The script now merges all files into a zfs 
snapshot, resulting int two idendical filesystem.

## Installation

Get the script and configuration files

git clone https://github.com/pewo/zsnap.git

Copy the zsnap.pl to both the source and destination systems.
Create a config file on the source system.
( zsnap.pl uses zsnap.pl.conf as default )
A minimum config on the source system:

	#--------
	# destdir 
	#--------
	# Used on the sending side.
	# This directory is used for storing the zfs snapshot and 
	# all other files created to support this system
	# No default value
	#
	destdir=/var/tmp/destdir

	#----------
	# transdir
	#----------
	# Used on the sending side.
	# This directory is used as the transit directory.
	# Some other tool should pick the files here and
	# move them to another computer (to "srcdir")
	# No default value
	#
	transdir=/var/tmp/transdir

Create a config file on the destination system.
( zsnap.pl uses zsnap.pl.conf as default )
A minimum config on the destination system:

	#--------
	# srcdir
	#--------
	# Used on the receiving side
	# This is the directory that zsnap.pl looks for files on
	# the receiving side. They got here from "transdir" on
	# the sending side.
	# No default value
	#
	srcdir=/var/tmp/transdir

## Howto run it

Example: 

On the source system we have zfs filesystem called tank/myfs
This filesystem we want to be syncroniced to the destination system.

	src-system# zsnap.pl --mksnap --fs=tank/myfs
	NAME        USED  AVAIL  REFER  MOUNTPOINT
	tank/myfs  27.2K  24.8G  27.2K  /tank/myfs
	send from @ to tank/myfs@20151031232256.snap estimated size is 10K
	total estimated size is 10K
	/var/tmp/transdir/tank.myfs.20151031232256.snap.comp.asc (Ok)
	/var/tmp/transdir/tank.myfs.20151031232256.snap.comp.asc.asc (Ok)
	/var/tmp/transdir/tank.myfs.20151031232256.snap.comp.asc.tot (Ok)
	/var/tmp/transdir/tank.myfs.20151031232256.snap.comp.part.0000 (Ok)

If /var/tmp/transdir (transdir in config) is a USB disk.
Mount the disk on the destination system in /var/tmp/transdir.
(or the directory specified in the config as "srcdir")

	dst-system# zsnap.pl --rdsnap --fs=tank/myfs
	tank.myfs.20151031232256.snap.comp.asc: OK
	tank.myfs.20151031232256.snap.comp.asc.tot: OK
	tank.myfs.20151031232256.snap.comp.part.0000: OK
	tank.myfs.20151031232256.snap.comp: OK
	compressed=0, tank.myfs.20151031232256.snap.comp: data
	tank.myfs.20151031232256.snap is inserted into tank/myfs correctly

Now tank/myfs are syncroniced on both the source and destination system.
One note, the filesystem on the destination system must be readonly.

## Copyright

License: [The MIT License (MIT)](LICENSE)

