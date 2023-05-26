Param(
    [bool]$Debug = $false,
    [bool]$NoUpdate = $false,
    [bool]$Console = $false
    )
<#==============================================================================
          File Name : Datastore-Tracker.ps1
    Original Author : Kenneth C. Mazie (kcmjr AT kcmjr.com)
                    :
        Description : Tracks SAN datastores over time. Emails a daily report on changes.
                    :
              Notes : Normal operation is with no command line options.
                    : Optional arguments: -Debug $true (defaults to false. Sends emails to debug user)
                    : -NoUpdate $true (runs with current files and doesnt replace them for debugging)
                    : -Console $true (displays runtime info on console)
                    :
           Warnings : None
                    :
              Legal : Public Domain. Modify and redistribute freely. No rights reserved.
                    : SCRIPT PROVIDED "AS IS" WITHOUT WARRANTIES OR GUARANTEES OF
                    : ANY KIND. USE AT YOUR OWN RISK. NO TECHNICAL SUPPORT PROVIDED.
                    :
            Credits : Code snippets and/or ideas came from many sources including but
                    : not limited to the following:
                    : Based on "Track Datastore Space script" Created by Hugo Peeters of www.peetersonline.nl
                    :
     Last Update by : Kenneth C. Mazie
    Version History : v1.00 - 09-16-14 - Original
     Change History : v1.10 - 08-28-15 - Edited to allow color coding of HTML output
                    : v1.20 - 09-16-15 - Added capacity numbers to HTML output
                    : v1.30 - 09-22-15 - Changed output from GB to TB
                    : v2.00 - 11-30-15 - Moved all config data out to xml file and encrypted password
                    : v2.10 - 07-07-17 - Fixed bug causing script to crash. Altered password from XML to use a key.
                    : v3.00 - 09-14-17 - Adjusted script to work with new PowerCLI v6 modules.
                    : v4.00 - 02-22-18 - Major rewrite to fix bugs in calulations and reporting.
                    : v4.10 - 03-02-18 - Minor notation fix for PS Gallery upload
                    :
#===============================================================================#>
<#PSScriptInfo
.VERSION 4.10
.AUTHOR Kenneth C. Mazie (kcmjr AT kcmjr.com)
.DESCRIPTION
 Tracks VMware SAN datastores over time. Emails a daily report on changes.
#> 
#requires -version 3.0

Clear-host
$ErrorActionPreference = "silentlycontinue"
$Computer = $Env:ComputerName
$Script:ScriptName = ($MyInvocation.MyCommand.Name).split(".")[0] 
$Script:LogFile = $PSScriptRoot+"\"+$ScriptName+"_{0:MM-dd-yyyy_HHmmss}.log" -f (Get-Date)
$Script:ConfigFile = "$PSScriptRoot\$ScriptName.xml"  
$body = "" 
$Script:CapGB = $False                                                                  #--[ Set to true if output in gigabytes is preferred ]--
$digits = 2
$Script:CurrentArray = @()                                                              #--[ Create an array to hold the output ]--

If ($Debug){
    $Script:Debug = $true
    $Script:NoUpdate = $true
    }

get-module -ListAvailable vm* | import-module | Out-Null                                #--[ Load VMware modules ]--
$Script:CurrentFile = $PSScriptRoot+'\Datastores_Current.xml'
$Script:PreviousFile = $PSScriptRoot+'\Datastores_Previous.xml'
$Script:DifferenceFile = $PSScriptRoot+'\Datastores_Difference.txt'

#--[ Functions ]--------------------------------------------------------
Function SendEmail {  #--[ Email settings ]--
    $Script:Email = new-object System.Net.Mail.MailMessage
    $Script:Email.From = $Script:Configuration.Settings.Email.From
    If ($Script:Debug -or $Script:NoUpdate){
        $Script:Email.To.Add($Script:DebugEmail)
    }Else{
        $Script:Email.To.Add($Script:EmailTo)
    }
    $Script:Email.Subject = $Script:Configuration.Settings.Email.Subject
    $Script:Email.IsBodyHtml = $Script:Configuration.Settings.Email.HTML
    $Script:Email.Body = $Script:ReportBody
    $smtp = new-object System.Net.Mail.SmtpClient($Script:SmtpServer)
    $smtp.Send($Script:Email)
    If ($Script::Console){Write-Host "-- Email Sent" -ForegroundColor red}
}

