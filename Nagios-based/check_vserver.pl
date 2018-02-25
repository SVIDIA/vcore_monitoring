#!/usr/bin/perl -w

#
# perl example to enumerate instances of CIM_ComputerSystem
# based on example written by warptrosse@gmail.com
# written by info@svidia.com
#

use strict;
use warnings;
use lib '../../../build/bindings/perl';
use lib '..';
use openwsman;
use DateTime;
use DateTime::Format::DateParse;
use Time::Duration;
use Getopt::Long;
use File::Basename;
use HTTP::Response;
use Date::Manip;

my $Version=          "6.416.1.1";

my $o_help=             undef;  # wan't some help ?
my $o_debug=            0;  # debug
my $o_host =            undef;  # hostname
my $o_timeout = 	undef;  # transport timeout
my $o_verb=             undef;  # verbose mode
my $o_version=          undef;  # print version
my $o_uptime_warn=      undef;  # WARNING alert if system has been up for < specified number of minutes
my $o_uptime_crit=      undef;  # CRITICAL alert if system has been up for < specified number of minutes
my $o_archive_warn=     undef;  # WARNING alert if archive is less than specified number of minutes
my $o_archive_crit=     undef;  # CRITICAL alert if archive is less than specified number of minutes
my $o_lastrec_warn=     undef;  # WARNING alert if last event in archive is less than specified number of minutes
my $o_lastrec_crit=     undef;  # CRITICAL alert if last event in archive is less than specified number of minutes
my $o_port =            undef;  # MI ssl port
my $o_login=            undef;  # Login to access MI
my $o_passwd=           undef;  # Pass to access MI
my $o_scope=            undef;  # defines scope of VServer probes: main service or camera monitoring
my $o_camidx=           undef;  # camera index when cameras scope is used
my $o_no_verify_ssl=	-1;	# Not to verify hostname and peer certificate

my $DEF_UPTIME_WARN_MIN=	720; 
my $DEF_UPTIME_CRIT_MIN=        15;     
my $DEF_ARCHIVE_WARN_MIN=       1440; 
my $DEF_ARCHIVE_CRIT_MIN=       0; #60;
my $DEF_LASTREC_WARN_MIN=       30; 
my $DEF_LASTREC_CRIT_MIN=       60;

my $DEF_PORT =        	    	5986;   
my $DEF_TIMEOUT = 		20;

my $SCOPE_MAIN = "main";
my $SCOPE_CAMERAS = "cameras";
my $DEF_SCOPE = $SCOPE_MAIN;
my $DEF_ALLCAMS = -1;
my $DEF_CAMSTATENUM_DISABLED 	= 0;
my $DEF_CAMSTATENUM_FAULT 	= 1;
my $DEF_CAMSTATENUM_OK 		= 2;
my $DEF_CAMSTATENUM_REC 	= 3;

my $DEF_MI_COMMUNICATION_STATUS_OK = 2; 

my $NAGIOS_OK = 0;
my $NAGIOS_WARN = 1;
my $NAGIOS_CRIT = 2;
my $NAGIOS_UNKN = 3;

my $NAGIOS_STATUS_OK = "OK";
my $NAGIOS_STATUS_WARN = "WARNING";
my $NAGIOS_STATUS_CRIT = "CRITICAL";
my $NAGIOS_STATUS_UNKN = "UNKNOWN";
my @NAGIOS_STATUS = ( $NAGIOS_STATUS_OK, $NAGIOS_STATUS_WARN, $NAGIOS_STATUS_CRIT, $NAGIOS_STATUS_UNKN);

my $exit_code = -1;
my $exit_status = $NAGIOS_STATUS_OK;


