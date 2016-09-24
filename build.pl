#!/usr/bin/perl -w

#
# build.pl for spl/zfs 0.6.5.8
#
# Only tested on CentOS 6.8 running vzkernel (OpenVZ)
#
#
##############################################################################
# When there is a problem installing, you could try to remove all spl and zfs
# packages and remove old files...
# sudo find /lib/modules/ \( -name "splat.ko" -or -name "zcommon.ko" -or -name "zpios.ko" -or -name "spl.ko" -or -name "zavl.ko" -or -name "zfs.ko" -or -name "znvpair.ko" -or -name "zunicode.ko" \) -exec /bin/rm {} \;
##############################################################################
use strict;
use File::Basename;

my($rel) = undef;
my($arch) = "x86_64";
my($version) = "0.6.5.8";
my($yum) = "/usr/bin/sudo /usr/bin/yum";

unless ( open(IN,"</etc/redhat-release") ) {
	die "/etc/redhat-release: $!\n";
}

foreach ( <IN> ) {
	next unless ( m/release\s(\d+)/ );
	$rel = "el" . $1;
}
die "Unknown el version" unless ( $rel );


my($spl) = "https://github.com/zfsonlinux/zfs/releases/download/zfs-$version/spl-$version.tar.gz";
my($zfs) = "https://github.com/zfsonlinux/zfs/releases/download/zfs-$version/zfs-$version.tar.gz";
my($asc) = "https://github.com/zfsonlinux/zfs/releases/download/zfs-$version/zfs-$version.sha256.asc";


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
# Retrieve and cache of all installed rpm packages
##############################################################################
{
	my(@rpm) = ();

	sub allrpm() {
		return(@rpm) if ( $#rpm >= 0 );

		unless ( open(POPEN,"rpm -qa |") ) {
			die "Unable to get rpm list: $!\n";
		}
	
		foreach ( <POPEN> ) {
			chomp;
			push(@rpm,$_);
		}
		close(POPEN);
		return(@rpm);
	}
}

##############################################################################
# remove all spl/zfs packages installled on the local system
##############################################################################
sub remove_spl_and_zfs() {
	my(@rpm) = allrpm();
	my(@remove) = ();
	my($cmd) = undef;
	foreach ( @rpm ) {
		next if ( m/zfs-release/ );
		$cmd .= "$_ " if (m/zfs|spl/);
		#push(@remove,$_) if ( m/zfs|spl/ );
	}
	unless ( $cmd ) {
		print "Nothing to remove...\n";
	}
	else {
		$cmd = "$yum erase -y $cmd";
		system($cmd);
	}
}

##############################################################################
# Try to fins out the kernel and install corresponfing headers and devel
##############################################################################
sub kernel() {
	my($release) = `uname -r`;
	unless ( $release ) {
		die "Unable to get kernel release\n";
	}
	chomp($release);

	my($arch) = `arch`;
	unless ( $arch ) {
		die "Unable to get kernel arch\n";
	}
	chomp($arch);


	unless ( open(POPEN,"rpm -qa |") ) {
		die "Unable to get rpm list: $!\n";
	}

	my(@rpm) = ();
	foreach ( <POPEN> ) {
		chomp;
		push(@rpm,$_);
	}
	close(POPEN);

	my($kernel) = undef;
	foreach ( @rpm ) {
		if  ( m/(^.*kernel-$release\.$arch)/ ) {
			$kernel = $1;
			last;
		}
	}
	unless ( $kernel ) {
		die "Unable to find running kernel\n";
	}

	my($name) = undef;
	if ( $kernel =~ /(^.*kernel)-$release/ ) {
		$name = $1;
	}
	unless ( $name ) {
		die "Unable to find kernel name\n";
	}

	my($headers) = 0;
	my($devel) = 0;
	foreach ( @rpm ) {
		$headers++ if ( m/^$name-headers-$release\.$arch/ );
		$devel++ if ( m/^$name-devel-$release\.$arch/ );
	}
	if ( $headers ) {
		print "kernel headers is installed\n";
	}
	else {
		system("$yum install -y $name-headers-$release.$arch");
	}

	if ( $devel ) {
		print "kernel devel is installed\n";
	}
	else {
		system("$yum install -y $name-devel-$release.$arch");
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
system("$yum install -y DKMS");
system("$yum groupinstall -y \"Development Tools\" parted lsscsi wget ksh");
system("$yum install -y zlib-devel libattr-devel libuuid-devel libblkid-devel libselinux-devel libudev-devel");
kernel();

##############################################################################
# Check if spl is installed
##############################################################################
my($splstatus) = 0;
$splstatus = system("rpm -qa spl | grep $version");
print "debug# splstatus=$splstatus\n";
my($zfsstatus) = 0;
$zfsstatus = system("rpm -qa zfs | grep $version");
print "debug# zfsstatus=$zfsstatus\n";

if ( $splstatus && $zfsstatus ) {
	remove_spl_and_zfs();
}

if ( $splstatus ) {
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
	system("cd $basedir; ./configure --with-config=user; make pkg-utils rpm-dkms");
	system("cd $basedir; $yum localinstall -y *.noarch.rpm");
	system("cd $basedir; $yum localinstall -y *.x86_64.rpm");
}

$splstatus = system("rpm -qa spl | grep $version");
if ( $splstatus ) {
	die "Unable to install spl version $version, exiting...\n";
}
else {
	print "spl $version is installed\n";
}

##############################################################################
# Check if zfs is installed
##############################################################################
if ( $zfsstatus ) {
	##############################################################################
	# Unpack zfs
	##############################################################################
	my($basedir) = $zfsfile;
	my($olddir) = $basedir . ".old";
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
	system("cd $basedir; ./configure --with-config=user; make pkg-utils rpm-dkms");
	system("cd $basedir; $yum localinstall -y *.noarch.rpm");
	system("cd $basedir; $yum localinstall -y *.x86_64.rpm");
}
$zfsstatus = system("rpm -qa zfs | grep $version");
if ( $zfsstatus ) {
	die "Unable to install zfs version $version, exiting...\n";
}
else {
	print "zfs $version is installed\n";
}
