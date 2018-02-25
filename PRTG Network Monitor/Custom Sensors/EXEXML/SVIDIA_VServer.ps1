#-scope main -VServer '%host' -domain '%windowsdomain' -username '%windowsuser' -password '%windowspassword' -timeout 30
#$ConfirmPreference = 'None'

Param(
	[parameter(Mandatory=$true)] [String] $scope,
	[parameter(Mandatory=$true)] [String] $VServer,
	[parameter(Mandatory=$true)] [String] $username,
	[parameter(Mandatory=$true)] [String] $password,
	[String] $domain,
	[int] $timeout = 30
    )

function error_exit() {
	Param(
		[String] $p_errmsg,
		[int] $exit_code = 4
	)
	"<?xml version=`"1.0`" encoding=`"UTF-8`" ?>"
	"<prtg>"
	"<Error>1</Error>"
	"<text>" + $p_errmsg + "</text>"
	"</prtg>" 	
	Exit $exit_code
}	

function vserver_info() {
	Param(
		[String] $p_name,
		[String] $p_version
	)
	"<?xml version=`"1.0`" encoding=`"UTF-8`" ?>"
	"<prtg>"
	"<result>"
	"<ValueLookup>prtg.standardlookups.yesno.stateyesok</ValueLookup>"
	"<value>1</value>"
	"<NotifyChanged>1</NotifyChanged>"
	"</result>"
	"<text>VServer name: " + $p_name + " (" + $p_version + ") </text>"
	"</prtg>"
}

function archive_info() {
	Param(
		[String] $p_from,
		[String] $p_to
	)
	"<?xml version=`"1.0`" encoding=`"UTF-8`" ?>"
	"<prtg>"
	"<result>"
	"<ValueLookup>prtg.standardlookups.yesno.stateyesok</ValueLookup>"
	"<value>1</value>"
	"</result>"
	"<text>VServer Archive from " + $p_from + " to " + $p_to + "</text>"
	"</prtg>"
}

function backup_info() {
	Param(
		[int] 		$p_state,
		[String] 	$p_date,
		[int] 		$p_space
	)
	
	"<?xml version=`"1.0`" encoding=`"UTF-8`" ?>"
	"<prtg>"
	"<result>"
#	"<ValueLookup>prtg.standardlookups.yesno.stateyesok</ValueLookup>"
	"<value>" + $p_state + "</value>"
	"</result>"
	[string] $msg = "";
	[int] $res = 0;
	switch ($p_state) {
		0 {$msg = "Backup is disabled"}
		1 {$msg = "Backup is running. The last date in backup: " + $p_date }
		2 {
			$msg = "Backup is stopped. The last date in backup: " + $p_date 
			$res = 1
		}
		default {
			$res = 3
			$msg = "Unexpected backup status"
			"<Error>1</Error>"
		}
	}
	"<text>" + $msg + "</text>"
	"</prtg>"
	Exit $res
}


function backup_info_simple() {
	Param(
		[int] 		$p_state,
		[String] 	$p_date,
		[int] 		$p_space
	)
	
	[string] $msg = "";
	[string] $datemsg = "The last date in backup: " + $p_date;
	
	[int] $res = 0;
	switch ($p_state) {
		0 {$msg = "Backup is disabled"}
		1 {$msg = "Backup is running. " + $datemsg }
		2 {
			$msg = "Backup is stopped. " + $datemsg 
			$res = 1
		}
		default {
			$res = 3
			$msg = "Unexpected backup status"
			"<Error>1</Error>"
		}
	}
#	write-host $res + ":"+$msg
	"{0}:{1}" -f $res, $msg
	Exit $res
}
	
#$trusted_hosts = (get-item wsman:\localhost\Client\TrustedHosts).value
#$tha = $trusted_hosts -split ', '
#$add_th = 1
#foreach ($th in $tha) {
#	if ("$th" -EQ "$VServer") {
#		$add_th = 0
#		break
#	}
#}

#if ($add_th -EQ 1) {
#	set-item wsman:\localhost\Client\TrustedHosts -value "$trusted_hosts, $VServer" -Force
#	write-host "$VServer" is NOT trusted 
#} else {
#	write-host "$VServer" is already added to trusted 
#}

if ([string]::IsNullOrEmpty($domain)) {
	$domain=$VServer
}