sub print_usage {
    my $bname = basename($0);
    print "Usage:\n";
    print "    get VServer info:\n";
    print "      $bname -H <host> -l login -x passwd [-p <port>] [-t <transport timeout>] [-v <no verify>] [-w <uptime warn> -e <uptime crit>] [-a <archive span warn> -b <archive span crit>] [-f <archive last record warn> -g <archive last record crit>]\n";
    print "         defaults:\n";
    print "            -p <port> 				= $DEF_PORT\n";
    print "            -v <0..1> 				= 0 - hostname and peer ssl certificate verification\n";
    print "            -t <transport timeout>		= $DEF_TIMEOUT seconds\n";
    print "            -w <uptime warn> 			= $DEF_UPTIME_WARN_MIN minutes\n";
    print "            -e <uptime crit> 			= $DEF_UPTIME_CRIT_MIN minutes\n";
    print "            -a <archive span warn> 		= $DEF_ARCHIVE_WARN_MIN minutes\n";
    print "            -b <archive span crit> 		= $DEF_ARCHIVE_CRIT_MIN minutes\n";
    print "            -f <archive last record warn> 	= $DEF_LASTREC_WARN_MIN minutes\n";
    print "            -g <archive last record crit> 	= $DEF_LASTREC_CRIT_MIN minutes\n";
    print "         warning and critical thresholds are specified in munites, 0 - disables a threshold notification\n";
    print "\n";
    print "    get all connected cameras info:\n";
    print "      $bname -s cameras -c 0 -H <host> -l login -x passwd [-p <port>]\n";
    print "\n";
    print "    get individual camera info:\n";
    print "      $bname -s cameras -c <camera 1..16> -H <host> -l login -x passwd [-p <port>]\n";
    print "\n";
}

sub is_num {
  my $num = shift;
  if (!length($num)) { 
	return 0; 
  }
  if ( $num =~ /^(\d+\.?\d*)|(^\.\d+)$/ ) { 
	return 1 ;
  }
  return 0;
}

sub help {
   print "\nSVIDIA VServer Plugin for Nagios v.",$Version,"\n";
   print "2017 (c) SVIDIA LLC\n\n";
   print_usage();
}

sub p_version { print "version : $Version\n"; }

sub update_exit_code {
	my $llexit_code = shift;
	if ( $exit_code < $llexit_code) {
                $exit_code = $llexit_code;
		$exit_status = $NAGIOS_STATUS[$llexit_code];
        }
}

sub my_err_exit {
	my $llexit_code = shift;
	my $error_message = shift;
	$llexit_code = $NAGIOS_UNKN if(!defined($llexit_code));

#	print STDERR $error_message;

	$exit_code = $llexit_code;
	$exit_status = $NAGIOS_STATUS[$llexit_code];

	if (defined($error_message)) {
		printf "VServer %s: %s\n", $exit_status, $error_message;
	} else {
		printf "VServer status: %s\n", $exit_status;
	}
	exit $exit_code;
}

