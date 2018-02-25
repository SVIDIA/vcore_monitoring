#-scope main -VServer '%host' -domain '%windowsdomain' -username '%windowsuser' -password '%windowspassword' -timeout 40

Param(
	[parameter(Mandatory=$true)] [String] $scope,
	[parameter(Mandatory=$true)] [String] $VServer,
	[parameter(Mandatory=$true)] [String] $username,
	[parameter(Mandatory=$true)] [String] $password,
	[String] $domain = ".",
	[int] $timeout = 30,
	[int] $cimport = 5986
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
		[int] $p_state,
		[String] $p_name,
		[String] $p_version,
		[String] $p_computer
	)
	"<?xml version=`"1.0`" encoding=`"UTF-8`" ?>"
	"<prtg>"
	"<result>"
	"<value>{0}</value>" -f $p_state
	"<NotifyChanged>1</NotifyChanged>"
	"</result>"
	"<text>VServer name: {0} ver: {1}, running on {2}</text>" -f $p_name, $p_version, $p_computer
	"</prtg>"
}

function archive_info() {
	Param(
		[int] $p_state,
		[String] $p_from,
		[String] $p_to
	)
		if ($p_to.Contains("1899")) {
			error_exit "An archive has no records" 2
		}
	"<?xml version=`"1.0`" encoding=`"UTF-8`" ?>"
	"<prtg>"
	"<result>"
	"<value>{0}</value>" -f $p_state
#	"<NotifyChanged>1</NotifyChanged>"
	"</result>"
	"<text>The archive holds records from {0} to {1}</text>" -f $p_from, $p_to
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
	"<value>{0}</value>" -f $p_state
#	"<NotifyChanged>1</NotifyChanged>"
	"</result>"
	[string] $last_rec = "The latest record date is: {0}" -f $p_date
	[string] $msg = "";
	[int] $res = 0;
	switch ($p_state) {
		0 {$msg = "A Backup is disabled."}
		1 {$msg = "A Backup is currently running. {0}" -f $last_rec }
		2 {
			$msg = "A Backup is currently stopped. {0}" -f $last_rec 
			$res = 1
		}
		default {
			$res = 3
			$msg = "Unexpected a backup status"
			"<Error>1</Error>"
		}
	}
	"<text>{0}</text>" -f $msg
	"</prtg>"
	Exit $res
}
function cameras_info() {
	param ($cameras)
	
	"<?xml version=`"1.0`" encoding=`"UTF-8`" ?>"
	"<prtg>"
	
	$healthy_cams = 0;
	$error_cams = 0;
	foreach ( $cam in  $cameras ) {
		if ( $cam.CameraStateEnum -EQ 1 ) {
			$error_cams ++;	
		}
		if ( $cam.CameraStateEnum -NE 0 ) { 
			$healthy_cams ++;
		}
	}
	"<result>"
	"<channel>Healthy cameras</channel>"
	if ( $healthy_cams -EQ 0) {
		"<Error>1</Error>"
	} else {
		"<Warning>0</Warning>"
	}
	"<value>{0}</value>" -f $healthy_cams
	"</result>"
	
	"<result>"
	"<channel>Faulty cameras</channel>"
	if ( $error_cams -EQ 0) {
		"<Warning>0</Warning>"
	} else {
		"<Error>1</Error>"
	}
	"<value>{0}</value>" -f $error_cams
	"</result>"
	
	foreach ( $cam in  $cameras ) {
		if ( $cam.CameraStateEnum -NE 0 ) { 
			"<result>"
				"<channel>{0}: {1}</channel>" -f $cam.Name, $cam.VServerCameraName
				"<Warning>0</Warning>"
				"<ValueLookup>prtg.svidia.VServer.camerastatus</ValueLookup>"
				"<value>{0}</value>" -f $cam.CameraStateEnum
			"</result>"
		}
	}
	
	if ( $healthy_cams -EQ 0) {
		"<Error>1</Error>"
		"<text>" + "No cameras are enabled" + "</text>"
	} 
	else { 
		if ( $error_cams -NE 0) {
			"<Error>1</Error>"
			"<text>" + "Faulty camera(s) found" + "</text>"
		} else {
			"<Warning>0</Warning>"
			"<text>" + "OK" + "</text>"
		}
	}
	"</prtg>"
}	

	if ([string]::IsNullOrEmpty($domain)) {
		$domain=$VServer
	}

	if ( $username.Contains('\') ) {
		$fullusername=$username
	} else {
		if ( $domain -EQ $VServer -Or $domain -EQ ".") {
			$fullusername="$username"
		} else {
			$fullusername="$domain\$username"
		}
	}

	if ( $scope -EQ "cameras") {
		$cim_class = "SVIDIA_VServerCamera"
	}
	else {
		$cim_class = "SVIDIA_VServer"
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

	Try {
		$cimop=New-CimSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck -Encoding Utf8 -UseSsl
	}
	Catch {
		$ErrorMessage = $_.Exception.Message
		$cimop = $null
	}
	if ($cimop -eq $null) {
		error_exit "Cannot create Session Options. $ErrorMessage"  2
	}
	
	Try {
		$session=New-CimSession -Authentication Basic -Credential $cred -ComputerName "$VServer" -SessionOption $cimop -Port $cimport -OperationTimeoutSec $timeout -ErrorAction Stop		
	} 
	Catch {
		$ErrorMessage = $_.Exception.Message
		$session = $null
	}
	if ($session -eq $null) {
		error_exit "Connection to $VServer has been failed. $ErrorMessage" 2
	}

	Try {
		$colItems = Get-CimInstance -CimSession $session -ClassName $cim_class -Namespace root/cimv2 -WarningAction SilentlyContinue -ErrorAction Stop -WarningVariable VServer_warnings
	} 
	Catch {
		$ErrorMessage = $_.Exception.Message
		$colItems = $null
	}
	if ($colItems -eq $null) {
		error_exit "VServer is not responding. $ErrorMessage" 2
	}
	
	if ( $scope -EQ "cameras" ) {
		if ($colItems[0].ReturnResult -EQ 10061) {
			$ReturnMessage = $colItems[0].ReturnMessage
			error_exit "$ReturnMessage. $ErrorMessage" 2
		}
		cameras_info $colItems
		Exit 0
	}
	
	$cs_name = $colItems.CSName
	if ((-not $colItems.VServerName) -Or  (-not $colItems.VServerVersion) ) {
		error_exit "VServer process is down, while the host $cs_name is alive." 2
	}

#	$ReturnMessage = $colItems.ReturnMessage	
	[double] $uptime_in_days = [System.Math]::Round($colItems.VServerUpTimeInSeconds / 86400, 2)	
	[double] $archive_in_days = [System.Math]::Round($colItems.ArchiveSpanInSeconds / 86400, 2)	
	
	
	if ( $scope -EQ "info" ) {
		vserver_info $colItems.RecordingStateEnum $colItems.VServerName $colItems.VServerVersion $colItems.CSName 
		Exit 0
	}
	
	if ( $scope -EQ "archive" ) {
		archive_info $colItems.RecordingStateEnum $colItems.ArchiveEarliestDate $colItems.ArchiveMostRecentDate 
		Exit 0
	}
		
	if ( $scope -EQ "backup" ) {
		backup_info $colItems.BackupStateEnum $colItems.BackupMostRecentDate $colItems.BackupSpaceUsedPercent
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
		"<value>{0}</value>" -f $uptime_in_days
	"</result>"

	"<result>"
		"<channel>Recording Status</channel>"
		"<ValueLookup>prtg.svidia.VServer.recordingstatus</ValueLookup>"
		"<value>{0}</value>" -f $colItems.RecordingStateEnum
    "</result>"
	
	"<result>"
		"<channel>Days in Archive </channel>"
		"<Float>1</Float>"
		"<DecimalMode>2</DecimalMode>"
		"<CustomUnit>days</CustomUnit>"
		"<value>{0}</value>" -f $archive_in_days
	"</result>"
	
	"<result>"
		"<channel>Backup Status</channel>"
		"<Warning>0</Warning>"
		"<ValueLookup>prtg.svidia.VServer.backupstatus</ValueLookup>"
		"<value>{0}</value>" -f $colItems.BackupStateEnum
    "</result>"
	
	if ( $colItems.BackupStateEnum -ne 0 ) {
		"<result>"
		"<channel>Backup Space Used</channel>"
		"<value>{0}</value>" -f $colItems.BackupSpaceUsedPercent
		"<LimitMode>1</LimitMode>"
		"<LimitMaxWarning>90.0</LimitMaxWarning>"
		"<LimitWarningMsg>Low space on backup destination</LimitWarningMsg>"
		"<Unit>Percent</Unit>"
		"</result>"
	}

"</prtg>" 

Exit 0
