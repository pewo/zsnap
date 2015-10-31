#!/usr/bin/perl -w

use strict;
use File::Basename;

my($rel) = "el6";
my($arch) = "x86_64";

my($spl) = "http://archive.zfsonlinux.org/downloads/zfsonlinux/spl/spl-0.6.5.3.tar.gz";
my($zfs) = "http://archive.zfsonlinux.org/downloads/zfsonlinux/zfs/zfs-0.6.5.3.tar.gz";
my($asc) = "http://archive.zfsonlinux.org/downloads/zfsonlinux/zfs/zfs-0.6.5.3.sha256.asc";


sub get($) {
	my($url) = shift;
	return unless ( $url );
	return unless ( $url =~ /^http/ );
	my($out) = basename($url);
	unless ( -r $out ) {
		my($cmd) = "wget -O $out $url";
		print "$cmd\n";
		system($cmd);
	}
	if ( -r $out ) {
		return($out);
	}
	else  {
		return(undef);
	}
}

##############################################################################
# Get spl
##############################################################################
my($splfile) = get($spl);
if ( $splfile ) {
	print "splfile=$splfile\n";
}
else {
	die "Could not get $spl, exiting...\n";
}

##############################################################################
# Get zfs
##############################################################################
my($zfsfile) = get($zfs);
if ( $zfsfile ) {
	print "zfsfile=$zfsfile\n";
}
else {
	die "Could not get $zfs, exiting...\n";
}	

##############################################################################
# Verify checksum
##############################################################################
my($ascfile) = get($asc);
if ( $ascfile ) {
	print "ascfile=$ascfile\n";
	my($cmd) = "sha256sum -c $ascfile";
	unless ( open(POPEN,"$cmd |") ) {
		die "Running cmd $cmd: $!\n";
	}
	my($error) = 0;
	foreach ( <POPEN> ) {
		$error++ unless ( m/\s+OK$/ );
		print "error=$error, $_";
	}
	close(POPEN);
	if ( $error ) {
		die "sha256sum mismatch, exiting...\n" or exit(1);
	}
}
else {
	die "Could not get $asc, exiting...\n";
}	

##############################################################################
# Install various needed tools
##############################################################################
system("yum install -y DKMS");
system("yum groupinstall -y \"Development Tools\"");
system("yum install -y vzkernel-devel zlib-devel libuuid-devel libblkid-devel libselinux-devel parted lsscsi wget");


##############################################################################
# Unpack spl
##############################################################################
my($basedir) = $splfile;
my($olddir) = $basedir . ".old";
$basedir =~ s/\.tar.*//;
unless ( $basedir =~ /^\w+/ ) {
	print "Bad directory name, $basedir, exiting...\n";
}
if ( -d $basedir ) {
	print "Removing old directory\n";
	system("mv $basedir $olddir");
}
print "Extracting from $splfile...\n";
system("tar -xzf $splfile");

##############################################################################
# Build spl
##############################################################################
system("cd $basedir; ./configure --with-config=user; make rpm-utils rpm-dkms");

##############################################################################
# Unpack zfs
##############################################################################
$basedir = $zfsfile;
$olddir = $basedir . ".old";
$basedir =~ s/\.tar.*//;
unless ( $basedir =~ /^\w+/ ) {
	print "Bad directory name, $basedir, exiting...\n";
}
if ( -d $basedir ) {
	print "Removing old directory\n";
	system("mv $basedir $olddir");
}
print "Extracting from $zfsfile...\n";
system("tar -xzf $zfsfile");

##############################################################################
# Build zfs
##############################################################################
system("cd $basedir; ./configure --with-config=user; make rpm-utils rpm-dkms");

##############################################################################
# Get spl version
##############################################################################
my($splver) = undef;
if ( $spl =~ /-(\d+)\.(\d+)\.(\d+)\.(\d+)/ ) {
	$splver = join(".",$1,$2,$3,$4);
}
unless ( $splver ) {
	die "Unabe to locate spl version, exiting...\n";
}
else {
	print "splver=$splver\n";
}

##############################################################################
# Get zfs version
##############################################################################
my($zfsver) = undef;
if ( $zfs =~ /-(\d+)\.(\d+)\.(\d+)\.(\d+)/ ) {
	$zfsver = join(".",$1,$2,$3,$4);
}
unless ( $zfsver ) {
	die "Unabe to locate zfs version, exiting...\n";
}
else {
	print "zfsver=$zfsver\n";
}

##############################################################################
# Build list of packages to install
##############################################################################
my($subrel) = 1;
my(@rpmlist) = (
	"spl-$splver/spl-$splver-$subrel.$rel.$arch.rpm",
	"spl-$splver/spl-dkms-$splver-$subrel.$rel.noarch.rpm",
	"zfs-$zfsver/libnvpair1-$zfsver-$subrel.$rel.$arch.rpm",
	"zfs-$zfsver/libuutil1-$zfsver-$subrel.$rel.$arch.rpm",
	"zfs-$zfsver/libzfs2-$zfsver-$subrel.$rel.$arch.rpm",
	"zfs-$zfsver/libzpool2-$zfsver-$subrel.$rel.$arch.rpm",
	"zfs-$zfsver/zfs-$zfsver-$subrel.$rel.$arch.rpm",
	"zfs-$zfsver/zfs-dkms-$zfsver-$subrel.$rel.noarch.rpm",
	"zfs-$zfsver/zfs-dracut-$zfsver-$subrel.$rel.$arch.rpm",
);

my($file);
my($yumcmd) = "yum localinstall -y";
foreach $file ( @rpmlist ) {
	my($ok) = -M $file;
	if ( $ok ){
		print "file=$file, OK\n";
		$yumcmd .= " $file";
	}
	else {
		die "Missing file $file, exiting...\n" unless ( $ok );
	}
}


##############################################################################
# Install
##############################################################################
print $yumcmd;
system("$yumcmd");
