#!/usr/bin/perl -w
###############################################################################
###############################################################################
###############################################################################
#
# zsnap.pl - creates and split/checksum/concatenats/restores a zfs snapshot
#
# Written by Peter Wirdemo (peter <dot> wirdemp gmail <dot> com)
#
# Latest version can be found at
# https://sites.google.com/site/peterwirdemo/home/scripts/zsnap.pl
#
###############################################################################
#    Date: Sun Jun 14 01:13:15 CEST 2015
# Version: 0.1.2 Renamed to zsnap.pl
###############################################################################
#    Date: Sun Jun 14 01:13:15 CEST 2015
# Version: 0.1.1 Added support for filesystem lock between execution:
#	sub done($$)
#	sub done_name($$) {
#	sub create_done($$) {
###############################################################################
# Version: 0.1.0 Initial version
###############################################################################
#
########
# Usage: 
########
# % zsnap.pl <--mksnap|--rdsnap> --fs=<zfs filesystem> | --help --force
# % zsnap.pl --mksnap --fs=tank/mirror
#
# This will create the following files:
#
# <destdir>/tank.mirror.20150612104938.snap.comp.asc
# This file contains the sha256sum checksum for all the .part.NNNN files
#     ecb4a <snip> 7cdc40f4cbd *tank.mirror.20150612104938.snap.comp.part.0000
#
# <destdir>/tank.mirror.20150612104938.snap.comp.asc.asc
#  This file containes the sha256sum checksums for .snap.comp.asc
#   and .snap.com.asc.tot files
#     deb21 <snip> 8f6011a5d9 *tank.mirror.20150612104938.snap.comp.asc
#     4865d <snip> 57d7a4e22a *tank.mirror.20150612104938.snap.comp.asc.tot
#
# <destdir>/tank.mirror.20150612104938.snap.comp.asc.tot
# This file contains the sha256sum checksum for the compressd snapshot
#     4eca02bccd <snip> ecb425a4ea4cbd *tank.mirror.20150612104938.snap.comp
#
# <destdir>/tank.mirror.20150612104938.snap.comp.part.0000
# This/These files are the result of the split of the snapshot
#
# % zsnap.pl --rdsnap --fs=tank/mirror
#
# This will insert the snapshot (created above) into the filesystem
#
# --force will use the -F flag on zfs receive:
#
# From the man page:
#
# -F
#  Force a rollback of the file system to the most recent snapshot before
#  performing the receive operation. If receiving an incremental replication
#  stream (for example, one generated by zfs send -R -[iI]), destroy  snapshots
#  and  file  systems that do not exist on the sending side.
###############################################################################
###############################################################################
###############################################################################

use strict;
use Sys::Hostname;
use Data::Dumper;
use Getopt::Long;
use File::Copy;
use File::Basename;
use Fcntl qw(:flock SEEK_END); # import LOCK_* and SEEK_END constants

my $verbose = 0;
my $force = undef;
my($destdir) = "/tmp";
my($transdir) = "/var/tmp";
my($srcdir) = "/tmp";
my($lockdir) = "/tmp";
my($version) = "0.1.2";
my($prog) = "$0";

##################################################
# mylock($lockfile)
# Creates a lock on $lockfile, or dies if it cant
# When used without parameter, remove the
# previoulsy used lockfile ($savename)
##################################################
{
	my($savename) = undef;

	sub mylock {
		my($lockfile) = shift;
		if ( $savename ) {
			close(LOCK);
			unlink($savename);
			return(0);
		}
		$lockfile =~ s/\W/_/g;
		$lockfile = $lockdir . "/." . $lockfile . ".lock";
		$savename = $lockfile;
		if ( open(LOCK,">>$savename") ) {
			my $rc = flock(LOCK, LOCK_EX|LOCK_NB);
			unless ( $rc ) {
				unlink($savename);
				print "Cannot create lock($savename,rc=$rc): $!\n";
			}
			return($rc);
		}
		else {
			return(0);
		}
		return(1);
	}
}


