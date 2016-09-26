#!/usr/bin/perl -w

use strict;
use Sys::Hostname;

my($host);
$host = hostname;

my($fs) = "/tank/testur";
my($snaplog) = $fs . "/.snaplog";
my($update)  = $fs . "/.updated";

my($cmd) = "/bin/find $fs -newer $snaplog";
unless ( open(FIND,"$cmd |") ) {
	die "Cant run $cmd: $!\n";
} 

my($files) = 0;
foreach ( <FIND> ) {
	next unless ( m/\/testur\// );
	print;
	$files++;
}

if ( $files > 0 ) {
	unless ( open(UPDATE,">$update") ) {
		die "Writing to $update: $!\n";
	}
	print UPDATE "Program: $0, on host: $host, date: " . localtime(time) . "\n";
	close(UPDATE);
	print "Found $files new or updated files.\n";
	exit(0);
}
else {
	print "No new files found, exiting...\n";
	exit(1);
}
