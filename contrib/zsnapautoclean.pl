#!/usr/bin/perl -w

use strict;
use Data::Dumper;

my($debug) = 0;

sub listsnap() {
	unless( open(POPEN,"/sbin/zfs list -H -o name -t snap |") ) {
		die "Could not list zfs snapshots: $!\n";
	}
	my(@res) = ();
	foreach ( <POPEN> ) {
		chomp;
		push(@res,$_);
	}
	close(POPEN);
	return(@res);
}

my($fs) = shift(@ARGV);
unless ( $fs ) {
	die "Usage: $0 <zfs filesystem, NOT path>\n";
}
print "DEBUG: fs=[$fs]\n" if ( $debug );
$fs =~ s/^\///;
print "DEBUG: fs=[$fs]\n" if ( $debug );
my($newpool,$fsbase) = split(/\//,$fs);
print "DEBUG: newpool=[$newpool], fsbase=[$fsbase]\n" if ( $debug );
($fsbase) = split(/\@/,$fsbase);
print "DEBUG: fsbase=[$fsbase]\n" if ( $debug );

my($fsdir) = "/" . $fs;
print "DEBUG: fsdir=[$fsdir]\n" if ( $debug );

if ( ! -d $fsdir ) {
	chdir($fsdir);
	die "chdir(\"$fsdir\"): $!\n";
}

my($snaplog) = $fsdir . "/.snaplog";
print "DEBUG: snaplog=[$snaplog]\n" if ( $debug );
unless ( open(SNAPLOG,"<$snaplog") ) {
	die "Reading $snaplog: $!\n";
}

my(%remote);
my($remotesnaps);
foreach ( <SNAPLOG> ) {
	next unless ( m/^snapshots=(\w+)\/(.*)/ );
	my($pool) = $1;
	my($snap) = $2;
	$remotesnaps++;
	print "DEBUG: pool=[$pool], snap=[$snap], remotesnaps=[$remotesnaps]\n" if ( $debug );
	print "# Found matching remote snapshot $pool/$snap (keeping)\n";
	$remote{$snap}="$pool/$snap";
}

unless ( $remotesnaps ) {
	print "# Unable to find any remote snapshots for $fs, exiting...\n";
	exit;
}

	
my(@all) = listsnap();
my(%delete);
foreach ( @all ) {
	next unless ( m/$newpool\/($fsbase\@.*)/ );
	my($removesnap) = $1;
	if ( $remote{$removesnap} ) {
		print "# Remote snapshot exists: $remote{$removesnap}\n";
		next;
	}
	print "/sbin/zfs destroy $newpool/$removesnap\n";
}