Function LoadConfig {
    #--[ Read and load configuration file ]-------------------------------------
    If (!(Test-Path $Script:ConfigFile)){       #--[ Error out if configuration file doesn't exist ]--
        Write-Host "---------------------------------------------" -ForegroundColor Red
        Write-Host "--[ MISSING CONFIG FILE. Script aborted. ]--" -ForegroundColor Red
        Write-Host "---------------------------------------------" -ForegroundColor Red
        break
    }Else{
        [xml]$Script:Configuration = Get-Content "$PSScriptRoot\$ScriptName.xml"      #--[ Load configuration ]--
        $Script:vCenters = ($Script:Configuration.Settings.General.vCenters).split(",")
        $Script:DebugEmail = $Script:Configuration.Settings.Email.Debug 
        $Script:EmailTo = $Script:Configuration.Settings.Email.To
        $Script:UserName = $Script:Configuration.Settings.Credentials.Username
        $Script:EncryptedPW = $Script:Configuration.Settings.Credentials.Password
        $Script:Base64String = $Script:Configuration.Settings.Credentials.Key
        $Script:SmtpServer = $Script:Configuration.Settings.Email.SmtpServer
        $Script:UserName = $Script:Configuration.Settings.Credentials.Username
        $Script:EncryptedPW = $Script:Configuration.Settings.Credentials.Password
        $Script:Base64String = $Script:Configuration.Settings.Credentials.Key   
        $ByteArray = [System.Convert]::FromBase64String($Script:Base64String);
        $Script:Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $Script:UserName, ($Script:EncryptedPW | ConvertTo-SecureString -Key $ByteArray)
        $Script:Password = $Credential.GetNetworkCredential().Password
    }       
}

Function CurrentStats {
    #==[ Get Current Statistics ]===================================================
    If ($Script:Console){Write-Host "`r`n--- Collecting Current Statistics --- " -ForegroundColor Yellow}
    If (Test-Path $Script:CurrentFile){Remove-Item -Path $Script:CurrentFile -Force}            #--[ Always clear out the current file. ]--
    If (Test-Path $Script:DifferenceFile){Remove-Item -Path $Script:DifferenceFile -Force}      #--[ If a Difference file exists remove it as well ]--
    ForEach ($VIServer in $Script:vCenters){
        If ($Script:Debug -or $Script:Console){Write-Host "`r`n--- Gathering Data From: $VIServer --- " -ForegroundColor Cyan}
        $VC = Connect-VIServer -Server $VIServer -Credential $Script:Credential                 #--[ Connect to Virtual Center ]--
        $DataStores = Get-Datastore | Sort-Object Name | Select-Object -Unique                  #--[ Get all datastores and put them in alphabetical order & remove accidental duplicates ]--
        ForEach ($Store in $DataStores){                                                        #--[ Loop through datastores ]--
            If ($Script:Console){
                Write-Host "-- Processing Datastore: " -ForegroundColor Yellow -NoNewline
                Write-Host ([string]$Store).PadRight(22) -ForegroundColor Magenta -NoNewline
            }
            if ($Store -notlike "*Local*"){
                $myObjCurrent = "" | Select-Object vCenter, Name, CapacityGB, UsedGB, FreeGB, PercFree, PercUsed    
                $myObjCurrent.CapacityGB = [math]::Round($store.CapacityGB,$digits)
                $myObjCurrent.UsedGB = [math]::Round(($store.CapacityGB - $store.FreeSpaceGB),$digits)
                $myObjCurrent.FreeGB = [math]::Round($store.FreeSpaceGB,$digits)
                $myObjCurrent.vCenter = $VIServer
                $myObjCurrent.Name = $store.Name
                $myObjCurrent.PercFree = [math]::Round(100 * $store.FreeSpaceGB / $store.CapacityGB,$digits)
                #$myObjCurrent.PercFree
                $myObjCurrent.PercUsed = 100-$myObjCurrent.PercFree
                #$myObjCurrent.PercUsed
                $Script:CurrentArray += $myObjCurrent                                                #--[ Add the object to the output array ]--
                If ($Script:Console){Write-Host $myObjCurrent }
            }Else{
                If ($Script:Console){Write-Host "-- Bypassed --"}
            }    
        }
        Disconnect-VIServer -Confirm:$False                                                          #--[ Disconnect from Virtual Center ]--
    }

    $Script:CurrentArray | Export-Clixml -Path $Script:CurrentFile                                   #--[ Export the output to an xml file; the new Current file ]--
    $Script:CurrentDate = (Get-Item $Script:CurrentFile).LastWriteTime | Get-Date -Format d          #--[ Get file dates for new file names ]--
    $Script:PreviousDate = (Get-Item $Script:PreviousFile).LastWriteTime  | Get-Date -Format d 

    If ($Script:Console){
        Write-Host "`nCurrent Date: $Script:CurrentDate"
        Write-host "Current File: $Script:CurrentFile`n"
        Write-host "Previous Date: $Script:PreviousDate"
        Write-host "Previous File: $Script:PreviousFile`n"
    }
}

