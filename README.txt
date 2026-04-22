
<#==============================================================================
          File Name : Datastore-Tracker.ps1
    Original Author : Kenneth C. Mazie (kcmjr AT kcmjr.com)
                    : 
        Description : Tracks SAN datastores over time.  Emails a daily report on changes.
                    : Has 2 options for credentials, prompt user, or load from encrypted file.
                    : Encrypted file can be in script folder or remote.  Diff files are stored
                    : in script folder for reference.  Stored diff file dates are checked each 
                    : run and if month date matches this month nothing is done.  If month
					: matches previous month all diff files are zipped for archiving.
                    : 
              Notes : Normal operation is with no command line options.  
                    : Optional arguments: (entered below)
                    :                     -Debug $true (defaults to false.  Sends emails to debug user) 
                    :                     -NoUpdate $true (runs with current files and doesnt replace them for debugging)
                    :                     -Console $true (displays runtime info on console)
                    : 
           Warnings : None.  Read only, no edits.
                    :   
              Legal : Public Domain. Modify and redistribute freely. No rights reserved.
                    : SCRIPT PROVIDED "AS IS" WITHOUT WARRANTIES OR GUARANTEES OF 
                    : ANY KIND. USE AT YOUR OWN RISK. NO TECHNICAL SUPPORT PROVIDED.
                    :
            Credits : Code snippets and/or ideas came from many sources including but not limited to the following:
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
                    : v5.30 - 04-24-25 - Altered editor mode to force noupdate so as to not overwrite diff during testing.
                    : v6.00 - 06-24-25 - Added console mode for testing without email and to show runtime info.  Added file 
                    :                    dates to report and diff file.  Added error log to track errors during runs.  Added 
                    :                    global catch for scheduled task runs.  Added more status messages throughout script.
                    :                    Retooled file management to create date stamped backup files.  Added archiving
					:                    routine to keep files from filling up the script folder.
					: v6.10 - 04-22-26 - Added check to verify previous XML file is being deleted.
                    #>$ScriptVer = "v6.10"<#
                    :
#===============================================================================#>
