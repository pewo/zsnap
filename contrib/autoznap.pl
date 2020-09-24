#!/usr/bin/perl -w

use strict;
use Data::Dumper;
use File::Basename;

my($error) = "Usage: $0 <zfs filesystem name...not path...>\n";

my($fs) = shift(@ARGV);

unless ( $fs ) {
	die $error;
}

if ( $fs =~ /\// ) {
	die $error;
}

print "Trying to locate zfs $fs\n";

unless ( open(POPEN,"/sbin/zfs list -H |") ) {
	die "zfs list: $!\n";
}

my(%zfs) = ();
foreach ( <POPEN> ) {
	chomp;
	my(@arr) = split(/\s+/,$_);
	$zfs{$arr[0]} = $arr[-1];
}
close(POPEN);

my($dir) = undef;
my($zfs) = "";
my($found_zfs) = 0;
foreach ( sort keys %zfs ) {
	if ( m/(\w+)\/$fs$/ ) {
		$zfs = $1;
		$dir = $zfs{$_};
		$found_zfs++;
	}
}

if ( $found_zfs > 1 ) {
	die "Narrow your search found $found_zfs $fs($zfs), exiting...\n";
}
elsif ( $found_zfs < 1 ) {
	die "Unable to find matching destination zfs for $fs, exiting...\n";
}

print "Found $fs in $zfs and direcotry $dir\n";

print "Trying to find snapshots\n";
my(%snap) = ();
my($snap) = "";
my($found_snap) = 0;
foreach ( </proj/fromyellow/zfs/trans/*.done> ) {
	my($base) = basename($_);
	if ( $base =~ /(\w+\.$fs)\.done/ ) {
		$snap = $1;
		$snap =~ s/\./\//;
		$snap =~ s/\s+$//;
		$found_snap++;
	}
}

if ( $found_snap > 1 ) {
	die "Narrow your search found $found_snap $fs($snap), exiting...\n";
}
elsif ( $found_snap < 1 ) {
	die "Unable to find matching source zfs for $fs, exiting...\n";
}

print "Found [$snap]\n";


my($cmd) = "/root/bin/zsnap.pl --rdsnap --fs=$snap --pool=$zfs " . join(" ",@ARGV);
print $cmd . "\n";
my($rc) = 0;
$rc = system($cmd);
exit($rc) if ( $rc );

my($snaplog) = $dir . "/.snaplog";

unless ( open(ZLOG,"<$snaplog")) {
	die "Reading $snaplog: $!\n";
}

my(@srcsnaps) = ();
my(@dstsnaps) = ();

foreach ( <ZLOG> ) {
	next unless ( m/^snapshots=(.*)/ );
	s/^$snap/$zfs/;
	push(@srcsnaps,$1);
}

print Dumper(\@srcsnaps);

unless ( open(POPEN,"/sbin/zfs list -H -t snap |") ) {
	die "zfs list: $!\n";
}
__END__
foreach ( <POPEN> ) {
	next unless ( m/$zfs/ );
	print;
}
__END__

[root@zfsreceiver smt]# grep ^snapshots= /tank/smt/.snaplog  | wc -l
3
[root@zfsreceiver smt]# zsnap.pl --fs=tank/smt --clean=3