####################################
# done_name($fs)
# constructs file donefile name from 
# filesystem and transdir
####################################
sub done_name($$) {
	my($dir) = shift;
	my($donefile) = shift;
	my($res) = undef;
	$donefile =~ s/\W/./g;
	$donefile = $dir . "/" . $donefile . ".done";
	return($donefile);
}

##########################################
# done($dir,$fs)
# Check if there is a donefile already
# I.e there are files waiting for transfer
##########################################
sub done($$) {
	my($dir) = shift;
	my($donefile) = shift;
	$donefile = done_name($dir,$donefile);
	if ( -f $donefile ) {
		return($donefile) 
	}
	else {
		return(undef);
	}
}

###########################################
# create_done($donefile)
# Create a donefile per filesystem, to stop
# createing of more snapshot until the prev
# files are removed
###########################################
sub create_done($$) {
	my($dir) = shift;
	my($donefile) = shift;
	$donefile = done_name($dir,$donefile);
	unlink($donefile);
	if ( open(OUT,">>$donefile") ) {
		print OUT scalar localtime(time) . "\n";
		close(OUT);
	}
}

##########################################################
# timestamp()
# Returns a string of the current time as YYYYMMDDHHMMSS
##########################################################
sub timestamp() {
	 #  0    1    2     3     4    5     6     7     8
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime(time);
	my($stamp) = sprintf("%4.4d%02.2d%02.2d%02.2d%02.2d%02.2d",
		$year+1900, $mon+1, $mday, $hour, $min, $sec);
	return($stamp);
}

##################################################################
# my_system(@args)
# A wrapper that runs system byt checks the extended return code
##################################################################
sub my_system {
	print "\ncmd=" . join(" ",@_) . "\n" if ( $verbose );
	my($rc) = system(@_);
	if ($rc == -1) {
		print "failed to execute: $!\n";
		return($rc);
	}
	elsif ($rc & 127) {
		die "child died with signal %d, %s coredump\n", ($rc & 127),  ($rc & 128) ? 'with' : 'without';
	}
	else {
		$rc = $rc >> 8;
		print "rc=$rc\n" if ( $verbose );
		return($rc);
	}
}

###########################################
# if_fs($fs)
# Return true or false depending on if the 
#  zfs filesystem exists on the system
###########################################
sub if_fs($) {
	my($fs) = shift;
	my($rc) =  my_system("zfs list $fs");
	if ( $rc ) {
		return(0);
	}
	else {
		return(1);
	}
}

###############################################
# list_snapshot($fs)
# List all the snapshot in the filesystem($fs)
###############################################
sub list_snapshots($) {
	my($fs) = shift;
	unless ( open(POPEN,"zfs list -t snapshot | ") ) {
		die "Unable to list snapshots, exiting...\n" or exit(1);
	}
	my(@arr);
	foreach ( <POPEN> ) {
		next unless ( m/(^$fs\@\d{14}.snap)\s+/ );
		push(@arr,$1);
	}
	close(POPEN);
	return(@arr);
}

###################################
# zfs_get($fs,$attr)
# Get the attr from the filesystem
###################################
sub zfs_get($$) {
	my($fs) = shift;
	my($attr) = shift;
	unless ( open(POPEN,"zfs get -H -o value $attr $fs | ") ) {
		die "Unable to get attr($attr) from $fs exiting...\n" or exit(1);
	}
	my(@arr);
	foreach ( <POPEN> ) {
		next unless ( m/(^.*)$/ );
		push(@arr,$1);
	}
	close(POPEN);
	return(@arr);
}

###########################################################
# first_snapshot($fs)
# Return the first (oldest) snapshot in the filesystem $fs
###########################################################
sub first_snapshot($) {
	my($fs) = shift;
	my(@snaps) = list_snapshots($fs);
	foreach ( sort @snaps ) {
		return($_);
	}
	return(undef);
}

