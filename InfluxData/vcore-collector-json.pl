#!/usr/bin/perl -w

#
# perl example to enumerate instances of CIM_ComputerSystem
# based on example written by warptrosse@gmail.com
# written by dk SVIDIA LLC
# produces json object

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
use Time::Local;
use DateTime::TimeZone;
use JSON;
#use Data::Dumper;

my $Version=          "8.15.3";

my $o_help=             undef;  # wan't some help ?
my $o_debug=            0;  # debug
my $o_host =            undef;  # hostname
my $o_timeout = 	undef;  # transport timeout
my $o_verb=             undef;  # verbose mode
my $o_version=          undef;  # print version
my $o_uptime_warn=      undef;  # WARNING alert if system has been up for < specified number of days
my $o_uptime_crit=      undef;  # CRITICAL alert if system has been up for < specified number of days
my $o_archive_warn=     undef;  # WARNING alert if archive is less than specified number of days
my $o_archive_crit=     undef;  # CRITICAL alert if archive is less than specified number of days
my $o_lastrec_warn=     undef;  # WARNING alert if last event in archive is less than specified number of minutes
my $o_lastrec_crit=     undef;  # CRITICAL alert if last event in archive is less than specified number of minutes
my $o_port =            undef;  # MI ssl port
my $o_login=            undef;  # Login to access MI
my $o_passwd=           undef;  # Pass to access MI
my $o_scope=            undef;  # defines scope of probes: service overview or camera monitoring
my $o_camidx=           undef;  # camera index when cameras scope is used
my $o_no_verify_ssl=	-1;	# Not to verify hostname and peer certificate
my $o_legacy_vserver=	0;	# Check leagcy VServer MI

my $DEF_UPTIME_WARN_DYS=	0.50; 
my $DEF_UPTIME_CRIT_DYS=        15.0 /60 /24;     
my $DEF_ARCHIVE_WARN_DYS=       1.00; 
my $DEF_ARCHIVE_CRIT_DYS=       0.00; #0.04;
my $DEF_LASTREC_WARN_MIN=       30.0; 
my $DEF_LASTREC_CRIT_MIN=       60.0;

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
my $NAGIOS_ERR = 4;

my $NAGIOS_STATUS_OK = "OK";
my $NAGIOS_STATUS_WARN = "WARNING";
my $NAGIOS_STATUS_CRIT = "CRITICAL";
my $NAGIOS_STATUS_UNKN = "UNKNOWN";
my $NAGIOS_STATUS_ERROR = "ERROR";
my @NAGIOS_STATUS = ( $NAGIOS_STATUS_OK, $NAGIOS_STATUS_WARN, $NAGIOS_STATUS_CRIT, $NAGIOS_STATUS_UNKN, $NAGIOS_STATUS_ERROR);

my $exit_code = -1;
my $exit_status = $NAGIOS_STATUS_OK;

my $PEER_TYPE = 'VCore';

sub print_usage {
    my $bname = basename($0);
    print "Usage:\n";
    print "    get VCore info:\n";
    print "      $bname -H <host> -l login -x passwd [-p <port>] [-t <transport timeout>] [-v <no verify>] [-w <uptime warn> -e <uptime crit>] [-a <archive span warn> -b <archive span crit>] [-f <archive last record warn> -g <archive last record crit>]\n";
    print "         defaults:\n";
    print "            -p <port> 				= $DEF_PORT\n";
    print "            -v <0..1> 				= 0 - hostname and peer ssl certificate verification\n";
    print "            -t <transport timeout>		= $DEF_TIMEOUT seconds\n";
    print "            -o <0..2> 				= 0 - check against VCore MI instances\n";
    print "             					= 1 - enables legacy VServer check\n";
    print "             					= 2 - enables legacy VServer check w backup\n";
    print "            -w <uptime warn> 			= $DEF_UPTIME_WARN_DYS days\n";
    print "            -e <uptime crit> 			= $DEF_UPTIME_CRIT_DYS days\n";
    print "            -a <archive span warn> 		= $DEF_ARCHIVE_WARN_DYS days\n";
    print "            -b <archive span crit> 		= $DEF_ARCHIVE_CRIT_DYS days\n";
    print "            -f <archive last record warn> 	= $DEF_LASTREC_WARN_MIN minutes\n";
    print "            -g <archive last record crit> 	= $DEF_LASTREC_CRIT_MIN minutes\n";
    print "         setting 0 - disables a threshold notification\n";
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
   print "\nSVIDIA VCore Plugin for Nagios v.",$Version,"\n";
   print "2017 (c) SVIDIA LLC\n\n";
   print_usage();
}

