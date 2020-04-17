#!/usr/bin/python

import winrm
import boto3
import time

internal_domain_user = "admin"
internal_domain_pass = "Password@1"

class WinRMSession:
    def __init__(self, host, username, password, use_ntlm=False):
        self.host = host
        self.username = username
        self.password = password
        self.use_ntlm = use_ntlm

    def run_command(self, command, args=[]):
        if self.use_ntlm:
            s = winrm.Session(self.host, auth=(self.username, self.password), transport="ntlm")
        else:
            s = winrm.Session(self.host, auth=(self.username, self.password))

        try:
            r = s.run_cmd(command, args)

            print("=====[ STDERR ]=====")
            print(r.std_err.decode("ascii"))

            print("=====[ STDOUT ]=====")
            return r.std_out.decode("ascii")

        except InvalidCredentialsError as e:
            print("Error")

def clean_windows_image(username, password, ip, domain_joined):
    
    print("====[ Cleaning {0} ]====".format(ip))

    dsc = "Write-Output '[DscLocalConfigurationManager()]' 'Configuration Meta { Node localhost { Settings { RefreshMode = \'\'Disabled\'\' } } }' > C:\\windows\\temp\\meta.ps1"
    
    s = WinRMSession(ip, username, password, use_ntlm=domain_joined)
    print(s.run_command('powershell', ['-c', 'Remove-DscConfigurationDocument -Stage Current -Force']))
    print(s.run_command('powershell', ['-c', 'Remove-DscConfigurationDocument -Stage Previous -Force']))
    print(s.run_command('powershell', ['-c', dsc]))
    print(s.run_command('powershell', ['-ep', 'bypass', '-c', 'cd C:\\windows\\temp; . .\\meta.ps1; Meta; Set-DscLocalConfigurationManager -Path .\Meta']))

# First we need to clean up Windows resources
ec2 = boto3.resource('ec2')
response = ec2.instances.filter(Filters=[{'Name': 'tag:Workspace', 'Values': ['imager']},{'Name': 'instance-state-name', 'Values': ['running']}])

for instance in response:
    if instance.platform == "windows":
        clean_windows_image(internal_domain_user, internal_domain_pass, instance.public_ip_address, True)
           
# Now everything is cleaned up, we image
for instance in response:
    for kv in instance.tags:
        if kv["Key"] == "Name": 
            print("====[ Creating AMI For {0}]====".format(kv["Value"]))
            name = kv["Value"] + "-{0}".format(time.time())
            instance.create_image(Name=name,Description="Lab Imager")