############################################################
# last_snapshot($)
# Return the latest (newest) snapshot in the filesystem $fs
############################################################
sub last_snapshot($) {
	my($fs) = shift;
	my(@snaps) = list_snapshots($fs);
	my($snap) = undef;
	foreach ( sort @snaps ) {
		$snap = $_;
	}
	return($snap);
}

#######################################################################
# create_snapshot($fs)
# Creates and return the name of a new snapshot in the filesystem $fs
# The snapshot name is created as $fs/<timestamp>.snap
# <timestamp> is the result from timestamp()
# if $fs is "tank/mirror", teh result could be as
# tank/mirror@20150612132704.snap
# This function also creates a logfile $fs/.snaplog which is included
# in the snapshot. Should be used for monitoring.
#######################################################################
sub create_snapshot($) {
	my($fs) = shift;
	my($name) = timestamp();
	my($snap) = "$fs\@$name.snap";
	my($rc);
	my($mountp) = zfs_get($fs,"mountpoint");
	if ( $mountp ) {
		my($snaplog) = $mountp . "/.snaplog";
		unlink($snaplog);
		if ( open(SNAPLOG,">$snaplog") ) {
			my($t) = time;
			my($h) = hostname;
			my($str) = "";
			$str .= "fs=$fs\n";
			$str .= "snap=$snap\n";
			$str .= "host=$h\n";
			$str .= "prog=$prog\n";
			$str .= "version=$version\n";
			$str .= "epoch=$t\n";
			$str .= "date=" . scalar localtime($t) . "\n";
			print SNAPLOG $str;
			close(SNAPLOG);
		}
		else {
			print "Could not write to $snaplog: $!\n";
		}
	}
	$rc = my_system("zfs","snapshot",$snap);
	if ( $rc ) {
		print "Could not make snapshot $snap, rc=$rc\n";
		return(undef);
	}
	else {
		return($snap);
	}
}

############################################################
#                                                          #
#       #     #  #    #   #####   #     #     #     ###### #
#      ##   ##  #   #   #     #  ##    #    # #    #     # #
#     # # # #  #  #    #        # #   #   #   #   #     #  #
#    #  #  #  ###      #####   #  #  #  #     #  ######    #
#   #     #  #  #          #  #   # #  #######  #          #
#  #     #  #   #   #     #  #    ##  #     #  #           #
# #     #  #    #   #####   #     #  #     #  #            #
#                                                          #
############################################################
#
# creats, checks and exports a zfs filesystem snapshot into
#  some files, ready to put on a diod and  processed by
#  the rdsnap() function
#
############################################################

