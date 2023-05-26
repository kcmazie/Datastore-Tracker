# Datastore-Tracker
Tracks VMware SAN datastores over time. Emails a daily report on changes.

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
