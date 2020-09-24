#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use File::Path qw(make_path);

my($fs) = undef;
my($basedir) = undef;


sub zfs_get($$) {
        my($fs) = shift;
        my($attr) = shift;
        unless ( open(POPEN,"zfs get -pH -o value $attr $fs | ") ) {
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

sub get_creation($) {
	my($fs) = shift;
	return(zfs_get($fs,"creation"));
}

sub get_dirname($) {
	my($time) = shift;
	my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($time);
	my($dir) = sprintf("%4.4d/%02.2d",$year+1900, $mon+1);
	return($dir);
}

######################
# Main
######################
GetOptions("fs=s",\$fs,"basedir=s",\$basedir);

unless ( $fs && $basedir ) {
	die "Usage: $0 --fs=<fs> --basedir=<base log directory>\n";
}

################################
# Check if log directory exists
###############################
if ( ! -d $basedir ) {
	chdir($basedir);
	die "chdir($basedir): $!\n";
}

##########################
# Get a list of snapshots
##########################
unless ( open(POPEN,"zfs list -H -t snapshot | " ) ) {
	die "Could not to a list of snapshots\n";
}

####################
# Find my snapshots
####################
my(@snaps) = ();
foreach ( <POPEN> ) {
	my($fspart) = split(/\@/,$_);
	next unless ( $fs eq $fspart );
	my($snap) = split(/\s+/,$_);
	push(@snaps,$snap);
}
close(POPEN);


############################################
# Rotate trough all snapshots a make a diff
############################################
my($prev) = undef;
my($curr);
foreach $curr ( @snaps ) {
	my($fpart,$spart) = split(/\@/,$curr);
	my($creation) = get_creation($curr);
	my($dir) = get_dirname($creation);
	my($logdir) = $basedir . "/" . $dir;

	############################################
	# Create date based log directory structure
	# <basedir>/<year>/<month>
	############################################
	make_path($logdir, {
             verbose => 1,
             mode => 0700,
         });

	#####################################################
	# Create a log filename based on the above directory
	#####################################################
	my($logfile) = $logdir . "/diff." . $spart . ".log";
	my($found) = undef;

	# Check if there are any logfile or compressed logfiles...
	# '.log*'
	foreach ( <$logfile*> ) {
		$found = $_;
	}

	if ( $found ) {
		print "Logfile $found is already there, skipping...\n";
		next;
	}
	unless ( open(LOG,">$logfile") ) {
		print "Writing $logfile: $!\n";
		next;
	}

	my($cmd) = undef;
	unless ( $prev ) {
		$cmd = "zfs diff -FH $curr $fs";
	}
	else {
		$cmd = "zfs diff -FH $prev $curr";
	}

	###########################################################
	# Run the diff command and write the output to the logfile
	###########################################################
	print "$cmd\n";
	unless ( open(POPEN,"$cmd  | " ) ) {
		die "Could not to a list of snapshots\n";
	}
	foreach ( <POPEN> ) {
		print LOG;
	}
	close(POPEN);
	close(LOG);
	$prev = $curr;
}