sub mksnap($) {
	my($fs) = shift;
	exit(1) unless ( if_fs($fs) );

	my($rc);
	my($snap) = undef;
	my($file) = undef;
	my($last_snap) = last_snapshot($fs);
	
	###################
	# Create snapshot #
	###################
	unless ( $snap ) {
		$snap = create_snapshot($fs);
		unless ( $snap ) {
			exit(1);
		}
		print "Created snapshot $snap\n" if ( $verbose );
	}

	$file = $snap; 
	$file =~ s/\W/./g; # Convert snapname to good filename

	#################################
	# Save delta snapshot to a file #
	#################################
	if ( $last_snap ) {
		#
		# Prev snapshots exists
		# Send delta
		#
		#  zfs send -D -i $PREVIOUSSNAPSHOT $CURRENTSNAPSHOT | xz -c | split -a3 -d -b512m - $OUTFILENAME
		#        gsha256sum ${OUTFILENAME}* >> $NEWFILESFILE
		$rc = my_system("zfs send -RDev -I $last_snap $snap > $destdir/$file");
	}
	else {
		#
		# No prev snapshots exists
		# Send filesystem
		#
		$rc = my_system("zfs send -RDev $snap > $destdir/$file");
	}

	########################################
	# Change directory to output directory #
	########################################
	unless ( chdir($destdir) ) {
		die "chdir($destdir): $!\n" or exit(1);
	}

	#####################
	# Compress snapshot #
	#####################
	my($ext) = ".comp";
	$rc = my_system("xz --verbose --compress --force -1 --suffix=$ext $file"); 
	die "Something went wrong when compressing(xz) the snapshot($file), rc=$rc\n" if ( $rc );

	$file = $file . $ext; # The filename of the commpressed output

	##################
	# Split snapshot #
	##################
	$rc = my_system("split --suffix-length=4 --bytes=512MB --numeric-suffixes $file $file.part."); 
	die "Something went wrong when splitting(split) the compressed snapshot($file), rc=$rc\n" if ( $rc );


	#####################################
	# Checksum snapshot and other files #
	#####################################
	$rc = my_system("sha256sum --binary $file > $file.asc.tot"); 
	die "Something went wrong when checksumming(sha256sum) the file(s): $file\n" if ( $rc );

	$rc = my_system("sha256sum --binary $file.part.* > $file.asc"); 
	die "Something went wrong when checksumming(sha256sum) the file(s): $file.part.*\n" if ( $rc );

	$rc = my_system("sha256sum --binary $file.asc $file.asc.tot > $file.asc.asc"); 
	die "Something went wrong when checksumming(sha256sum) the file(s): $file.asc.tot\n" if ( $rc );

	########################
	# Remove snapshot file #
	########################
	unless ( unlink($file) ) {
		die "unlink($file): $!\n" or exit(1);
	}

	############################################
	# Transfer files from $dstdir to $transdir #
	############################################
	my($src);
	foreach $src ( <$file.*> ) {
		next unless ( -f $src );
		my($dst) = $transdir . "/" . basename($src);
		$rc = move($src,$dst);
		if ( $rc ) {
			print "$dst (Ok)\n";
		}
		else {
			print "$dst ($!)\n";
		}
	}

	return(0);
}

#############################################################
#                                                           #
#       ######   ######    #####   #     #     #     ###### #
#      #     #  #     #  #     #  ##    #    # #    #     # #
#     #     #  #     #  #        # #   #   #   #   #     #  #
#    ######   #     #   #####   #  #  #  #     #  ######    #
#   #   #    #     #        #  #   # #  #######  #          #
#  #    #   #     #  #     #  #    ##  #     #  #           #
# #     #  ######    #####   #     #  #     #  #            #
#                                                           #
#############################################################
#
# Reads, checks and inserts a filesystem snapshot into
#  a zfs filesystem.
#
#############################################################

