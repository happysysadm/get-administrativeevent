function Get-AdministrativeEvent {

<#
.Synopsis
The Get-AdministrativeEvent function retrieves the last critical administrative events on a local or remote computer
.EXAMPLE
Get-AdministrativeEvent -cred (get-credential domain\admin) -ComputerName srv01 -HoursBack 1
.EXAMPLE
$cred = get-credential
Get-AdministrativeEvent -cred $cred -ComputerName srv01 -HoursBack 24 | Sort-Object timecreated -Descending | Out-Gridview
.EXAMPLE
'srv01','srv02' | % { Get-AdministrativeEvent -HoursBack 1 -cred $cred -ComputerName $_ } | Sort-Object timecreated -Descending | ft * -AutoSize
.EXAMPLE
Get-AdministrativeEvent -HoursBack 36 -ComputerName (Get-ADComputer -filter *).name | sort timecreated -Descending | Out-GridView
.EXAMPLE
Get-AdministrativeEvent -cred $cred -ComputerName 'srv01','srv02' -HoursBack 12 | Out-Gridview
.EXAMPLE
$Report = Start-RSJob -Throttle 20 -Verbose -InputObject ((Get-ADComputer -server dc01 -filter {(name -notlike 'win7*') -AND (OperatingSystem -Like "*Server*")} -searchbase "OU=SRV,DC=Domain,DC=Com").name) -FunctionsToLoad Get-AdministrativeEvent -ScriptBlock {Get-AdministrativeEvent $_ -HoursBack 3 -Credential $using:cred -Verbose} | Wait-RSJob -Verbose -ShowProgress | Receive-RSJob -Verbose
$Report | sort timecreated -descending | Out-GridView
.EXAMPLE
$Servers = ((New-Object -typename ADSISearcher -ArgumentList @([ADSI]"LDAP://domain.com/dc=domain,dc=com","(&(&(sAMAccountType=805306369)(objectCategory=computer)(operatingSystem=*Server*)))")).FindAll()).properties.name
$Report = Start-RSJob -Throttle 20 -Verbose -InputObject $Servers -FunctionsToLoad Get-AdministrativeEvent -ScriptBlock {Get-AdministrativeEvent $_ -Credential $using:cred -HoursBack 48 -Verbose} | Wait-RSJob -Verbose -ShowProgress | Receive-RSJob -Verbose
$Report | format-table * -AutoSize
.NOTES
happysysadm.com
@sysadm2010
#>

    [CmdletBinding()]
    Param
    (
        # List of computers
        [Parameter(Mandatory=$true,
                   ValueFromPipeline=$true,
                   ValueFromPipelineByPropertyName=$true,
                   Position=0)]
        [Alias('Name','CN')] 
        [string[]]$ComputerName,

        # Specifies a user account that has permission to perform this action
        [Parameter(Mandatory=$false)]
        [System.Management.Automation.PSCredential]
        [System.Management.Automation.Credential()]
        $Credential = [System.Management.Automation.PSCredential]::Empty,

        #Number of hours to go back to when retrieving events
        [int]$HoursBack = 1

    )

    Begin

        {

        Write-Verbose "$(Get-Date) - Started."

        $AllResults = @()

        }
    
    Process
        {

        foreach($Computer in $ComputerName) {
    
            $Result = $Null

            write-verbose "$(Get-Date) - Working on $Computer - Eventlog"

            $starttime = (Get-Date).AddHours(-$HoursBack)
    
            try {

                write-verbose "$(Get-Date) - Trying with Get-WinEvent"
    
                $result = Get-WinEvent -ErrorAction stop -Credential $credential -ComputerName $Computer -filterh @{LogName=(Get-WinEvent -Computername $Computer -ListLog *| ? {($_.logtype -eq 'administrative') -and ($_.logisolation -eq 'system')} | ? recordcount).logname;StartTime=$starttime;Level=1,2} | select machinename,timecreated,providername,logname,id,leveldisplayname,message

                }

            catch [System.Diagnostics.Eventing.Reader.EventLogException] {
        
                switch -regex ($_.Exception.Message) {

                    "RPC" { 
            
                        Write-Warning "$(Get-Date) - RPC error while communicating with $Computer"
                
                        $Result = 'RPC error'
                
                        }
        
                    "Endpoint" { 
            
                        write-verbose "$(Get-Date) - Trying with Get-EventLog for systems older than Windows 2008"

                        try { 
                
                            $sysevents = Get-EventLog -ComputerName $Computer -LogName system -Newest 1000 -EntryType Error -ErrorAction Stop | `
                                            ? TimeGenerated -gt $starttime | `
                                            select MachineName,
                                            
                                                   @{Name='TimeCreated';Expression={$_.TimeGenerated}},
                                                   
                                                   @{Name='ProviderName';Expression={$_.Source}},
                                                   
                                                   LogName,
                                                   
                                                   @{Name='Id';Expression={$_.EventId}},
                                                   
                                                   @{Name='LevelDisplayName';Expression={$_.EntryType}},
                                                   
                                                   Message

                            if($sysevents) {

                                $result = $sysevents

                                }

                            else {

                                Write-Warning "$(Get-Date) - No events found on $Computer"
                        
                                $result = 'none'

                                }
                    
                            }

                        catch { $Result = 'error' }
                
                        }

                    Default { Write-Warning "$(Get-Date) - Error retrieving events from $Computer" }
                
                    }

                }
        
            catch [Exception] {
        
                Write-Warning "$(Get-Date) - No events found on $Computer"
        
                $result = 'none'

                }

        if(($result -ne 'error') -and ($result -ne 'RPC error') -and ($result -ne 'none')) {

            Write-Verbose "$(Get-Date) - Consolidating events for $Computer"
            
            $lastuniqueevents = $null

            $lastuniqueevents = @()
            
            $ids = ($result | select id -unique).id

            foreach($id in $ids){

                $machineevents = $result | ? id -eq $id

                $lastuniqueevents += $machineevents | sort timecreated -Descending | select -first 1

                }

            $AllResults += $lastuniqueevents

            }
    
        }

    }

    End {
        
        Write-Verbose "$(Get-Date) - Finished."
    
        $AllResults
        
        }

}