sub p_version { print "version : $Version\n"; }

sub influx_exit_code {
	return $exit_code < $NAGIOS_UNKN ? 0 : $exit_code;
}

sub update_exit_code {
	my $llexit_code = shift;
	if ( $exit_code < $llexit_code) {
                $exit_code = $llexit_code;
		$exit_status = $NAGIOS_STATUS[$llexit_code];
        }
}

sub make_json {
	my $params = shift;
	my %paramhash = %$params;
	my $json = JSON->new->allow_nonref;
	my $enable = 1;
	$json = $json->utf8([$enable]);
	$json = $json->canonical([$enable]);
        my $json_text   = $json->encode( \%paramhash );
       	print "$json_text\n";
}

sub my_err_exit {
	my $llexit_code = shift;
	my $error_message = shift;
	$llexit_code = $NAGIOS_UNKN if(!defined($llexit_code));

#	print STDERR $error_message;

	$exit_code = $llexit_code;
	$exit_status = $NAGIOS_STATUS[$llexit_code];

	my %json_out;
    	$json_out{'result_status'} = $exit_status;
    	$json_out{'result_code'} = $exit_code;
    	$json_out{'peer_type'} = $PEER_TYPE;

	if (defined($error_message)) {
    		$json_out{'error'} = $error_message;
#		printf "%s %s: %s\n", $PEER_TYPE, $exit_status, $error_message;
#	} else {
#		printf "%s status: %s\n", $PEER_TYPE, $exit_status;
	}

	make_json(\%json_out);
	
#	exit $exit_code;
	exit influx_exit_code();
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
        'o:s'   => \$o_legacy_vserver,  'legacy_vserver:s'    => \$o_legacy_vserver,
    );
    if (defined ($o_help) ) { 
	help(); 
	my_err_exit $NAGIOS_ERR; #$NAGIOS_UNKN;
    }
    if (defined($o_version)) { 
	p_version(); 
	my_err_exit $NAGIOS_ERR; #$NAGIOS_UNKN;
    }

    if (!defined($o_host) || (!defined($o_login) || !defined($o_passwd)) ) {
	print "Please specify hostname and login info\n"; 
	print_usage(); 
	my_err_exit $NAGIOS_ERR, "argument error";
    }

    if (!defined($o_port) || !is_num($o_port) || $o_port < 10 || $o_port > 65535 ) {
	    $o_port = $DEF_PORT;
    }	

    if (!defined($o_scope) || ($o_scope ne $SCOPE_MAIN && $o_scope ne $SCOPE_CAMERAS)) {
	if ( defined($o_scope) && $o_scope eq "camera" ) { $o_scope = $SCOPE_CAMERAS; }
	else { $o_scope = $DEF_SCOPE; }
    }	

    if (!defined($o_uptime_warn) || !is_num($o_uptime_warn) || $o_uptime_warn < 0 ) {
	    $o_uptime_warn = $DEF_UPTIME_WARN_DYS;
    }
#    $o_uptime_warn = $o_uptime_warn * 60;	
    if (!defined($o_uptime_crit) || !is_num($o_uptime_crit) || $o_uptime_crit < 0 ) {
	    $o_uptime_crit = $DEF_UPTIME_CRIT_DYS;
    }
#    $o_uptime_crit = $o_uptime_crit * 60;


    if (!defined($o_archive_warn) || !is_num($o_archive_warn) || $o_archive_warn < 0 ) {
	    $o_archive_warn = $DEF_ARCHIVE_WARN_DYS;
    }
#    $o_archive_warn = $o_archive_warn * 60;	
    if (!defined($o_archive_crit) || !is_num($o_archive_crit) || $o_archive_crit < 0 ) {
	    $o_archive_crit = $DEF_ARCHIVE_CRIT_DYS;
    }
#    $o_archive_crit = $o_archive_crit * 60;

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

    if (!defined($o_legacy_vserver) || !is_num($o_legacy_vserver) || $o_legacy_vserver < 0) {
            $o_legacy_vserver = 0;
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
	print "o_legacy_vserver=$o_legacy_vserver\n";
}
#exit 1;