sub check_options {
    Getopt::Long::Configure ("bundling");
        GetOptions(
        'h'     => \$o_help,            'help'          => \$o_help,
        'd'     => \$o_debug,           'debug'         => \$o_debug,
        'v:s'   => \$o_no_verify_ssl,   'no_verify_ssl:s' 	=> \$o_no_verify_ssl,
        's:s'   => \$o_scope,           'scope:s'    	=> \$o_scope,
        'H:s'   => \$o_host,            'hostname:s'    => \$o_host,
        'p:s'   => \$o_port,            'port:s'        => \$o_port,
        't:s'   => \$o_timeout,         'transport_timeout:s'	=> \$o_timeout,
        'l:s'   => \$o_login,           'login:s'       => \$o_login,
        'x:s'   => \$o_passwd,          'passwd:s'      => \$o_passwd,
        'V'     => \$o_version,         'version'       => \$o_version,
        'c:s'   => \$o_camidx,          'camidx:s'    	=> \$o_camidx,
        'w:s'   => \$o_uptime_warn,     'uptime_warning:s'     	=> \$o_uptime_warn,
        'e:s'   => \$o_uptime_crit,     'uptime_critical:s'    	=> \$o_uptime_crit,
        'a:s'   => \$o_archive_warn,    'archive_warning:s'     => \$o_archive_warn,
        'b:s'   => \$o_archive_crit,    'archive_critical:s'    => \$o_archive_crit,
        'f:s'   => \$o_lastrec_warn,    'lastrec_warning:s'     => \$o_lastrec_warn,
        'g:s'   => \$o_lastrec_crit,    'lastrec_critical:s'    => \$o_lastrec_crit,
    );
    if (defined ($o_help) ) { 
	help(); 
	my_err_exit $NAGIOS_UNKN;
    }
    if (defined($o_version)) { 
	p_version(); 
	my_err_exit $NAGIOS_UNKN;
    }

    if (!defined($o_host) || (!defined($o_login) || !defined($o_passwd)) ) {
	print "Please specify hostname and login info\n"; 
	print_usage(); 
	my_err_exit $NAGIOS_UNKN, "argument error";
    }

    if (!defined($o_port) || !is_num($o_port) || $o_port < 10 || $o_port > 65535 ) {
	    $o_port = $DEF_PORT;
    }	

    if (!defined($o_scope) || ($o_scope ne $SCOPE_MAIN && $o_scope ne $SCOPE_CAMERAS)) {
	if ( defined($o_scope) && $o_scope eq "camera" ) { $o_scope = $SCOPE_CAMERAS; }
	else { $o_scope = $DEF_SCOPE; }
    }	

    if (!defined($o_uptime_warn) || !is_num($o_uptime_warn) || $o_uptime_warn < 0 ) {
	    $o_uptime_warn = $DEF_UPTIME_WARN_MIN;
    }
    $o_uptime_warn = $o_uptime_warn * 60;	
    if (!defined($o_uptime_crit) || !is_num($o_uptime_crit) || $o_uptime_crit < 0 ) {
	    $o_uptime_crit = $DEF_UPTIME_CRIT_MIN;
    }
    $o_uptime_crit = $o_uptime_crit * 60;


    if (!defined($o_archive_warn) || !is_num($o_archive_warn) || $o_archive_warn < 0 ) {
	    $o_archive_warn = $DEF_ARCHIVE_WARN_MIN;
    }
    $o_archive_warn = $o_archive_warn * 60;	
    if (!defined($o_archive_crit) || !is_num($o_archive_crit) || $o_archive_crit < 0 ) {
	    $o_archive_crit = $DEF_ARCHIVE_CRIT_MIN;
    }
    $o_archive_crit = $o_archive_crit * 60;

    if (!defined($o_lastrec_warn) || !is_num($o_lastrec_warn) || $o_lastrec_warn < 0 ) {
            $o_lastrec_warn = $DEF_LASTREC_WARN_MIN;
    }
    $o_lastrec_warn = $o_lastrec_warn * 60;
    if (!defined($o_lastrec_crit) || !is_num($o_lastrec_crit) || $o_lastrec_crit < 0 ) {
            $o_lastrec_crit = $DEF_LASTREC_CRIT_MIN;
    }
    $o_lastrec_crit = $o_lastrec_crit * 60;	

    if (!defined($o_camidx) || !is_num($o_camidx) || $o_camidx < 0 || $o_camidx > 16) {
            $o_camidx = 0;
    }
    $o_camidx --;

    if (!defined($o_timeout) || !is_num($o_timeout) || $o_timeout <= 0 || $o_timeout > 180) {
            $o_timeout = $DEF_TIMEOUT;
    }

    if (defined($o_no_verify_ssl) && !length($o_no_verify_ssl)) {
            $o_no_verify_ssl = 1;
    } elsif (!defined($o_no_verify_ssl) || !is_num($o_no_verify_ssl) || $o_no_verify_ssl < 0) {
            $o_no_verify_ssl = 0;
    }

}


sub update_archive_span_status {
	my $span_sec = shift;
	my $llexit_code = shift;

}