Function CompareStats {     
    #--[Compare the Current information to that in the Previous file ]--------------
    If ($Script:Console){Write-Host "`r`n--- Processing Changes ---" -ForegroundColor Cyan}
    $Script:PreviousArray = Import-Clixml $Script:PreviousFile                                #--[ Import the Previous file ]--
    $Script:CurrentArray= Import-Clixml $Script:CurrentFile                                   #--[ Import the Current file ]--
    $Script:OutputArray = @()                                                                 #--[ Create an array to hold the differences ]--

    If (Test-Path $Script:PreviousFile){ 
        ForEach ($CurrentDS in $Script:CurrentArray){                                         #--[ Loop through the current datastores ]--
            $Script:VCCurrent = $CurrentDS.vCenter
            $RowData = ""
            $diff = ""
            $Script:DataStoreArray = "" | Select-Object vCenter, VolName, Capacity, CurrentUsed, CurrentFree, PreviousUsed, PreviousFree, PercentFree, PercentUsed, Diff 

            #--[ Process the comparison ]-------------------------------------------

            #--[ Calculate the difference compensating for identical datastore names across multiple vcenters ]--
            $diff = Compare-Object ($Script:PreviousArray | Where { ($_.Name -eq $CurrentDS.Name) -and ($_.vCenter -eq $Script:VCCurrent)}) $CurrentDS -Property UsedGB -ErrorAction SilentlyContinue

            #--[ The most important property is the calculated difference between the current and previous values of PercFree. You can substitute it for CurrentUsedGB if you like. ]--
            #$Script:DataStoreArray.Diff = ($diff | Where { $_.SideIndicator -eq '=>' }).PercFree - ($diff | Where { $_.SideIndicator -eq '<=' }).PercFree
            $Script:DataStoreArray.Diff = ($diff | Where { $_.SideIndicator -eq '<=' }).UsedGB - ($diff | Where { $_.SideIndicator -eq '=>' }).UsedGB
            #$Script:DataStoreArray.Diff = ($diff | Where { $_.SideIndicator -eq '<=' }).FreeGB - ($diff | Where { $_.SideIndicator -eq '=>' }).FreeGB
            # typical diff = @{FreeGB=2052.90; SideIndicator==>} @{FreeGB=2053.07; SideIndicator=<=}
            # current => previous <=
               
            If (($Script:DataStoreArray.Diff -eq "") -or ($Script:DataStoreArray.Diff -eq $null)){$Script:DataStoreArray.Diff = "0.00"}           #--[ Compensate for no results ]--

            #==[ Final results for output ]=========================================
            $Script:DataStoreArray.vCenter = $CurrentDS.vCenter 
            $Script:DataStoreArray.VolName = $CurrentDS.Name    
            $Script:DataStoreArray.Capacity = $CurrentDS.CapacityGB
            $Script:DataStoreArray.PreviousUsed = ($Script:PreviousArray | Where { $_.vCenter -eq $CurrentDS.vCenter -and $_.Name -eq $CurrentDS.Name }).UsedGB 
            $Script:DataStoreArray.PercentFree = $CurrentDS.PercFree 
            $Script:DataStoreArray.PercentUsed = $CurrentDS.PercUsed 
            $Script:DataStoreArray.CurrentUsed = $CurrentDS.UsedGB    
            $Script:DataStoreArray.CurrentFree = $CurrentDS.FreeGB    
            $Script:DataStoreArray.PreviousFree = ($Script:PreviousArray | Where { $_.vCenter -eq $CurrentDS.vCenter -and $_.Name -eq $CurrentDS.Name }).FreeGB
            #==[ Final results for output ]=========================================
        
            $Script:OutputArray += $Script:DataStoreArray                                                 #--[ Add result to the output array ]--
        
            If($Script:Console){  
                Write-Host $Script:DataStoreArray.vCenter.PadRight(13) -ForegroundColor cyan -NoNewline
                Write-Host $Script:DataStoreArray.VolName.PadRight(18) -ForegroundColor yellow -NoNewline
                write-host "Capacity:"([String]$Script:DataStoreArray.Capacity).PadRight(10) -ForegroundColor Magenta -NoNewline    
                write-host "NowFree:"([String]$Script:DataStoreArray.CurrentFree).PadRight(10) -ForegroundColor yellow -NoNewline    
                write-host "NowUsed:"([String]$Script:DataStoreArray.CurrentUsed).PadRight(10) -ForegroundColor white -NoNewline    
                write-host "PrevUsed:"([String]$Script:DataStoreArray.PreviousUsed).PadRight(10) -ForegroundColor cyan -NoNewline    
                If ([String]$Script:DataStoreArray.diff -like "-*"){
                       Write-Host "Loss (GB):"([String]$Script:DataStoreArray.diff).PadRight(8) -ForegroundColor Red -NoNewline 
                }ElseIf ([String]$Script:DataStoreArray.diff -eq "0.00"){
                    Write-Host "No Change:"([String]$Script:DataStoreArray.diff).PadRight(8) -ForegroundColor White -NoNewline 
                }Else{
                    Write-Host "Gain (GB):"([String]$Script:DataStoreArray.diff).PadRight(8) -ForegroundColor Green -NoNewline 
                }  
                write-host "% Used:"([String]$Script:DataStoreArray.PercentUsed).PadRight(10) -ForegroundColor yellow -NoNewline
                write-host "% Free:"([String]$Script:DataStoreArray.PercentFree).PadRight(10) -ForegroundColor green #-NoNewline
            }
    
            #--[ Generate HTML row ]------------------------------------------------
            $BGColor = "#dfdfdf"                                                    #--[ Grey default cell background ]--
            $BGColorRed = "#ff0000"                                                 #--[ Red background for alerts ]--
            $BGColorOra = "#ff9900"                                                 #--[ Orange background for alerts ]--
            $BGColorYel = "#ffd900"                                                 #--[ Yellow background for alerts ]--
            $FGColor = "#000000"                                                    #--[ Black default cell foreground ]--
            $RowData += '<tr>'                                                        #--[ Start table row ]--
            
            #--[ Rotate colors between vcenters ]--
            If (($Script:vCenters.IndexOf($Script:VCCurrent)) % 2 -eq 0 ){
                $RowData += '<td bgcolor=' + $BGColor + '><font color=#408080>' + $Script:DataStoreArray.vCenter + '</td>'
            }Else{
                  $RowData += '<td bgcolor=' + $BGColor + '><font color=#808000>' + $Script:DataStoreArray.vCenter + '</td>'
            }
            
            $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + $Script:DataStoreArray.VolName + '</td>'                                    #--[ Add volume name ]--
            $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + [math]::Round($Script:DataStoreArray.Capacity,$digits) + '</td>'            #--[ Add volume capacity in GB ]--
            #$RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + [math]::Round($Script:DataStoreArray.Capacity/1024,$digits) + '</td>' #--[ Add volume capacity in TB ]--
            $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + $Script:DataStoreArray.CurrentFree + '</td>'                                #--[ Add volume current free ]--
            $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + $Script:DataStoreArray.CurrentUsed + '</td>'                                #--[ Add volume current used ]--
            If ([int]$Script:DataStoreArray.PreviousUsed -eq 0){
                  $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>0.00</td>'                                                                #--[ Add volume previous used ]--
            }Else{
                   $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + [math]::Round($Script:DataStoreArray.PreviousUsed,$digits) + '</td>'    #--[ Add volume previous used ]--
                #$RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + $Script:DataStoreArray.PreviousFree + '</td>' #--[ Add volume previous free ]--
            }
            If ($Script:DataStoreArray.Diff -eq "0.00"){                                                                                                        #--[ Add volume gain/loss ]--
                   $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + $Script:DataStoreArray.Diff 
            }ElseIf ($Script:DataStoreArray.Diff -lt 0){
                   $RowData += '<td bgcolor=' + $BGColor + '><font color=#700000><strong>' + $Script:DataStoreArray.Diff + '</strong>'                             #--[ Red ]--
            }Else{  
                   $RowData += '<td bgcolor=' + $BGColor + '><font color=#007000><strong>' + $Script:DataStoreArray.Diff + '</strong>'                             #--[ Green ]--
            }
 
            #[int]$Percentage = [Int]$Script:DataStoreArray.PercentFree #--[ be sure to rotate the color order if you switch this ]--
            [int]$Percentage = [Int]$Script:DataStoreArray.PercentUsed
            
            #--[ See https://www.w3schools.com/colors/colors_mixer.asp for color mix info ]--
            If ($Percentage -gt 95){$BGColor = "#FF0000"}
            If ($Percentage -le 95){$BGColor = "#ff4000"}
            If ($Percentage -le 90){$BGColor = "#ff6600"}    
            If ($Percentage -le 85){$BGColor = "#ef8300"}
            If ($Percentage -le 80){$BGColor = "#e29a00"}
            If ($Percentage -le 75){$BGColor = "#d9ab00"}
            If ($Percentage -le 70){$BGColor = "#cfbc00"}
            If ($Percentage -le 65){$BGColor = "#c9c800"}
            If ($Percentage -le 60){$BGColor = "#c2d300"}    
            If ($Percentage -le 55){$BGColor = "#bfd900"}
            If ($Percentage -le 50){$BGColor = "#b2d100"}
            If ($Percentage -le 45){$BGColor = "#a6c900"}
            If ($Percentage -le 40){$BGColor = "#99c200"}
            If ($Percentage -le 35){$BGColor = "#8cba00"}
            If ($Percentage -le 30){$BGColor = "#80b200"}
            If ($Percentage -le 25){$BGColor = "#73ab00"}
            If ($Percentage -le 20){$BGColor = "#66a300"}
            If ($Percentage -le 15){$BGColor = "#4c9400"}
            If ($Percentage -le 10){$BGColor = "#338500"}
            If ($Percentage -le 5) {$BGColor = "#1a7500"}
            If ($Percentage -le 1) {$BGColor = "#006600"}
  
            If ($Percentage -ge 85){                                               
                $RowData += '<td bgcolor=' + $BGColorYel + '><font color=#ff0000><strong>' + $Percentage + ' %</strong></td>'       #--[ Add yellow on red if <20% volume percent free ]--
            #}ElseIf ($Percentage -lt 85){
            # $RowData += '<td bgcolor=' + $BGColor + '><font color=#ffffff><strong>' + $Percentage + ' %</strong></td>' #--[ Add yellow on red volume percent free ]--
            }ElseIf ($Percentage -lt 10){                             
                $RowData += '<td bgcolor=' + $BGColor + '><font color=#ffffff><strong>' + $Percentage + ' %</strong></td>'           #--[ Add yellow on red volume percent free ]--
            }Else{                                                               
                $RowData += '<td bgcolor=' + $BGColor + '><font color=#000000><strong>' + $Percentage + ' %</strong></td>'           #--[ Add volume percent free ]--
            }    
        
            $RowData += '</td></tr>'
            $Script:ReportBody += $RowData
            Clear-Variable diff -ErrorAction "SilentlyContinue"
        }   

        $Script:OutputArray | Format-Table -AutoSize | Out-File $Script:DifferenceFile -Force -Append                            #--[ Dump output to difference text file for reference ]--
        Clear-Variable RowData -ErrorAction "SilentlyContinue"    
    }Else{
        If ($Script:Console){Write-Host "`n--- No Previous File Exists. ---" -ForegroundColor red}
        #--[ No previous file ]--
    }    
    
    If ($Script:OutputArray.Length -ne 0){        #--[ Add file dates to diff file and HTML report ]--
            (Get-Content $Script:DifferenceFile) | Where { $_ } | Set-Content $DifferenceFile
            (Get-Content $Script:DifferenceFile) | Where {$_ -notmatch '----'} | Set-Content $DifferenceFile 
            Add-Content $Script:DifferenceFile –value "`nCurrent-Report $Script:CurrentDate `nPrevious-Report $Script:PreviousDate"
        
        #--[ Last line of HTML table ]--
        $FGColor = "#000000"
        $BGColor = "#bbbbbb"
        $BGColorRed = "#bbbbbb"
        $BGColorOra = "#bbbbbb"
        $BGColorYel = "#bbbbbb"
        $RowData += '<tr>'
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>Current Report</td>'    
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + $Script:CurrentDate + '</td>'    
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>&nbsp;</td>'
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>Previous Report</td>'    
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + $Script:PreviousDate + '</td>'    
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>&nbsp;</td>'
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>&nbsp;</td>'
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>&nbsp;</td>'
        $RowData += '</tr>'#>
        $Script:ReportBody += $RowData
    }
}