if ($o_debug) {
	openwsman::set_debug(1);
}

# Create client instance.
my $client = new openwsman::Client::($o_host, $o_port, '/wsman', 'https', $o_login, $o_passwd)
    or my_err_exit $NAGIOS_ERR, "Could not create wsman client handler";

# Alternate way.
# my $client = new openwsman::Client::('https://user:password@host_name_or_ip:5986')
#  or die print "[ERROR] Could not create client handler.\n";

my $options = new openwsman::ClientOptions::()
    or my_err_exit $NAGIOS_ERR, "Could not create wsman client options handler";
#$options->set_flags($openwsman::FLAG_ENUMERATION_OPTIMIZATION);

$client->transport()->set_auth_method($openwsman::BASIC_AUTH_STR);
if ($o_no_verify_ssl) {
	$client->transport()->set_verify_peer(0);
	$client->transport()->set_verify_host(0);
}
$client->transport()->set_timeout($o_timeout);


my $uri_main_scope = 'SVIDIA_VCore';
my $uri_cams_scope = 'SVIDIA_VCoreCamera';
my $noun_VCoreUpTimeInSeconds = 'VCoreUpTimeInSeconds';
my $noun_VCoreName = 'VCoreName';
my $noun_VCoreVersion = 'VCoreVersion';
my $noun_VCoreCameraName = 'VCoreCameraName';

my $noun_RecordingState = 'RecordingState';
my $noun_ArchiveSpanInSeconds = 'ArchiveSpanInSeconds';
my $noun_ArchiveEarliestDate = 'ArchiveEarliestDate';
my $noun_ArchiveMostRecentDate = 'ArchiveMostRecentDate';
my $noun_NumberOfCamerasLicensed = 'NumberOfCamerasLicensed';
my $noun_ReturnResult = 'ReturnResult';
my $noun_ReturnMessage = 'ReturnMessage';
my $noun_CommunicationStatus = 'CommunicationStatus';
my $noun_RecordingStateEnum = 'RecordingStateEnum';
my $noun_CSTimeBias = 'CSTimeBias';
my $noun_Description = 'Description';
my $noun_CameraState = 'CameraState';
my $noun_CameraStateEnum ='CameraStateEnum';
my $noun_Name = 'Name';
my $noun_CSName = 'CSName';
if ($o_legacy_vserver) {
	$PEER_TYPE = 'VServer';
	$uri_main_scope = 'SVIDIA_VServer';
	$uri_cams_scope = 'SVIDIA_VServerCamera';
	$noun_VCoreUpTimeInSeconds = 'VServerUpTimeInSeconds';
	$noun_VCoreName = 'VServerName';
	$noun_VCoreVersion = 'VServerVersion';
	$noun_VCoreCameraName = 'VServerCameraName';
}

my $cam_cumul_status = $NAGIOS_OK;
my $cam_total_count = 0;
my $cam_healthy_count = 0;
my $cam_faulty_count = 0;
my $uri = 'http://schemas.microsoft.com/wbem/wsman/1/wmi/root/cimv2/';
my $filter = undef;
my $tzbias = 0;

my %json_out;
my %json_sub_peer;
my %json_sub_uptime;
my %json_sub_recording;
my %json_sub_archive;
my %json_sub_backup;
my %json_sub_lastrec;
my %json_sub_cameras;
my %json_sub_cameras_h;
my %json_sub_cameras_f;

if ($o_scope eq $SCOPE_MAIN) {
	$uri = $uri . $uri_main_scope;
} elsif ($o_scope eq $SCOPE_CAMERAS) {
	if ($o_camidx == $DEF_ALLCAMS) {
		$uri = $uri . $uri_cams_scope;
	} else {
		$uri = $uri . '*';
		$filter = new openwsman::Filter::()
 			or my_err_exit $NAGIOS_ERR, "Could not create wsman filter";
		$filter->wql(sprintf("Select * from %s WHERE InstanceID=%d",$uri_cams_scope,$o_camidx));
	} 
} else {
	my_err_exit $NAGIOS_ERR, "unexpected scope";
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
	$lerr_msg = sprintf("Could not enumerate %s MI instances\n%s (err=%d response=%d)\n" , $PEER_TYPE, $lerr_msg, $client->last_error, $client->response_code);
    	my_err_exit $NAGIOS_ERR, $lerr_msg;
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
			$cam_faulty_count ++ if ($myprop && $nodes->get($cnt)->text() == $DEF_CAMSTATENUM_FAULT);
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
	my_err_exit $NAGIOS_UNKN, sprintf("%s MI provider returns no results", $PEER_TYPE);
}


