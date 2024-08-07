Param(
    [Switch]$Debug = $false,
    [Switch]$NoUpdate = $false,
    [Switch]$Console = $false
    )
<#==============================================================================
          File Name : Datastore-Tracker.ps1
    Original Author : Kenneth C. Mazie (kcmjr AT kcmjr.com)
                    : 
        Description : Tracks SAN datastores over time.  Emails a daily report on changes.
                    : Has 2 options for credentials, prompt user, or load from encrypted file.
                    : Encrypted file can be in script folder or remote.  Diff files are stored
                    : in script folder for reference.  There is no upper limit to these files
                    : so they must be cleared out manually as of this version.
                    : 
              Notes : Normal operation is with no command line options.  
                    : Optional arguments: -Debug $true (defaults to false.  Sends emails to debug user) 
                    :                     -NoUpdate $true (runs with current files and doesnt replace them for debugging)
                    :                     -Console $true (displays runtime info on console)
                    : 
           Warnings : None.  Read only, no edits.
                    :   
              Legal : Public Domain. Modify and redistribute freely. No rights reserved.
                    : SCRIPT PROVIDED "AS IS" WITHOUT WARRANTIES OR GUARANTEES OF 
                    : ANY KIND. USE AT YOUR OWN RISK. NO TECHNICAL SUPPORT PROVIDED.
                    :
            Credits : Code snippets and/or ideas came from many sources including but 
                    :   not limited to the following:
                    : Based on "Track Datastore Space script" Created by Hugo Peeters of www.peetersonline.nl    
                    : 
     Last Update by : Kenneth C. Mazie 
    Version History : v1.00 - 09-16-14 - Original 
     Change History : v1.10 - 08-28-15 - Edited to allow color coding of HTML output     
                    : v1.20 - 09-16-15 - Added capacity numbers to HTML output    
                    : v1.30 - 09-22-15 - Changed output from GB to TB 
                    : v2.00 - 11-30-15 - Moved all config data out to xml file and encrypted password
                    : v2.10 - 07-07-17 - Fixed bug causing script to crash.  Altered password from XML to use a key.
                    : v3.00 - 09-14-17 - Adjusted script to work with new PowerCLI v6 modules.
                    : v4.00 - 02-22-18 - Major rewrite to fix bugs in calulations and reporting.
                    : v4.10 - 03-02-18 - Minor notation fix for PS Gallery upload
                    : v5.00 - 04-03-24 - Retooled for options using object instead of global variables.  Fixed runtime bugs.
                    :                    Added error log and global catch.  Changed required PS version to 5.
                    : v5.10 - 04-18-24 - Added totals to report.  Fixed bug importing previous days data.
                    : v5.20 - 07-23-24 - Replaced missing statusmsg function.
                    #>$ScriptVer = "v5.20"<#
                    :
#===============================================================================#>
#requires -version 5.0
$Script:Console = $false