#==[ Main Process ]====================================================================
LoadConfig

#--[ Create header for HTML email attachment file ]--
$Script:ReportBody = @() 
$Script:ReportBody += '
<style type="text/css">
    table.myTable { border:5px solid black;border-collapse:collapse; }
    table.myTable td { border:2px solid black;padding:5px}
    table.myTable th { border:2px solid black;padding:5px;background: #949494 }
    table.bottomBorder { border-collapse:collapse; }
    table.bottomBorder td, table.bottomBorder th { border-bottom:1px dotted black;padding:5px; }
    tr.noBorder td {border: 0; }
</style>'

$Script:ReportBody += 
'<table class="myTable">
<tr class="noBorder"><td colspan=8><center><h1>- SAN Volume Utilization Report -</h1></td></tr>
<tr class="noBorder"><td colspan=8><center>The following report displays the current SAN volume usage and the percent of change from yesterdays usage.</td></tr>
<tr class="noBorder"><td colspan=8><center>The raw data files are retained on the '+$env:computername+' server for use in long term utilization tracking purposes.</center></td></tr>
<tr><th>vCenter</th><th>Volume Name</th><th>Capacity GB</th><th>Curr Free GB</th><th>Curr Used GB</th><th>Prev Used GB</th><th>Gain/Loss GB</th><th>Percent Used</th></tr>
'

CurrentStats   #--[ Call the gather new stats function ]--
CompareStats   #--[ Call the compare to previous stats function ]--

#--[ Use this section to add notes to the bottom of the HTML email attachment file. ]--
    $Script:ReportBody += '<tr class="noBorder"><td colspan=8><font color=#909090>Script "'+$Script:ScriptName+'" executed from server "'+$env:computername+'".</td></tr>'
    $Script:ReportBody += '</table><br><br>'
#--------------------------------------------------------------------------------------

SendEmail      #--[ Send the email ]--

#--[ Cleanup ]----------------------------------------------------
If (!($Script:NoUpdate)){
    If (Test-Path $Script:DifferenceFile){rename-Item -Path $Script:DifferenceFile -newname ("$PSScriptRoot\SAN-Vol_{0:MM-dd-yyyy}_Diff.log" -f (Get-Date))}
    If (Test-Path $Script:PreviousFile){Remove-Item -Path $Script:PreviousFile -Force}    #--[ If a Previous file exists remove it ]--
    If (Test-Path $Script:CurrentFile){
        Copy-Item -Path $Script:CurrentFile -Destination ("$PSScriptRoot\SAN-Vol_{0:MM-dd-yyyy}_Stats.xml" -f (Get-Date))
        Rename-Item -Path $Script:CurrentFile -NewName $Script:PreviousFile            #--[ If a Current file exists, rename this Current file to Previous ]--
    }
}Else{
    #--[ Dont do anything. Current and diff files will be removed by new stats function. Previous file should remain unchanged ]--
        If ($Console){Write-Host "`n--- DEBUG - No File Updates ---"}
}

If ($Script:Debug){
    Write-Host "`n-- Contents of difference file: " -ForegroundColor Yellow
    Write-Host Get-Content $DifferenceFile | Out-String
   }
   
$Credential = ""
$CurrentFile = ""
$PreviousFile = ""
$DifferenceFile = ""
$OutBody = ""

If ($Script:Console){Write-Host `n"--- Completed ---" -ForegroundColor Red }

<#--[ Sample of the XML configuration file -----------------------------------------------------
<!-- Settings & Configuration File -->
<Settings>
    <General>
        <DebugTarget>testbox</DebugTarget>
        <vCenters>VCSA1,VCSA2</vCenters>
    </General>
    <Email>
        <From>DailyReports@domain.com</From>
        <To>you@domain.com,me@domain.com</To>
        <Debug>you@domain.com</Debug>
        <Subject>SAN Daily Utilization Status</Subject>
        <HTML>$true</HTML>
        <SmtpServer>10.10.10.1</SmtpServer>
    </Email>
    <Credentials>
        <UserName>domain\serviceaccount</UserName>
        <Password>76492d1116743f0423413dgdyru3e0a5345MgBB6AHoAeQA0AEcBhAGEAYQBhAGQANQBA2AGQAZAA2ADQAaAB1AFEAPQA9AHwAYwAzADkADQAZQAzAGYANAAyADUAYQQANgA0AGEAMAAwADmAGQAOAA0ADEANgBiADAANwBkADEANAA4AGQAZgA3ADIAYQAwADYAZAA3AGUAZgBkAGYAZAA=</Password>
        <Key>kdhCh7HCvQAZgBiAGMAYQAYwBkADkADQAZQAzAGYANAAyADUAYQBg44$678mkrJ7IXN0IObie8mE=</Key>
    </Credentials>
</Settings>
#>