########## MAIN #######
update_exit_code($NAGIOS_OK);
check_options();
if ($o_debug) {
	print "o_port=$o_port\n";
	print "o_timeout=$o_timeout\n";
	print "o_scope=$o_scope\n";
	print "o_no_verify_ssl=$o_no_verify_ssl\n";
	print "o_camidx=$o_camidx\n";
	print "o_uptime_warn=$o_uptime_warn\n";
	print "o_uptime_crit=$o_uptime_crit\n";
	print "o_archive_warn=$o_archive_warn\n";
	print "o_archive_crit=$o_archive_crit\n";
	print "o_lastrec_warn=$o_lastrec_warn\n";
	print "o_lastrec_crit=$o_lastrec_crit\n";
}
#exit 1;

if ($o_debug) {
	openwsman::set_debug(1);
}

# Create client instance.
my $client = new openwsman::Client::($o_host, $o_port, '/wsman', 'https', $o_login, $o_passwd)
    or my_err_exit $NAGIOS_UNKN, "Could not create wsman client handler";

# Alternate way.
# my $client = new openwsman::Client::('https://user:password@host_name_or_ip:5986')
#  or die print "[ERROR] Could not create client handler.\n";

my $options = new openwsman::ClientOptions::()
    or my_err_exit $NAGIOS_UNKN, "Could not create wsman client options handler";
#$options->set_flags($openwsman::FLAG_ENUMERATION_OPTIMIZATION);

$client->transport()->set_auth_method($openwsman::BASIC_AUTH_STR);
if ($o_no_verify_ssl) {
	$client->transport()->set_verify_peer(0);
	$client->transport()->set_verify_host(0);
}
$client->transport()->set_timeout($o_timeout);

my $cam_cumul_status = $NAGIOS_OK;
my $cam_total_count = 0;
my $cam_healthy_count = 0;
my $uri = 'http://schemas.microsoft.com/wbem/wsman/1/wmi/root/cimv2/';
my $filter = undef;

if ($o_scope eq $SCOPE_MAIN) {
	$uri = $uri . 'SVIDIA_VServer';
} elsif ($o_scope eq $SCOPE_CAMERAS) {
	if ($o_camidx == $DEF_ALLCAMS) {
		$uri = $uri . 'SVIDIA_VServerCamera';
	} else {
		$uri = $uri . '*';
		$filter = new openwsman::Filter::()
 			or my_err_exit $NAGIOS_UNKN, "Could not create wsman filter";
		$filter->wql(sprintf("Select * from SVIDIA_VServerCamera WHERE InstanceID=%d",$o_camidx));
	} 
} else {
	my_err_exit $NAGIOS_UNKN, "unexpected scope";
}

my $result; # Used to store obtained data.
my @list;   # Instances list.

# Enumerate from external schema (uri).
# (options, filter, resource uri)

$result = $client->enumerate($options, $filter, $uri);
unless($result && $result->is_fault eq 0) {
	my $lerr_msg;
	if (defined($client->fault_string)) {
		$lerr_msg = $client->fault_string 
	} else {
		my $lhttp_r = new HTTP::Response($client->response_code);
#	print $hr->status_line . "\n";
		$lerr_msg = $lhttp_r->status_line;
	}
	$lerr_msg = sprintf("Could not enumerate VServer MI instances\n%s (err=%d response=%d)\n" , $lerr_msg, $client->last_error, $client->response_code);
    	my_err_exit $NAGIOS_UNKN, $lerr_msg;
}


# Get context.
my $context = $result->context();

while($context) {
    # Pull from local server.
    # (options, filter, resource uri, enum context)
    $result = $client->pull($options, undef, $uri, $context);
    next unless($result);

    # Get nodes.
    # soap body -> PullResponse -> items
    my $nodes = $result->body()->find($openwsman::XML_NS_ENUMERATION, "Items")->child();
    next unless($nodes);

    # Get items.
    my $items;
    for((my $cnt = 0) ; ($cnt<$nodes->size()) ; ($cnt++)) {
	if ($o_scope eq $SCOPE_CAMERAS) {
		my $myprop = ( $nodes->get($cnt)->name() eq "CameraStateEnum" && $nodes->get($cnt)->text() );
		$cam_cumul_status = $NAGIOS_CRIT if ($myprop && $nodes->get($cnt)->text() == $DEF_CAMSTATENUM_FAULT);
		if ($o_camidx == $DEF_ALLCAMS) {
			$cam_total_count ++ if ($myprop && $nodes->get($cnt)->text() != $DEF_CAMSTATENUM_DISABLED);
			$cam_healthy_count ++ if ($myprop && $nodes->get($cnt)->text() > $DEF_CAMSTATENUM_FAULT);
		}
	}
        $items->{$nodes->get($cnt)->name()} = $nodes->get($cnt)->text();
    }
    push @list, $items;

    $context = $result->context();
}