$ErrorActionPreference = "stop"
try{ #--[ Global catch for running via shceduled task.  Outputs to error log ]--

Clear-host
$ErrorActionPreference = "stop" #ilentlycontinue"
$ScriptName = ($MyInvocation.MyCommand.Name).split(".")[0] 

#--[ Runtime Testing Tweaks ]-----------
   # $Debug = $true
   # $NoUpdate = $true
#---------------------------------------

#--[ Functions ]--------------------------------------------------------
Function StatusMsg ($Msg, $Color){
    If ($Null -eq $Color){
        $Color = "Magenta"
    }
    Write-Host "-- Script Status: $Msg" -ForegroundColor $Color
    $Msg = ""
}

Function SendEmail ($ExtOption){  #--[ Email settings ]--
    $Email = new-object System.Net.Mail.MailMessage
    $Email.From = $ExtOption.Sender
    If ($ExtOption.Debug -or $ExtOption.NoUpdate -or $ExtOption.ConsoleState){
        $Email.To.Add($ExtOption.DebugEmail)
    }Else{
        $Email.To.Add($ExtOption.Recipient)
    }
    $Email.Subject = $ExtOption.Subject
    $Email.IsBodyHtml = $True
    $Email.Body = $ExtOption.ReportBody
    $smtp = new-object System.Net.Mail.SmtpClient($ExtOption.SmtpServer)
    $smtp.Send($Email)
    If ($ExtOption.Console){
        If ($ExtOption.ConsoleState){
            Write-Host "`n--- Editor Mode detected ---" -ForegroundColor red    
        }
        Write-Host "`n--- Email Sent ---" -ForegroundColor red
    }
}

Function GetConsoleHost ($ExtOption){  #--[ Detect if we are using a script editor or the console ]--
    Switch ($Host.Name){
        'consolehost'{
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleState" -Value $False -force
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleMessage" -Value "PowerShell Console detected." -Force
        }
        'Windows PowerShell ISE Host'{
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleState" -Value $True -force
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleMessage" -Value "PowerShell ISE editor detected." -Force
        }
        'PrimalScriptHostImplementation'{
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleState" -Value $True -force
            $ExtOption | Add-Member -MemberType NoteProperty -Name "COnsoleMessage" -Value "PrimalScript or PowerShell Studio editor detected." -Force
        }
        "Visual Studio Code Host" {
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleState" -Value $True -force
            $ExtOption | Add-Member -MemberType NoteProperty -Name "ConsoleMessage" -Value "Visual Studio Code editor detected." -Force
        }
    }
    If ($ExtOption.ConsoleState){
        StatusMsg $ExtOption.ConsoleMessage "Magenta" $ExtOption
    }
    Return $ExtOption
}

Function LoadConfig ($ConfigFile){
    If ($Config -ne "failed"){
        [xml]$Config = Get-Content $ConfigFile           #--[ Read & Load XML ]--  
        $ExtOption = New-Object -TypeName psobject 
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "vCenter" -Value $Config.Settings.General.vCenter
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Datacenter" -Value $Config.Settings.General.Datacenter
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "DebugEmail" -Value $Config.Settings.Email.DebugEmail
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Recipient" -Value $Config.Settings.Email.Recipient
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Sender" -Value $Config.Settings.Email.Sender
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Subject" -Value $Config.Settings.Email.Subject
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "SmtpServer" -Value $Config.Settings.Email.SmtpServer
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "HTML" -Value $Config.Settings.Email.HTML
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Subject" -Value $Config.Settings.Email.Subject
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "CredDrive" -Value $Config.Settings.Credentials.CredDrive
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "KeyFile" -Value $Config.Settings.Credentials.KeyFile
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "PasswordFile" -Value $Config.Settings.Credentials.PasswordFile
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "UserName" -Value $Config.Settings.Credentials.UserName
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "CurrentFile" -Value ($PSScriptRoot+'\Datastores_Current.xml')
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "PreviousFile" -Value ($PSScriptRoot+'\Datastores_Previous.xml')
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "DifferenceFile" -Value ($PSScriptRoot+'\Datastores_Difference.txt')
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "CurrentArray" -Value @() 
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Console" -Value $True
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "LogFile" -Value ($ConfigFile.split(".")[0]+'_Error.log') 
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Debug" -Value $False
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "NoUpdate" -Value $False
        #$ExtOption | Add-Member -Force -MemberType NoteProperty -Name "AltUser" -Value $Config.Settings.Credentials.AltUser
        #$ExtOption | Add-Member -Force -MemberType NoteProperty -Name "AltPass" -Value $Config.Settings.Credentials.AltPass
    }Else{
        StatusMsg "MISSING XML CONFIG FILE.  File is required.  Script aborted..." " Red" $True
        $Message = (
'--[ External XML config file example ]-----------------------------------
--[ To be named the same as the script and located in the same folder as the script ]--

<?xml version="1.0" encoding="utf-8"?>
<Settings>
    <General>
        <DebugTarget>testbox</DebugTarget>
        <vCenters>MyVcenter.com</vCenters>
        <Datacenter>DC01</Datacenter>
    </General>
    <Email>
        <Sender>DailyReports@company.com</Sender>
        <Recipient>me@company.com</Recipient>
        <DebugEmail>me@company.com</DebugEmail>
        <Subject>SAN Daily Utilization Status</Subject>
        <HTML>$true</HTML>
        <SmtpServer>mail.company.com</SmtpServer>
    </Email>
    <Credentials>
        <UserName></UserName>
        <Password></Password>
        <Key></Key>
        <CredDrive>c:</CredDrive>
        <PasswordFile>Pass.txt</PasswordFile>
        <KeyFile>Key.txt</KeyFile>
    </Credentials>  
</Settings> ')
Write-host $Message -ForegroundColor Yellow
    }
    Return $ExtOption
}

Function CurrentStats ($ExtOption){
    #==[ Get Current Statistics ]===================================================
    $Digits = 2
    If ($ExtOption.Console){Write-Host "`r`n--- Collecting Current Datastore Statistics ---  " -ForegroundColor Yellow}
    If (!($ExtOption.NoUpdate)){
        If (Test-Path $ExtOption.CurrentFile){Remove-Item -Path $ExtOption.CurrentFile -Force}            #--[ Clear out the current file unless debugging. ]--
        If (Test-Path $ExtOption.DifferenceFile){Remove-Item -Path $ExtOption.DifferenceFile -Force}      #--[ If a Difference file exists remove it as well ]--
    }
    ForEach ($VIServer in $ExtOption.vCenter){
        If ($ExtOption.Debug -or $ExtOption.Console){Write-Host "`r`n--- Gathering Data From: $VIServer --- " -ForegroundColor Cyan}
        $VC = Connect-VIServer -Server $VIServer -Credential $ExtOption.Credential   #--[ Used to connect to Virtual Center ]--
        $DC = Get-DataCenter -Name $ExtOption.DataCenter
        $DataStores = Get-Datastore | Sort-Object Name | Select-Object -Unique     #--[ Get all datastores and put them in alphabetical order & remove accidental duplicates ]--
        $CurrentArray = @()  
        ForEach ($Store in $DataStores){    #--[ Loop through datastores ]--
            If ($ExtOption.Console){
                Write-Host "-- Processing Datastore: " -ForegroundColor Yellow -NoNewline
                Write-Host ([string]$Store).PadRight(22) -ForegroundColor Magenta -NoNewline
            }
            if (($Store -notlike "*Local*") -and ($Store -like "40ESX*")){
                $ObjCurrent = "" | Select-Object vCenter, Name, CapacityGB, UsedGB, FreeGB, PercFree, PercUsed    
                $ObjCurrent.CapacityGB = [math]::Round($store.CapacityGB,$Digits)
                $ObjCurrent.UsedGB = [math]::Round(($store.CapacityGB - $store.FreeSpaceGB),$Digits)
                $ObjCurrent.FreeGB = [math]::Round($store.FreeSpaceGB,$Digits)
                $ObjCurrent.vCenter = $VIServer
                $ObjCurrent.Name = $store.Name
                $ObjCurrent.PercFree = [math]::Round(100 * $store.FreeSpaceGB / $store.CapacityGB,$Digits)
                $ObjCurrent.PercUsed = 100-$ObjCurrent.PercFree
                $CurrentArray += $ObjCurrent                   #--[ Add the object to the output array    ]--
                If ($ExtOption.Console){Write-Host $ObjCurrent }
            }Else{
                If ($ExtOption.Console){Write-Host "-- Bypassed --"}
            }    
        }
        Disconnect-VIServer -Confirm:$False    #--[ Disconnect from Virtual Center ]--
    }

    If (!($ExtOption.NoUpdate)){
        $CurrentArray | Export-Clixml -Path $ExtOption.CurrentFile    #--[ Export the output to an xml file; the new Current file ]--
        If (!(Test-Path -path $ExtOption.PreviousFile)){
            Copy-Item $ExtOption.CurrentFile $ExtOption.PreviousFile
        }    
    }

    $CurrentDate = (Get-Item $ExtOption.CurrentFile).LastWriteTime | Get-Date -Format d   #--[ Get file dates for new file names ]--
    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "CurrentDate" -Value $CurrentDate

    $PreviousDate = (Get-Item $ExtOption.PreviousFile).LastWriteTime  | Get-Date -Format d 
    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "PreviousDate" -Value $PreviousDate

  #  If ($ExtOption.Debug){
   #     Write-Host "`nCurrent Date: $CurrentDate"
        #Write-host "Current File: $ExtOption.CurrentFile`n"
    #    Write-host "Previous Date: $PreviousDate"
        #Write-host "Previous File: $ExtOption.PreviousFile`n"
    #}
    Return $ExtOption
}

Function CompareStats ($ExtOption){     
    #--[Compare the Current information to that in the Previous file ]--------------
    $Digits = 2
    If ($ExtOption.Console){Write-Host "`r`n--- Processing Changes ---" -ForegroundColor Cyan}
    $PreviousArray = Import-Clixml $ExtOption.PreviousFile                                #--[ Import the Previous file ]--
    $CurrentArray= Import-Clixml $ExtOption.CurrentFile                                   #--[ Import the Current file ]--
    $OutputArray = @()                                                                    #--[ Create an array to hold the differences ]--
    $Capacity = ""
    $PreviousUsed = ""
    $PercentFree = ""
    $PercentUsed = ""
    $CurrentUsed = ""
    $CurrentFree = ""
    $PreviousFree = ""
    $GainLoss = ""
    $ReportBody = $ExtOption.ReportBody

    If (Test-Path $ExtOption.PreviousFile){ 
        ForEach ($CurrentDS in $CurrentArray){              
            #--[ Loop through the current datastores ]--
            $VCCurrent = $CurrentDS.vCenter
            $RowData = ""
            $diff = ""
            $DataStoreArray = "" | Select-Object vCenter, VolName, Capacity, CurrentUsed, CurrentFree, PreviousUsed, PreviousFree, PercentFree, PercentUsed, Diff 
          
            #--[ Process the comparison ]-------------------------------------------

            #--[ Calculate the difference compensating for identical datastore names across multiple vcenters ]--
            $diff = Compare-Object ($PreviousArray | Where-Object { ($_.Name -eq $CurrentDS.Name) -and ($_.vCenter -eq $VCCurrent)}) $CurrentDS -Property UsedGB -ErrorAction SilentlyContinue

            #--[ The most important property is the calculated difference between the current and previous values of PercFree. You can substitute it for CurrentUsedGB if you like. ]--
            #$DataStoreArray.Diff = ($diff | Where-Object { $_.SideIndicator -eq '=>' }).PercFree - ($diff | Where-Object { $_.SideIndicator -eq '<=' }).PercFree
            $DataStoreArray.Diff = ($diff | Where-Object { $_.SideIndicator -eq '<=' }).UsedGB - ($diff | Where-Object { $_.SideIndicator -eq '=>' }).UsedGB
            #$DataStoreArray.Diff = ($diff | Where-Object { $_.SideIndicator -eq '<=' }).FreeGB - ($diff | Where-Object { $_.SideIndicator -eq '=>' }).FreeGB
            # typical diff = @{FreeGB=2052.90; SideIndicator==>} @{FreeGB=2053.07; SideIndicator=<=}
            #                                      current =>                        previous <= 
               
            If (($DataStoreArray.Diff -eq "") -or ($Null -eq $DataStoreArray.Diff)){$DataStoreArray.Diff = "0.00"}           #--[ Compensate for no results ]--

            #==[ Final results for output ]========================================= 
            $DataStoreArray.vCenter = $CurrentDS.vCenter 
            $DataStoreArray.VolName = $CurrentDS.Name    
            $DataStoreArray.Capacity = $CurrentDS.CapacityGB
            $DataStoreArray.PreviousUsed = ($PreviousArray | Where-Object { $_.vCenter -eq $CurrentDS.vCenter -and $_.Name -eq $CurrentDS.Name }).UsedGB 
            $DataStoreArray.PercentFree = $CurrentDS.PercFree 
            $DataStoreArray.PercentUsed = $CurrentDS.PercUsed 
            $DataStoreArray.CurrentUsed = $CurrentDS.UsedGB    
            $DataStoreArray.CurrentFree = $CurrentDS.FreeGB    
            $DataStoreArray.PreviousFree = ($PreviousArray | Where-Object { $_.vCenter -eq $CurrentDS.vCenter -and $_.Name -eq $CurrentDS.Name }).FreeGB
            #==[ Final results for output ]========================================= 
        
            $OutputArray += $DataStoreArray                                                 #--[ Add result to the output array ]--        
        
            If($ExtOption.Console){  
                Write-Host $DataStoreArray.vCenter.PadRight(($DataStoreArray.vCenter.length)+2) -ForegroundColor cyan -NoNewline
                Write-Host $DataStoreArray.VolName.PadRight(18) -ForegroundColor yellow -NoNewline
                write-host "Capacity:"([String]$DataStoreArray.Capacity).PadRight(10) -ForegroundColor Magenta -NoNewline    
                write-host "NowFree:"([String]$DataStoreArray.CurrentFree).PadRight(10) -ForegroundColor yellow -NoNewline    
                write-host "NowUsed:"([String]$DataStoreArray.CurrentUsed).PadRight(10) -ForegroundColor white -NoNewline    
                write-host "PrevUsed:"([String]$DataStoreArray.PreviousUsed).PadRight(10) -ForegroundColor cyan -NoNewline    
                If ([String]$DataStoreArray.diff -like "-*"){
                       Write-Host "Loss (GB):"([String]$DataStoreArray.diff).PadRight(8) -ForegroundColor Red -NoNewline 
                }ElseIf ([String]$DataStoreArray.diff -eq "0.00"){
                    Write-Host "No Change:"([String]$DataStoreArray.diff).PadRight(8) -ForegroundColor White -NoNewline 
                }Else{
                    Write-Host "Gain (GB):"([String]$DataStoreArray.diff).PadRight(8) -ForegroundColor Green -NoNewline 
                }  
                write-host "% Used:"([String]$DataStoreArray.PercentUsed).PadRight(10) -ForegroundColor yellow -NoNewline
                write-host "% Free:"([String]$DataStoreArray.PercentFree).PadRight(10) -ForegroundColor green #-NoNewline
            }
    
            #--[ Generate HTML row ]------------------------------------------------
            $BGColor = "#dfdfdf"                                                    #--[ Grey default cell background ]--
            $BGColorRed = "#ff0000"                                                 #--[ Red background for alerts ]-- 
            $BGColorOra = "#ff9900"                                                 #--[ Orange background for alerts ]-- 
            $BGColorYel = "#ffd900"                                                 #--[ Yellow background for alerts ]-- 
            $FGColor = "#000000"                                                    #--[ Black default cell foreground ]--
            $RowData += '<tr>'                                                      #--[ Start table row ]--
            
            #--[ Use this to rotate colors between vcenters if more than one exist ]--
            # If (($vCenters.IndexOf($VCCurrent)) % 2 -eq 0 ){
                $RowData += '<td bgcolor=' + $BGColor + '><font color=#408080>' + $DataStoreArray.vCenter + '</td>'
            # }Else{
            #    $RowData += '<td bgcolor=' + $BGColor + '><font color=#808000>' + $DataStoreArray.vCenter + '</td>'
            # }
            
            $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + $DataStoreArray.VolName + '</td>'                                    #--[ Add volume name ]--
            $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + [math]::Round($DataStoreArray.Capacity,$Digits) + '</td>'            #--[ Add volume capacity in GB ]--            
            #$RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + [math]::Round($DataStoreArray.Capacity/1024,$Digits) + '</td>'      #--[ Add volume capacity in TB ]--    
            $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + $DataStoreArray.CurrentFree + '</td>'                                #--[ Add volume current free ]--
            $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + $DataStoreArray.CurrentUsed + '</td>'                                #--[ Add volume current used ]--
            If ([int]$DataStoreArray.PreviousUsed -eq 0){
                  $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>0.00</td>'                                                                #--[ Add volume previous used ]--
            }Else{
                   $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + [math]::Round($DataStoreArray.PreviousUsed,$Digits) + '</td>'    #--[ Add volume previous used ]--
                #$RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + $DataStoreArray.PreviousFree + '</td>'                          #--[ Add volume previous free ]--
            }
            If ($DataStoreArray.Diff -eq "0.00"){                                                                                                           #--[ Add volume gain/loss ]--
                   $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + $DataStoreArray.Diff 
            }ElseIf ($DataStoreArray.Diff -lt 0){
                   $RowData += '<td bgcolor=' + $BGColor + '><font color=#700000><strong>' + $DataStoreArray.Diff + '</strong>'                             #--[ Red ]--
            }Else{  
                   $RowData += '<td bgcolor=' + $BGColor + '><font color=#007000><strong>' + $DataStoreArray.Diff + '</strong>'                             #--[ Green ]--
            }
 
            #[int]$Percentage = [Int]$DataStoreArray.PercentFree           #--[ be sure to rotate the color order if you switch this ]--
            [int]$Percentage = [Int]$DataStoreArray.PercentUsed
            
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
            #    $RowData += '<td bgcolor=' + $BGColor + '><font color=#ffffff><strong>' + $Percentage + ' %</strong></td>'           #--[ Add yellow on red volume percent free ]--
            }ElseIf ($Percentage -lt 10){                             
                $RowData += '<td bgcolor=' + $BGColor + '><font color=#ffffff><strong>' + $Percentage + ' %</strong></td>'           #--[ Add yellow on red volume percent free ]--
            }Else{                                                               
                $RowData += '<td bgcolor=' + $BGColor + '><font color=#000000><strong>' + $Percentage + ' %</strong></td>'           #--[ Add volume percent free ]--
            }    
        
            $RowData += '</td></tr>'
            $ReportBody += $RowData
            Clear-Variable diff -ErrorAction "SilentlyContinue"
            
            #--[ Running Totals ]---------------------------
            $Capacity = [Int]$Capacity+[Int]$DataStoreArray.Capacity
            $PreviousUsed = [Int]$PreviousUsed+[Int]$DataStoreArray.PreviousUsed
            $PercentFree = [Int]$PercentFree+[Int]$DataStoreArray.PercentFree
            $PercentUsed = [Int]$PercentUsed+[Int]$DataStoreArray.PercentUsed
            $CurrentUsed = [Int]$CurrentUsed+[Int]$DataStoreArray.CurrentUsed
            $CurrentFree = [Int]$CurrentFree+[Int]$DataStoreArray.CurrentFree
            $PreviousFree = [int]$PreviousFree+[int]$DataStoreArray.PreviousFree
            $GainLoss = [int]$GainLoss+[int]$DataStoreArray.diff
        }   

        $PercentUsed = [math]::Round(100 -(100 * $CurrentFree / $Capacity))  #--[ Total percent in use ]--                       

        $OutputArray | Format-Table -AutoSize | Out-File $ExtOption.DifferenceFile -Force -Append  #--[ Dump output to difference text file for reference ]--
        Clear-Variable RowData -ErrorAction "SilentlyContinue"    
    }Else{
        If ($ExtOption.Console){Write-Host "`n--- No Previous File Exists. ---" -ForegroundColor red}
        #--[ No previous file ]--
    }    
  
    If ($OutputArray.Length -ne 0){        #--[ Add file dates to diff file and HTML report ]--
        (Get-Content $ExtOption.DifferenceFile) | Where-Object { $_ } | Set-Content $ExtOption.DifferenceFile
        (Get-Content $ExtOption.DifferenceFile) | Where-Object {$_ -notmatch '----'} | Set-Content $ExtOption.DifferenceFile 
        Add-Content $ExtOption.DifferenceFile –value "`nCurrent-Report $CurrentDate `nPrevious-Report $PreviousDate"
        
        #--[ Last line of HTML table ]--
        $FGColor = "#000000"
        $BGColor = "#bbbbbb"
        $BGColorRed = "#bbbbbb"
        $BGColorOra = "#bbbbbb"
        $BGColorYel = "#bbbbbb"
        $RowData += '<tr>'
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '><center>System Totals</center></td>'    
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>&nbsp;</td>'    
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>'+$Capacity+' GB</td>'
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>'+$CurrentFree+' GB</td>'
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>'+$CurrentUsed+' GB</td>'
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>'+$PreviousUsed+' GB</td>'
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>'+$GainLoss+' GB</td>'
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>'+$PercentUsed+' %</td>'
        $RowData += '</tr>'
        $RowData += '<tr>'
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>Current Report</td>'    
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + $ExtOption.CurrentDate + '</td>'    
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>&nbsp;</td>'
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>Previous Report</td>'    
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>' + $ExtOption.PreviousDate + '</td>'    
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>&nbsp;</td>'
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>&nbsp;</td>'
        $RowData += '<td bgcolor=' + $BGColor + '><font color=' + $FGColor + '>&nbsp;</td>'
        $RowData += '</tr>'#>
        $ReportBody += $RowData
    }
    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "ReportBody" -Value $ReportBody
    Return $ExtOption
}

#==[ Main Process ]====================================================================

#--[ Load external XML options file ]------------------------------------------------
$ConfigFile = $PSScriptRoot+"\"+$MyInvocation.MyCommand.Name.Split(".")[0]+".xml"
If (Test-Path $ConfigFile){                          #--[ Error out if configuration file doesn't exist ]--
    $ExtOption = LoadConfig $ConfigFile 
    If ($Debug){
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Debug" -Value $True 
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "NoUpdate" -Value $True
    }
    If ($NoUpdate){
        $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "NoUpdate" -Value $True
    }
}Else{
    LoadConfig "failed"
    StatusMsg "MISSING XML CONFIG FILE.  File is required.  Script aborted..." " Red" $Debug
    break;break;break
}

if (!(Get-Module -Name "vmware*")) {    
    Try{  
        #get-module -ListAvailable vm* | import-module -ErrorAction SilentlyContinue | Out-Null  #--[ Load all VMware modules ]--
        import-module -name vmware.powercli
    }Catch{
        Add-Content -path $ExtOption.LogFile -value "-- Error loading VMware module."
        Add-Content -path $ExtOption.LogFile -value ("Error: "+$_.Error.Message)
        Add-Content -path $ExtOption.logFile -value ("Exception: "+$_.Exception.Message)
    }
    #Set-PowerCLIConfiguration -invalidcertificateaction Ignore  #--[ Only run if there are vCenter dert errors ]--
}

#--[ Determine if running from an ISE ]--
$ExtOption = GetConsoleHost $ExtOption  

#--[ Prepare Credentials ]--
$UN = $Env:USERNAME
$DN = $Env:USERDOMAIN
$UID = $DN+"\"+$UN

#--[ Test location of encrypted files, remote or local ]--
If (Test-Path -path ($ExtOption.CredDrive+'\'+$ExtOption.PasswordFile)){
    $PF = ($ExtOption.CredDrive+'\'+$ExtOption.PasswordFile)
    $KF = ($ExtOption.CredDrive+'\'+$ExtOption.KeyFile)
}Else{
    $PF = ($PSScriptRoot+'\'+$ExtOption.PasswordFile)
    $KF = ($PSScriptRoot+'\'+$ExtOption.KeyFile)
}

If (Test-Path -Path $PF){
    $Base64String = (Get-Content $KF)
    $ByteArray = [System.Convert]::FromBase64String($Base64String)
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UID, (Get-Content $PF | ConvertTo-SecureString -Key $ByteArray)
    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Credential" -Value $Credential
}Else{
    $Credential = $Script:ManualCreds
    $ExtOption | Add-Member -Force -MemberType NoteProperty -Name "Credential" -Value $Credential
}

#--[ Create header for HTML email attachment file ]--
$ReportBody = @() 
$ReportBody += '
<style type="text/css">
    table.myTable { border:5px solid black;border-collapse:collapse; }
    table.myTable td { border:2px solid black;padding:5px}
    table.myTable th { border:2px solid black;padding:5px;background: #949494 }
    table.bottomBorder { border-collapse:collapse; }
    table.bottomBorder td, table.bottomBorder th { border-bottom:1px dotted black;padding:5px; }
    tr.noBorder td {border: 0; }
</style>'

$ReportBody += 
'<table class="myTable">
<tr class="noBorder"><td colspan=8><center><h1>- SAN Volume Utilization Report -</h1></td></tr>
<tr class="noBorder"><td colspan=8><center>The following report displays the current SAN volume usage and the percent of change from yesterdays usage.</td></tr>
<tr class="noBorder"><td colspan=8><center>The raw data files are retained on the '+$env:computername+' computer for use in long term utilization tracking purposes.</center></td></tr>
<tr><th>vCenter</th><th>Volume Name</th><th>Capacity GB</th><th>Curr Free GB</th><th>Curr Used GB</th><th>Prev Used GB</th><th>Gain/Loss GB</th><th>Percent Used</th></tr>
'

$ExtOption | Add-Member -Force -MemberType NoteProperty -Name "ReportBody" -Value $ReportBody
$ExtOption = CurrentStats $ExtOption  #--[ Call the gather new stats function ]--
$ExtOption = CompareStats $ExtOption  #--[ Call the compare to previous stats function ]--
 
$ReportBody =  $ExtOption.ReportBody+'<tr class="noBorder"><td colspan=8><font color=#909090>Script "'+$ScriptName+'" executed from system "'+$env:computername+'".</td></tr>'
If ($ExtOption.ConsoleState){
    $ReportBody += '<tr class="noBorder"><td colspan=8><font color=#ff0000>--- Editor mode detected.  Only emailing debug user. ---</td></tr>'
}
$ReportBody += '</table><br><br>'
$ExtOption | Add-Member -Force -MemberType NoteProperty -Name "ReportBody" -Value $ReportBody
#--------------------------------------------------------------------------------------    

SendEmail $ExtOption     #--[ Send the email ]--

#--[ Cleanup ]----------------------------------------------------
If (!($ExtOption.NoUpdate)){
    $TodaysFile = "$PSScriptRoot\SAN-Vol_{0:MM-dd-yyyy}_Diff.log" -f (Get-Date)
    If (Test-Path $TodaysFile){Remove-Item $TodaysFile -force}
    If (Test-Path $ExtOption.DifferenceFile){rename-Item -Path $ExtOption.DifferenceFile -newname $TodaysFile}
    If (Test-Path $ExtOption.PreviousFile){Remove-Item -Path $ExtOption.PreviousFile -Force}    #--[ If a Previous file exists remove it ]--
    If (Test-Path $ExtOption.CurrentFile){
        Copy-Item -Path $ExtOption.CurrentFile -Destination ("$PSScriptRoot\SAN-Vol_{0:MM-dd-yyyy}_Stats.xml" -f (Get-Date))
        Rename-Item -Path $ExtOption.CurrentFile -NewName $ExtOption.PreviousFile            #--[ If a Current file exists, rename this Current file to Previous ]--
    }
}Else{
    #--[ Dont do anything.  Current and diff files will be removed by new stats function. Previous file should remain unchanged ]--
    If ($ExtOption.Console){
        StatusMsg "NoUpdate Mode - No File Updates ---" "Yellow" $ExtOption
    }
}

If ($ExtOption.Debug){

    $Msg = "Current Date: "+$ExtOption.CurrentDate
    StatusMsg $Msg "Yellow" $ExtOption
    $Msg = "Previous Date: "+$ExtOption.PreviousDate
    StatusMsg $Msg "Yellow" $ExtOption

    Write-Host "`n-- Contents of difference file:  " -ForegroundColor Yellow
foreach ($Diff in (get-content $ExtOption.DifferenceFile) ){
    Write-Host $Diff}
}

If ($ExtOption.Console){Write-Host `n"--- Completed ---" -ForegroundColor Red }

}Catch{
    Add-Content -path $ExtOption.Logfile -value "global"
    Add-Content -path $ExtOption.Logfile -value $_.Error.Message
    Add-Content -path $ExtOption.Logfile -value $_.Exception.Message 
}