# Print output.
foreach(@list) {

 my %route = %$_;

 if (! $route{$noun_CommunicationStatus} || $route{$noun_CommunicationStatus} != $DEF_MI_COMMUNICATION_STATUS_OK ) {
	my $comm_err_msg = sprintf("%s MI communication error", $PEER_TYPE);
	my $ret_res = $route{$noun_ReturnResult};
	if ($ret_res && is_num($ret_res)) {
		$comm_err_msg = sprintf("%s: %d", $comm_err_msg, $ret_res);
	}
	if ($route{$noun_ReturnMessage}) {
		$comm_err_msg = sprintf("%s\n%s", $comm_err_msg, $route{$noun_ReturnMessage});
	}
	my_err_exit $NAGIOS_CRIT, $comm_err_msg;
 } 


 if ($o_scope eq $SCOPE_MAIN)
 {   
    my $rec_status = $NAGIOS_STATUS_OK;
    if ( $route{$noun_RecordingStateEnum} == 0 ) {
	update_exit_code ( $NAGIOS_CRIT );
	$rec_status = $NAGIOS_STATUS_CRIT;
    }

    my $uptime_status = "";
    my $uptime_sec = $route{$noun_VCoreUpTimeInSeconds};	
    my $uptime_days = $uptime_sec /60 /60 /24;
    if ($o_uptime_crit && $uptime_days < $o_uptime_crit) {
	update_exit_code ( $NAGIOS_CRIT );
	$uptime_status = sprintf("%s: %s has been restarted" ,$NAGIOS_STATUS_CRIT, $PEER_TYPE);
    } elsif ($o_uptime_warn && $uptime_days < $o_uptime_warn) {
	update_exit_code ( $NAGIOS_WARN );
	$uptime_status = sprintf("%s: %s has been restarted" ,$NAGIOS_STATUS_WARN, $PEER_TYPE);
    }

#    my $uptime_perfdata = sprintf("uptime_days=%.2f;%.2f;%.2f", $uptime_days ,$o_uptime_warn, $o_uptime_crit);

    my $archive_span_sec = $route{$noun_ArchiveSpanInSeconds};
    my $archive_span = $archive_span_sec /60 /60 /24;

#    my $archive_span_status = "";
    my $archive_span_status = $NAGIOS_OK;
    if ( $o_archive_crit && $archive_span < $o_archive_crit ) {
	update_exit_code ( $NAGIOS_CRIT );
	$archive_span_status = sprintf("%s: archive is too short: " ,$NAGIOS_STATUS_CRIT);
    } elsif ( $o_archive_warn && $archive_span < $o_archive_warn ) {
	update_exit_code ( $NAGIOS_WARN );
	$archive_span_status = sprintf("%s: archive is too short: " ,$NAGIOS_STATUS_WARN);
    }	
#    my $archive_span_perfdata = sprintf("archive_days=%.2f;%.2f;%.2f", $archive_span, $o_archive_warn, $o_archive_crit);

    my $today;
    if ($o_legacy_vserver) {
	$today = DateTime->now( time_zone => 'local' )->set_time_zone('floating');
    } else {
	my $tz = DateTime::TimeZone->new( name => 'local' );
#	my @t = localtime(time);
#	my $gmt_offset_in_mins = (timelocal(@t) - timegm(@t)) / 60;
    	$today = DateTime->now()->subtract(minutes => $route{$noun_CSTimeBias});
#    	$today = $today->add(minutes => $gmt_offset_in_mins);
	my $nowdst = $tz->is_dst_for_datetime( DateTime->now( time_zone => 'local' ) );
	if ($nowdst) {
	    	$today = $today->add(minutes => 60);
	}
#	printf("remote offset=%d min, is_dst=%s\n",$route{$noun_CSTimeBias},$nowdst);
    }
    my $till = DateTime::Format::DateParse->parse_datetime($route{$noun_ArchiveMostRecentDate});
    my $dur = $today->subtract_datetime_absolute($till);
    my $no_archive = ($route{$noun_ArchiveMostRecentDate} =~ "1899");

    my $arch_status = $NAGIOS_STATUS_OK;
    if ( $o_lastrec_warn && $dur->seconds() > $o_lastrec_warn ) {
        update_exit_code ( $NAGIOS_WARN );
	$arch_status = $NAGIOS_STATUS_WARN;
    } elsif ( $o_lastrec_crit && $dur->seconds() > $o_lastrec_crit ) {
        update_exit_code ( $NAGIOS_CRIT );
	$arch_status = $NAGIOS_STATUS_CRIT;
    }

#    my $vcore_info = sprintf("%s info: name=%s ver='%s' running_on=%s", $PEER_TYPE, $route{$noun_VCoreName}, $route{$noun_VCoreVersion}, $route{$noun_CSName});

    my $backup_status = $NAGIOS_STATUS_OK;

    $json_out{'result_status'} = $exit_status;
    $json_out{'result_code'} = $exit_code;
    $json_out{'peer_type'} = $PEER_TYPE;

    $json_sub_peer{'name'} = $route{$noun_VCoreName};
    $json_sub_peer{'version'} = $route{$noun_VCoreVersion};
    $json_sub_peer{'host'} = $route{$noun_CSName};
    $json_sub_peer{'addr'} = $o_host;
    $json_sub_peer{'licensed_cameras'} = $route{$noun_NumberOfCamerasLicensed} + 0 if (!$o_legacy_vserver);
    $json_out{'peer'} = \%json_sub_peer;
#    my $vcore_info = sprintf("%s info: name=%s ver='%s' running_on=%s", $PEER_TYPE, $route{$noun_VCoreName}, $route{$noun_VCoreVersion}, $route{$noun_CSName}); 

    $json_sub_uptime{'status'} = $uptime_status;
    $json_sub_uptime{'days'} = $uptime_days;
    $json_sub_uptime{'warning_thres'} = $o_uptime_warn;
    $json_sub_uptime{'critical_thres'} = $o_uptime_crit;
#    if ($uptime_status ne "") {
#    	printf("%s %s\n",$uptime_status, from_now($uptime_sec,1));
#    }
    $json_out{'uptime'} = \%json_sub_uptime;

    $json_sub_recording{'status'} = $rec_status;
    $json_sub_recording{'state'} = $route{$noun_RecordingState};
    $json_out{'recording'} = \%json_sub_recording;

    $json_sub_archive{'status'} = $arch_status;
    $json_sub_archive{'span_status'} = $archive_span_status;
#    $json_sub_archive{'seconds'} = duration($archive_span_sec,1);
    $json_sub_archive{'days'} = $archive_span;
    $json_sub_archive{'warning_thres'} = $o_archive_warn;
    $json_sub_archive{'critical_thres'} = $o_archive_crit;
    $json_sub_archive{'from_date'} = $route{$noun_ArchiveEarliestDate}; 
    $json_sub_archive{'till_date'} = $route{$noun_ArchiveMostRecentDate}; 
    if ($no_archive) {
	    $json_sub_archive{'warning'} = "archive has no records";
    }

    $json_out{'archive'} = \%json_sub_archive;
   
    if ($o_legacy_vserver > 1) {
    	if ($route{'BackupStateEnum'} == 2) {
       		update_exit_code ( $NAGIOS_WARN );
       		$backup_status = $NAGIOS_WARN;

		$json_out{'result_status'} = $exit_status;
    		$json_out{'result_code'} = $exit_code;
    	}

    	$json_sub_backup{'status'} = $backup_status;
    	$json_sub_backup{'state'} = $route{'BackupState'};
#    	my $backup_space_used_perfdata = "";
    	if ($route{'BackupStateEnum'} > 0) {
#      		$backup_space_used_perfdata = sprintf("backup_space_used=%d\%", $route{'BackupSpaceUsedPercent'});
	    	$json_sub_backup{'space_used_percent'} = $route{'BackupSpaceUsedPercent'};
	    	$json_sub_backup{'most_recent_date'} = $route{'BackupMostRecentDate'};
    	}
    	$json_out{'backup'} = \%json_sub_backup;
#    	printf("%s %s|%s %s %s\n", $route{$noun_VCoreName}, $exit_status, $archive_span_perfdata, $uptime_perfdata, $backup_space_used_perfdata);
    } else {
    	
    	$json_sub_lastrec{'seconds'} = $dur->seconds();
    	$json_sub_lastrec{'warning_thres'} = $o_lastrec_warn;
    	$json_sub_lastrec{'critical_thres'} = $o_lastrec_crit;
    	$json_out{'last_record'} = \%json_sub_lastrec;
	
#	my $last_rec_perfdata = sprintf("lastrec_secs=%.2f;%.2f;%.2f", $dur->seconds(), $o_lastrec_warn, $o_lastrec_crit);
#    	printf("%s %s|%s %s %s\n", $route{$noun_VCoreName}, $exit_status, $archive_span_perfdata, $uptime_perfdata, $last_rec_perfdata);
    }

    last;

 } elsif ( $o_scope eq $SCOPE_CAMERAS) {
    $json_out{'peer_type'} = $PEER_TYPE;
    $json_sub_peer{'name'} = $route{$noun_VCoreName};
    $json_sub_peer{'addr'} = $o_host;
    $json_out{'peer'} = \%json_sub_peer;

    if (defined($cam_cumul_status)) {
	if ( $o_camidx == $DEF_ALLCAMS ) {
		update_exit_code($NAGIOS_WARN) if $cam_cumul_status ne $NAGIOS_OK;
#		printf("%s cameras: %s|healthy_cameras=%d;%d;0; faulty_cameras=%d;1;%d;\n", $route{$noun_VCoreName}, $exit_status, $cam_healthy_count, $cam_total_count-1,  $cam_faulty_count, $cam_total_count);

		$json_out{'result_status'} = $exit_status;
    		$json_out{'result_code'} = $exit_code;

		my %json_cam_total;
		$json_cam_total{'value'} = $cam_total_count;
		$json_cam_total{'status'} = $cam_cumul_status;
		$json_sub_cameras{'total'} = \%json_cam_total;

		$json_sub_cameras_h{'value'} = $cam_healthy_count;
    		$json_sub_cameras_h{'warning_thres'} = $cam_total_count-1;
    		$json_sub_cameras_h{'critical_thres'} = 0;
    		$json_sub_cameras{'healthy'} = \%json_sub_cameras_h;	

		$json_sub_cameras_f{'value'} = $cam_faulty_count;
    		$json_sub_cameras_f{'warning_thres'} = 1;
    		$json_sub_cameras_f{'critical_thres'} = $cam_total_count;
    		$json_sub_cameras{'faulty'} = \%json_sub_cameras_f;	

    		$json_out{'cameras'} = \%json_sub_cameras;	

	} else {
		update_exit_code($NAGIOS_CRIT) if $cam_cumul_status ne $NAGIOS_OK;
#		printf("%s %s: %s\n", $route{$noun_VCoreName}, $route{$noun_Description}, $route{$noun_CameraState});
		$json_out{'result_status'} = $exit_status;
    		$json_out{'result_code'} = $exit_code;

		my %json_cam;
        	$json_cam{'name'} = $route{$noun_VCoreCameraName};
        	$json_cam{'state'} = $route{$noun_CameraState};
        	$json_cam{'status'} = $route{$noun_CameraStateEnum};
		$json_out{$route{$noun_Name}} = \%json_cam;

#    		$json_out{'name'} = $route{$noun_Description};
#    		$json_out{'state'} = $route{$noun_CameraState};
#    		$json_out{'status'} = $route{$noun_CameraStateEnum};
		
		last;
	}
	$cam_cumul_status = undef;
	
    }	
	
    my $cam_status = undef;
    my $cam_enum = $route{$noun_CameraStateEnum};
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
#	printf("%s (%s): %s\n", $route{$noun_Name}, $route{$noun_VCoreCameraName}, $cam_status);
	
	my %json_cam;
	$json_cam{'name'} = $route{$noun_VCoreCameraName};
	$json_cam{'state'} = $cam_status;
	$json_cam{'status'} = $route{$noun_CameraStateEnum};
	

#	$json_cameras{'name'} = \%(json_cam_arr_ref->[0]);
	$json_sub_cameras{$route{$noun_Name}} = \%json_cam;
    }	
	
 } else {
    my_err_exit $NAGIOS_ERR, "unexpected scope";
 }


}

#print Dumper(\%json_out);
 
make_json(\%json_out);
exit influx_exit_code();
