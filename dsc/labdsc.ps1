configuration Lab {

    param
    (
        [Parameter(Mandatory)]
        [pscredential]$safemodeAdministratorCred,
        [Parameter(Mandatory)]
        [pscredential]$domainCred,
        [Parameter(Mandatory)]
        [string]$firstDomainName,
        [Parameter(Mandatory)]
        [string]$secondDomainName,
        [Parameter(Mandatory)]
        [pscredential]$firstDomainCred
    )

    Import-DscResource -ModuleName ActiveDirectoryDsc
    Import-DscResource -ModuleName NetworkingDsc

    Node "First" {

        WindowsFeature ADDSInstall {
            Ensure = "Present"
            Name = "AD-Domain-Services"
        }

        WindowsFeature ADDSTools {
            Ensure = "Present"
            Name = "RSAT-ADDS"
        }

        FirewallProfile DisablePublic {
            Enabled = "False"
            Name   = "Public"
        }
        
        FirewallProfile DisablePrivate {
            Enabled = "False"
            Name   = "Private"
        }
        
        FirewallProfile DisableDomain {
            Enabled = "False"
            Name   = "Domain"
        }

        User AdminUser {
            Ensure = "Present"
            UserName = $domainCred.UserName
            Password = $domainCred
        }

        Group Administrators {
            GroupName = "Administrators"
            MembersToInclude = $domainCred.UserName
            DependsOn = "[User]AdminUser"
        }

        ADDomain CreateDC {
            DomainName = $firstDomainName
            Credential = $domainCred
            SafemodeAdministratorPassword = $safemodeAdministratorCred
            DatabasePath = 'C:\NTDS'
            LogPath = 'C:\NTDS'
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        WaitForADDomain waitFirstDomain {
            DomainName = $firstDomainName
            DependsOn = "[ADDomain]CreateDC"
        }

        DnsServerAddress DnsServerAddress
        {
            Address        = '127.0.0.1', '10.0.2.100'
            InterfaceAlias = 'Ethernet'
            AddressFamily  = 'IPv4'
            Validate       = $false
            DependsOn = "[WaitForADDomain]waitFirstDomain"
        }

        Script SetConditionalForwardedZone {
            GetScript = { return @{ } }

            TestScript = {
                $zone = Get-DnsServerZone -Name $using:secondDomainName -ErrorAction SilentlyContinue
                if ($zone -ne $null -and $zone.ZoneType -eq 'Forwarder') {
                    return $true
                }

                return $false
            }

            SetScript = {
                $ForwardDomainName = $using:secondDomainName
                $IpAddresses = @("10.0.2.100")
                Add-DnsServerConditionalForwarderZone -Name "$ForwardDomainName" -ReplicationScope "Domain" -MasterServers $IpAddresses
            }

            DependsOn = "[WaitForADDomain]waitFirstDomain"
        }

        ADUser 'regular.user'
        {
            Ensure     = 'Present'
            UserName   = 'regular.user'
            Password   = (New-Object System.Management.Automation.PSCredential("regular.user", (ConvertTo-SecureString "DoesntMatter" -AsPlainText -Force)))
            DomainName = 'first.local'
            Path       = 'CN=Users,DC=first,DC=local'
            DependsOn = "[WaitForADDomain]waitFirstDomain"
        }

        ADUser 'roast.user'
        {
            Ensure     = 'Present'
            UserName   = 'roast.user'
            Password   = (New-Object System.Management.Automation.PSCredential("roast.user", (ConvertTo-SecureString "DoesntMatter" -AsPlainText -Force)))
            DomainName = 'first.local'
            Path       = 'CN=Users,DC=first,DC=local'
            ServicePrincipalNames = "MSSQL/sql.first.local"
            DependsOn = "[WaitForADDomain]waitFirstDomain"
        }

        ADUser 'asrep.user'
        {
            Ensure     = 'Present'
            UserName   = 'asrep.user'
            Password   = (New-Object System.Management.Automation.PSCredential("asrep.user", (ConvertTo-SecureString "DoesntMatter" -AsPlainText -Force)))
            DomainName = 'first.local'
            Path       = 'CN=Users,DC=first,DC=local'
            DependsOn = "[WaitForADDomain]waitFirstDomain"
        }

        Script "asrep.user PreAuth Disable"
        {
            SetScript = {
                Set-ADAccountControl -Identity "asrep.user" -DoesNotRequirePreAuth $true
            }
            TestScript = { 
                $false 
            }
            GetScript = { 
                @{ Result = (Get-ADUser "asrep.user" ) } 
            }
            DependsOn = "[WaitForADDomain]waitFirstDomain", "[ADUser]asrep.user"
        }
    }

    Node "Second" {

        WindowsFeature ADDSInstall {
            Ensure = "Present"
            Name = "AD-Domain-Services"
        }

        WindowsFeature ADDSTools {
            Ensure = "Present"
            Name = "RSAT-ADDS"
        }

        FirewallProfile DisablePublic {
            Enabled = "False"
            Name   = "Public"
        }
        
        FirewallProfile DisablePrivate {
            Enabled = "False"
            Name   = "Private"
        }
        
        FirewallProfile DisableDomain {
            Enabled = "False"
            Name   = "Domain"
        }

        User AdminUser {
            Ensure = "Present"
            UserName = $domainCred.UserName
            Password = $domainCred
        }

        Group Administrators {
            GroupName = "Administrators"
            MembersToInclude = $domainCred.UserName
            DependsOn = "[User]AdminUser"
        }
        
        ADDomain CreateDC {
            DomainName = $secondDomainName
            Credential = $domainCred
            SafemodeAdministratorPassword = $safemodeAdministratorCred
            DatabasePath = 'C:\NTDS'
            LogPath = 'C:\NTDS'
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        WaitForADDomain waitSecondDomain {
            DomainName = $secondDomainName
            DependsOn = "[ADDomain]CreateDC"
        }

        DnsServerAddress DnsServerAddress
        {
            Address        = '127.0.0.1', '10.0.1.100'
            InterfaceAlias = 'Ethernet'
            AddressFamily  = 'IPv4'
            Validate       = $false
            DependsOn = "[WaitForADDomain]waitSecondDomain"
        }

        Script SetConditionalForwardedZone {
            GetScript = { return @{ } }

            TestScript = {
                $zone = Get-DnsServerZone -Name $using:firstDomainName -ErrorAction SilentlyContinue
                if ($zone -ne $null -and $zone.ZoneType -eq 'Forwarder') {
                    return $true
                }

                return $false
            }

            SetScript = {
                $ForwardDomainName = $using:firstDomainName
                $IpAddresses = @("10.0.1.100")
                Add-DnsServerConditionalForwarderZone -Name "$ForwardDomainName" -ReplicationScope "Domain" -MasterServers $IpAddresses
            }
        }

        ADUser 'regular.user'
        {
            Ensure     = 'Present'
            UserName   = 'regular.user'
            Password   = (New-Object System.Management.Automation.PSCredential("regular.user", (ConvertTo-SecureString "DoesntMatter" -AsPlainText -Force)))
            DomainName = 'second.local'
            Path       = 'CN=Users,DC=second,DC=local'
            DependsOn = "[WaitForADDomain]waitSecondDomain"
        }

        ADUser 'roast.user'
        {
            Ensure     = 'Present'
            UserName   = 'roast.user'
            Password   = (New-Object System.Management.Automation.PSCredential("roast.user", (ConvertTo-SecureString "DoesntMatter" -AsPlainText -Force)))
            DomainName = 'second.local'
            Path       = 'CN=Users,DC=second,DC=local'
            ServicePrincipalNames = "MSSQL/sql.second.local"
            DependsOn = "[WaitForADDomain]waitSecondDomain"
        }

        ADUser 'asrep.user'
        {
            Ensure     = 'Present'
            UserName   = 'asrep.user'
            Password   = (New-Object System.Management.Automation.PSCredential("asrep.user", (ConvertTo-SecureString "DoesntMatter" -AsPlainText -Force)))
            DomainName = 'second.local'
            Path       = 'CN=Users,DC=second,DC=local'
            DependsOn = "[WaitForADDomain]waitSecondDomain"
        }

        WaitForADDomain waitFirstDomain {
            DomainName = $firstDomainName
            Credential = $firstDomainCred
            WaitTimeout = 600
            RestartCount = 2
            DependsOn = "[Script]SetConditionalForwardedZone"
        }

        ADDomainTrust DomainTrust {
            TargetDomainName = $firstDomainName
            TargetCredential = $firstDomainCred
            TrustType = "External"
            TrustDirection = "Bidirectional"
            SourceDomainName = $secondDomainName
            DependsOn = "[WaitForADDomain]waitFirstDomain"
            Ensure = "Present"
        }
    }
}

$ConfigData = @{
    AllNodes = @(
        @{
            Nodename                    = "First"
            Role                        = "First DC"
            RetryCount                  = 1
            RetryIntervalSec            = 1
            PsDscAllowPlainTextPassword = $true
        },
        @{
            Nodename                    = "Second"
            Role                        = "Second DC"
            RetryCount                  = 1
            RetryIntervalSec            = 1
            PsDscAllowPlainTextPassword = $true
        }
    )
}

Lab -ConfigurationData $ConfigData `
    -firstDomainName "first.local" `
    -secondDomainName "second.local" `
    -domainCred (New-Object System.Management.Automation.PSCredential("admin", (ConvertTo-SecureString "DoesntMatter" -AsPlainText -Force))) `
    -safemodeAdministratorCred (New-Object System.Management.Automation.PSCredential("admin", (ConvertTo-SecureString "DoesntMatter" -AsPlainText -Force))) `
    -firstDomainCred (New-Object System.Management.Automation.PSCredential("first-admin", (ConvertTo-SecureString "DoesntMatter" -AsPlainText -Force)))
