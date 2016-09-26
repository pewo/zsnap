#!/usr/bin/perl -w

use strict;

print "Starting $0 " . localtime(time) . "\n";

my($zfs) = shift(@ARGV);

unless ( $zfs ) {
	die "Usage: $0 <filesystem>\n";
}


if ( ! -d $zfs ) {
	chdir($zfs);
	die "chdir($zfs): $!\n";
}

my($updated) = $zfs . "/.updated";

if ( ! -r $updated ) {
	die "No update file present ($updated)\n";
}
else {
	unlink($updated);
}

#
# remove leading /
#
$zfs =~ s/\///;

my $cmd = "/root/bin/zsnap.pl --mksnap --fs=$zfs";
print $cmd . "\n";
system($cmd);

print "Done $0 " . localtime(time) . "\n";
