# Start-VDICleanup
Start-VDICleanup.ps1 uses PowerShell jobs and VMware PowerCLI to perform a multithreaded cleanup of a VDI environment.

New cleanup locations are easy to add, though they need to be added midway through the script, once added, it is a very efficient script which has been tested in a 3500 VM environment and completed in less than 8 hours when run regularly on a scheduled task.

Start-VDICleanup depends on Get-LastVMUser.psm1 in the Modules folder, so be sure to download that as well.

Best used with Linked Clone style environments, the script will require some tweaking, depending on your environment, specifically the Inventory Building function and the Paths you would like to cleanup
