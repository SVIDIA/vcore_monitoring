How to monitor SVIDIA VServer using PRTG:

- run cmd as administartor
-- execute the command to allow powershell scripts to be executed on system:
--- powershell Set-ExecutionPolicy RemoteSigned

- Right click -> Add Device
-- enter Device Name and IPv4-Address/DNS Name
-- select a "Device Icon"
-- under DEVICE TYPE -> Sensor Management 
--- select item "Automatic sensor creation using specific device template(s)" 
--- SVIDIA_VServer template

-- enter "CREDENTIALS FOR WINDOWS SYSTEMS" 
--- "Domain or Computer Name"
--- "Username"
--- "Password"
-- click "Continue"