sub rdsnap($) {
	my($fs) = shift;
	my($rc);

	die "Usage: $0 <zfs filesystem>\n" unless ( $fs );

	#
	# Locate master snapshot info *.snap.comp.asc.asc file
	# and check its checksum ...
	#

	my($asc1);
	my($file) = $fs; 
	$file =~ s/\W/./g; # Convert snapname to good filename
	print "file=$file\n" if ( $verbose );
	chdir($srcdir);
	foreach $asc1 ( <$file.*.snap.comp.asc.asc> ) {

		#
		# Check checksum on .asc.asc 
		# This file contains
		#<filesystem>.<timestamp>.snap.asc / checksums of all .part files
		#<filesystem>.<timestamp>.snap.asc.tot / checksum of the snap
		#
		print "asc1=$asc1\n" if ( $verbose );
		$rc = my_system("sha256sum --check $asc1"); 
		if ( $rc ) {
			die "Checksum error, exiting...\n" or exit(1);
		}


		my($asc2) = $asc1;
		$asc2 =~ s/\.asc$//;
		print "asc2=$asc2\n" if ( $verbose );
		$rc = my_system("sha256sum --check $asc2"); 
		if ( $rc ) {
			die "Checksum error, exiting...\n" or exit(1);
		}

		#
		# Checksum on .asc is ok
		#
		my($snap) = $asc2;
		$snap =~ s/\.asc$//;
		unlink($snap);

		#
		# Concatenate all files into $snap
		# (Reading filenames from asc file)
		#
		my(@files);
		unless ( open(RES,"<$asc2") ) {
			die "Reading $asc2: $!\n" or exit(1);
		}
		foreach ( <RES> ) {
			next unless ( m/$file/ );
			if ( m/($file.*.part.*)/ ) {
				my($part) = $1;
				push(@files,$part);
			}
		}
		close(RES);

		foreach ( @files ) {
			$rc = my_system("cat $_ >> $snap");
			print "Concatenated $_ to $snap, rc=$rc\n" if ( $verbose );
			if ( $rc ) {
				unlink($snap);
				die "Error concatenating to $snap, exiting...\n" or exit(1);
			}
		}

		my($asc3) = $asc2 . ".tot";
		print "asc3=$asc3\n" if ( $verbose );
		$rc = my_system("sha256sum --check $asc3"); 
		if ( $rc ) {
			unlink($snap);
			die "Checksum error, exiting...\n" or exit(1);
		}

		#
		# Decompress using xz
		#
		my($ext) = ".comp";
		$rc = my_system("xz --verbose --decompress --suffix=$ext $snap");
		die "Something went wrong when decompressing(xz) the file $snap, rc=$rc, exiting...\n" if ( $rc );
		$snap =~ s/$ext$//;

		#
		# All files are ok
		# Remove checklsum and part files, leaving only the snapshot
		#
		push(@files,$asc1,$asc2,$asc3);
		foreach ( @files ) {
			$rc = unlink($_);
			print "unlink($_): $rc\n" if ( $verbose );
		}
	}

	#
	# Insert all snapshots into filesystem
	#
	my($snap);
	my($done) = 0;
	foreach $snap ( <$file.*.snap> ) {
		print "snap=$snap\n" if ( $verbose );
		my($cmd) = "zfs receive ";
		if ( $force ) {
			$cmd .= "-F ";
		}
		$cmd .= "$fs < $snap";
		
		my($rc);
		$rc = my_system($cmd);
		if ( $rc ) {
			die "Could not receive snapshot $snap into $fs, rc=$rc\n" or exit(1);
		}
		else {
			print "$snap is inserted into $fs correctly\n";
			unlink($snap);
		}
		$done++;
	}

	unless ( $done ) {
		print "No files found for $fs, check $srcdir directory\n";
	}

	return(0);
}

###############################################################################
###############################################################################
###############################################################################

########################################
#                                      #
#       #     #     #     ###  #     # #
#      ##   ##    # #     #   ##    #  #
#     # # # #   #   #    #   # #   #   #
#    #  #  #  #     #   #   #  #  #    #
#   #     #  #######   #   #   # #     #
#  #     #  #     #   #   #    ##      #
# #     #  #     #  ###  #     #       #
#                                      #
########################################
my $result;
my $mksnap = undef;
my $rdsnap = undef;
my $help = undef;
my $fs = undef;

$result = GetOptions (
		"mksnap" => \$mksnap,
		"rdsnap" => \$rdsnap,
		"help" => \$help,
		"fs=s" => \$fs,
		"verbose"  => \$verbose,
		"force"  => \$force,
);

my($err) = 0;
$err++ unless ( $mksnap || $rdsnap );
$err++ unless ( $fs );
$err++ if ( $help );
if ( $err ) {
	die "Usage($version): $0 <--mksnap|--rdsnap> --fs=<zfs filesystem>\n";
}

unless ( mylock($fs) ) {
	die "Could not create lock, exiting...\n" or exit(1);
}

my($rc) = 0;


if ( $mksnap ) {
	my($df) = done($transdir,$fs);
	if ( defined($df) ) {
		die "There are already files waiting to be transferd($df), exiting...\n" or exit(1);
	}
	$rc = mksnap($fs);
	create_done($transdir,$fs);
}
elsif ( $rdsnap ) {
	my($df) = done($srcdir,$fs);
	unless ( defined($df) ) {
		die "Cant find the transfered files($srcdir), exiting...\n" or exit(1);
	}
	$rc = rdsnap($fs);
	unlink($df);
}
else {
	print "This should not happend...exiting\n";
	$rc = 42;
}

mylock();
exit($rc);

###############################################################################
###############################################################################
###############################################################################
