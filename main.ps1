param(
    [Parameter()]
    [string]$SqlInstance,
    [string]$Database,
    [string]$Version,
    [string]$TempDir = $Env:RUNNER_TEMP,
    [string]$User,
    [string]$Password
)

$DownloadUrl = "http://tsqlt.org/download/tsqlt/?version=$Version"
$zipFile = Join-Path $TempDir "tSQLt.zip"
$zipFolder = Join-Path $TempDir "tSQLt"
$CLRSecurityQuery = "
/* Turn off CLR Strict for 2017+ fix */
IF EXISTS (SELECT 1 FROM sys.configurations WHERE name = 'clr strict security')
BEGIN
	EXEC sp_configure 'show advanced options', 1;
	RECONFIGURE;

	EXEC sp_configure 'clr strict security', 0;
	RECONFIGURE;
END
GO"

try {
    Write-Output "Downloading $DownloadUrl"
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $zipFile -ErrorAction Stop -UseBasicParsing
    Expand-Archive -Path $zipFile -DestinationPath $zipFolder -Force
    $installFile = (Get-ChildItem $zipFolder -Filter "tSQLt.class.sql").FullName
    $setupFile = (Get-ChildItem $zipFolder -Filter "PrepareServer.sql").FullName
    Write-Output "Download complete."
}
catch {
    Write-Error "Unable to download & extract tSQLt from '$DownloadUrl'. Ensure version is valid." -ErrorAction "Stop"
}

if ($isMacOs) {
    Write-Output "Only Linux and Windows operation systems supported."
}
elseif ($IsLinux) {
    if ($User -and $Password) {
        sqlcmd -S $SqlInstance -d $Database -q $CLRSecurityQuery -U $User -P $Password
        sqlcmd -S $SqlInstance -d $Database -i $setupFile -U $User -P $Password
        sqlcmd -S $SqlInstance -d $Database -i $installFile -U $User -P $Password
    }
    else {
        sqlcmd -S $SqlInstance -d $Database -q $CLRSecurityQuery
        sqlcmd -S $SqlInstance -d $Database -i $setupFile
        sqlcmd -S $SqlInstance -d $Database -i $installFile
    }

}
elseif ($IsWindows) {
    $connSplat = @{
        ServerInstance = $SqlInstance
    }
    if ($User -and $Password) {
        $SecPass = ConvertTo-SecureString -String $Password -AsPlainText -Force
        $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $SecPass
        $connSplat.add("Credential", $Credential)
    }

    if (!(Get-SqlDatabase @connSplat -Name $Database)) {
        Write-Error "Database '$Database' not found." -ErrorAction "Stop"
    }
    Invoke-SqlCmd @connSplat -Database $Database -Query $CLRSecurityQuery -OutputSqlErrors $true
    Invoke-SqlCmd @connSplat -Database $Database-InputFile $setupFile -OutputSqlErrors $true
    Invoke-SqlCmd @connSplat -Database $Database -InputFile $installFile -Verbose -OutputSqlErrors $true
}

Write-Output "Installation of tSQLt $Version complete."