if ( $username.Contains('\') ) {
	$fullusername=$username
} else {
	$fullusername="$domain\$username"
}

#write-host "fullusername=$fullusername VServer=$VServer domain=$domain"

Try {
	$SecurePass = ConvertTo-SecureString $password -AsPlainText -Force
} 
Catch {
	$ErrorMessage = $_.Exception.Message
	$SecurePass = $null
}
if ($SecurePass -eq $null) {
	error_exit "Creating secure password has been failed. $ErrorMessage" 2
}

Try {
	$cred = new-object -typename System.Management.Automation.PSCredential ("$fullusername",$SecurePass)
} 
Catch {
	$ErrorMessage = $_.Exception.Message
	$cred = $null
}
if ($cred -eq $null) {
	error_exit "Cannot create credentials. $ErrorMessage"  2
}

#$cred = Get-Credential -UserName "$fullusername"  -Message "winrm"
$cimop=New-CimSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck -Encoding Utf8 -UseSsl
Try {
	$session=New-CimSession -Authentication Negotiate -Credential $cred -ComputerName $VServer -SessionOption $cimop -OperationTimeoutSec $timeout -ErrorAction Stop
} 
Catch {
	$ErrorMessage = $_.Exception.Message
	$session = $null
}
if ($session -eq $null) {
	error_exit "Connection to $VServer has been failed. $ErrorMessage" 2
}
Try {
	$colItems = Get-CimInstance -CimSession $session -ClassName SVIDIA_VServer -Namespace root/cimv2 -WarningAction SilentlyContinue -ErrorAction Stop -WarningVariable VServer_warnings
} 
Catch {
	$ErrorMessage = $_.Exception.Message
	$colItems = $null
}
if ($colItems -eq $null) {
	error_exit "VServer is not responding. $ErrorMessage" 2
}

	[String] $warn_msg = ""
	[int] $res = 0

#	$CSName = $colItems.CSName
	$ReturnMessage = $colItems.ReturnMessage	
	[double] $uptime_in_days = [System.Math]::Round($colItems.VServerUpTimeInSeconds / 86400, 2)	
	[double] $archive_in_days = [System.Math]::Round($colItems.ArchiveSpanInSeconds / 86400, 2)	
	
	$RecordingStateEnum = $colItems.RecordingStateEnum
	$BackupStateEnum = $colItems.BackupStateEnum	
	
	if ( $scope -EQ "info" ) {
		vserver_info  $colItems.VServerName $colItems.VServerVersion 
		Exit 0
	}
	
	if ( $scope -EQ "archive" ) {
		archive_info $colItems.ArchiveEarliestDate $colItems.ArchiveMostRecentDate 
		Exit 0
	}
		
	if ( $scope -EQ "backup" ) {
		backup_info $colItems.BackupStateEnum $colItems.BackupMostRecentDate $colItems.BackupSpaceUsedPercent
		Exit 0
	}
	
	if ( $scope -EQ "backup_txt" ) {
		backup_info_simple $colItems.BackupStateEnum $colItems.BackupMostRecentDate $colItems.BackupSpaceUsedPercent
		Exit 0
	}
	
	if ( $scope -NE "main" ) {
		error_exit "Unexpected scope param"
	}

"<?xml version=`"1.0`" encoding=`"UTF-8`" ?>"
"<prtg>"
	"<result>"
		"<channel>UpTime</channel>"
		"<Warning>0</Warning>"		
		"<Float>1</Float>"
		"<DecimalMode>2</DecimalMode>"
		"<CustomUnit>days</CustomUnit>"		
		"<LimitMode>1</LimitMode>"
		"<LimitMinWarning>0.25</LimitMinWarning>"
		"<LimitWarningMsg>VServer has been restarted in the last six hours</LimitWarningMsg>"
		"<value>" + $uptime_in_days + "</value>"
	"</result>"

	"<result>"
		"<channel>Recording Status</channel>"
		"<ValueLookup>prtg.svidia.VServer.recordingstatus</ValueLookup>"
		"<value>" + $RecordingStateEnum + "</value>"
    "</result>"
	
	"<result>"
		"<channel>Days in Archive </channel>"
		"<Float>1</Float>"
		"<DecimalMode>2</DecimalMode>"
		"<CustomUnit>days</CustomUnit>"
		"<value>" + $archive_in_days + "</value>"
	"</result>"
	
	"<result>"
		"<channel>Backup Status</channel>"
		"<Warning>0</Warning>"
		"<ValueLookup>prtg.svidia.VServer.backupstatus</ValueLookup>"
		"<value>" + $BackupStateEnum + "</value>"
    "</result>"
	
	if ($BackupStateEnum -ne 0) {
		[int] $BackupSpaceUsedPercent = $colItems.BackupSpaceUsedPercent
		"<result>"
		"<channel>Backup Space Used</channel>"
		"<value>" + $BackupSpaceUsedPercent+ "</value>"
		"<LimitMode>1</LimitMode>"
		"<LimitMaxWarning>90.0</LimitMaxWarning>"
		"<LimitWarningMsg>Low space on backup destination</LimitWarningMsg>"
		"<Unit>Percent</Unit>"
		"</result>"
	}

"</prtg>" 

Exit 0