# Release context.
$client->release($options, $uri, $context) if($context);

if (! @list) {
	my_err_exit $NAGIOS_UNKN, "VServer MI provider returns no results";
}

# Print output.
foreach(@list) {

 my %route = %$_;

 if (! $route{'CommunicationStatus'} || $route{'CommunicationStatus'} != $DEF_MI_COMMUNICATION_STATUS_OK ) {
	my $comm_err_msg = "VServer MI communication error";
	my $ret_res = $route{'ReturnResult'};
	if ($ret_res && is_num($ret_res)) {
		$comm_err_msg = sprintf("%s: %d", $comm_err_msg, $ret_res);
	}
	if ($route{'ReturnMessage'}) {
		$comm_err_msg = sprintf("%s\n%s", $comm_err_msg, $route{'ReturnMessage'});
	}
	my_err_exit $NAGIOS_CRIT, $comm_err_msg;
 } 


 if ($o_scope eq $SCOPE_MAIN)
 {   
    my $rec_status = $NAGIOS_STATUS_OK;
    if ( $route{'RecordingStateEnum'} == 0 ) {
	update_exit_code ( $NAGIOS_CRIT );
	$rec_status = $NAGIOS_STATUS_CRIT;
    }

    my $uptime_sec = $route{'VServerUpTimeInSeconds'};	
    my $uptime_days = $uptime_sec /60 /60 /24;
    if ($o_uptime_crit && $uptime_sec < $o_uptime_crit) {
	update_exit_code ( $NAGIOS_CRIT );
    } elsif ($o_uptime_warn && $uptime_sec < $o_uptime_warn) {
	update_exit_code ( $NAGIOS_WARN );
    }

    my $uptime_perfdata = sprintf("uptime=%ds;%d;%d", $uptime_sec ,$o_uptime_warn, $o_uptime_crit);

    my $archive_span_sec = $route{'ArchiveSpanInSeconds'};
    my $archive_span = $archive_span_sec /60 /60 /24;

    my $archive_span_status = "";
    if ( $o_archive_crit && $archive_span_sec < $o_archive_crit ) {
	update_exit_code ( $NAGIOS_CRIT );
	$archive_span_status = sprintf("%s: archive is too short: " ,$NAGIOS_STATUS_CRIT);
    } elsif ( $o_archive_warn && $archive_span_sec < $o_archive_warn ) {
	update_exit_code ( $NAGIOS_WARN );
	$archive_span_status = sprintf("%s: archive is too short: " ,$NAGIOS_STATUS_WARN);
    }	
    my $archive_span_perfdata = sprintf("archive=%ds;%d;%d", $archive_span_sec, $o_archive_warn, $o_archive_crit);


    my $today = DateTime->now( time_zone => 'local' )->set_time_zone('floating');
    my $till = DateTime::Format::DateParse->parse_datetime($route{'ArchiveMostRecentDate'});
    my $dur = $today->subtract_datetime_absolute($till);
    my $no_archive = ($route{'ArchiveMostRecentDate'} =~ "1899");

    my $arch_status = $NAGIOS_STATUS_OK;
    if ( $o_lastrec_warn && $dur->seconds() > $o_lastrec_warn ) {
        update_exit_code ( $NAGIOS_WARN );
	$arch_status = $NAGIOS_STATUS_WARN;
    } elsif ( $o_lastrec_crit && $dur->seconds() > $o_lastrec_crit ) {
        update_exit_code ( $NAGIOS_CRIT );
	$arch_status = $NAGIOS_STATUS_CRIT;
    }

    my $backup_status = $NAGIOS_STATUS_OK;
    if ($route{'BackupStateEnum'} == 2) {
	update_exit_code ( $NAGIOS_WARN );
	$backup_status = $NAGIOS_WARN;
    }

    my $backup_space_used_perfdata = "";
    if ($route{'BackupStateEnum'} > 0) {
	$backup_space_used_perfdata = sprintf("backup_space_used=%d\%", $route{'BackupSpaceUsedPercent'});
    }

    my $vserver_info = sprintf("VServer info: name=%s ver='%s' running_on=%s", $route{'VServerName'}, $route{'VServerVersion'}, $route{'CSName'});
	
    printf("%s %s|%s %s %s\n", $route{'VServerName'}, $exit_status, $archive_span_perfdata, $uptime_perfdata, $backup_space_used_perfdata);
    printf("Recording status %s: %s\n", $rec_status, $route{'RecordingState'});
    if ($no_archive) {
	    printf("Archive status %s: archive has no events\n", $rec_status);
    } else {
	    printf("Archive status %s: the last event was recorded %s\n", $arch_status, from_now($dur->seconds(),1));
    }
    printf("Archive span %s%s\n", $archive_span_status, duration($archive_span_sec,1));
    printf("Archive from %s\n", $route{'ArchiveEarliestDate'});
    printf("Archive till %s\n", $route{'ArchiveMostRecentDate'});

    if ($route{'BackupStateEnum'} > 0) {
        printf("Backup status %s: %s\n", $backup_status, $route{'BackupState'});
    	printf("Backup: the most recent date %s\n", $route{'BackupMostRecentDate'});
    	printf("Backup: space used %d\%\n", $route{'BackupSpaceUsedPercent'});
    } else {
        printf("%s\n", $route{'BackupState'});
    }

    printf("%s\n", $vserver_info);
    last;

 } elsif ( $o_scope eq $SCOPE_CAMERAS) {
	
    if (defined($cam_cumul_status)) {
	if ( $o_camidx == $DEF_ALLCAMS ) {
		update_exit_code($NAGIOS_WARN) if $cam_cumul_status ne $NAGIOS_OK;
		printf("%s cameras: %s|enabled=%d healthy=%d\n", $route{'VServerName'}, $exit_status, $cam_total_count, $cam_healthy_count);
	} else {
		update_exit_code($NAGIOS_CRIT) if $cam_cumul_status ne $NAGIOS_OK;
		printf("%s %s: %s\n", $route{'VServerName'}, $route{'Description'}, $route{'CameraState'});
		last;
	}
	$cam_cumul_status = undef;
    }	
	
    my $cam_status = undef;
    my $cam_enum = $route{'CameraStateEnum'};
    if ($cam_enum == $DEF_CAMSTATENUM_FAULT) {
#	$cam_status = sprintf("%s FAULT", $NAGIOS_STATUS_CRIT);
	$cam_status = "FAULT";
    } elsif  ($cam_enum == $DEF_CAMSTATENUM_OK) {
	$cam_status = sprintf("%s", $NAGIOS_STATUS_OK);
    } elsif  ($cam_enum == $DEF_CAMSTATENUM_REC) {
	$cam_status = sprintf("%s, recording", $NAGIOS_STATUS_OK);
#    } elsif ($cam_enum == $DEF_CAMSTATENUM_DISABLED) {
#	$cam_status = "disabled";
    }

    if (defined($cam_status)) {	
	    printf("%s (%s): %s\n", $route{'Name'}, $route{'VServerCameraName'}, $cam_status);
    }	
	
 } else {
	my_err_exit $NAGIOS_UNKN, "unexpected scope";
 }


#    my_err_exit $NAGIOS_CRIT , "tsetstst-crit";
#    my_err_exit $NAGIOS_UNKN , "tsetstst--unkn";
#    my_err_exit $NAGIOS_WARN , "tsetstst--warn";

}

exit $exit_code
