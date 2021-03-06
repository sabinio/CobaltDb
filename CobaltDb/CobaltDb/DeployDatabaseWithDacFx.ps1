#create some params
param([string]$targetConnectionString, [string]$Dacpac, [string]$targetDatabaseName, [string]$Profile, [bool] $deploy, [bool] $script, [bool] $azure)
 
 #where the patest dacFx is if you have installed Visual Srudio 2015 version. For VS 2013  alter '14.0' to '13.0'
$dacfxPath = 'C:\Program Files (x86)\Microsoft Visual Studio 14.0\Common7\IDE\Extensions\Microsoft\SQLDB\DAC\130\Microsoft.SqlServer.Dac.dll'

#set params
$logs = "$PSScriptRoot"
$dacpac = Join-Path $PSScriptRoot 'CobaltDb.dacpac'
$profile = Join-Path $PSScriptRoot 'CobaltDb.publish.xml'

#alter conection string based on value. So we can alter 'target platform' for cobaltdb properties and set $azure to $true or $false depending on deployment type
$azure=$false  
 if ($azure)
 {
$targetConnectionString = ''
}
else
{
$targetConnectionString = 'SERVER=.;Integrated Security=True'
}

$targetDatabaseName = 'CobaltDb'

#in this script there are three samples:
    #$deploy - deploy using the dacServices.Deploy method. This is available in older versions of DacFx API.
    #$script - generate script using dacServices.GenerateDeployScript. Also avilable in older versions
    #newway - generates deploy script, deploy report AND executes the deployment all in one step. Neat! Only available in 16.5 (and later, probably, I'm not Psychic....)
    # set the values to true or false depending on what method you want to try.
    # default is $newway
$deploy = $false
$script= $false
$newWay = $true

# Load the DAC assembly
Write-Verbose 'Testing if DACfx was installed...'

if (!$dacfxPath)
{
    throw 'No usable version of Dac Fx found.'
}
else
{
    try
    {
        Write-Verbose -Verbose 'DacFX found, attempting to load DAC assembly...'
        Add-Type -Path $dacfxPath
        Write-Verbose -Verbose 'Loaded DAC assembly.'
    }
    catch [System.Management.Automation.RuntimeException]
    {
        throw "Exception caught: "+$_.Exception.GetType().FullName
    }
}


if (Test-Path $dacpac)
{
    # Load DacPackage
    $dacPackage = [Microsoft.SqlServer.Dac.DacPackage]::Load($Dacpac)
    Write-Host ('Loaded dacpac ''{0}''.' -f $Dacpac)
}
else 
{
    Write-Verbose "$dacpac not found!"
    throw
}

if (Test-Path $Profile)
{
    # Load DacProfile
    $dacProfile = [Microsoft.SqlServer.Dac.DacProfile]::Load($Profile)
    Write-Host ('Loaded publish profile ''{0}''.' -f $Profile)
}
else 
{
    Write-Verbose "$profile not found!"
    throw
}
 
# Setup DacServices with connection string
$dacServices = New-Object Microsoft.SqlServer.Dac.DacServices $targetConnectionString
 
if ($script)
{
#old script way: will only generate the deployment script and nothing else.
    try 
    {
        Write-Host 'Generating Deployment Script...'
        $dacServices.GenerateDeployScript($dacPackage,$targetDatabaseName, $dacProfile.DeployOptions) | Out-File "$logs\$targetDatabaseName.GenerateDeployScript.sql"
        Write-Host "Deployment Script Created at $logs\$targetDatabaseName.GenerateDeployScript.sql!"
    } 
    catch [Microsoft.SqlServer.Dac.DacServicesException] 
    {
        throw ('Deployment failed: ''{0}'' Reason: ''{1}''' -f $_.Exception.Message, $_.Exception.InnerException.Message)
    }
}
if ($deploy)
{
    # Deploy package
    # will not generate a deployment script
    try 
    {
        Write-Host "Executing Deployment..."
        $dacServices.Deploy($dacPackage, $targetDatabaseName, $true, $dacProfile.DeployOptions, $null)
        Write-Host "Deployment successful!"
        }  
    catch [Microsoft.SqlServer.Dac.DacServicesException] 
    {
        throw ('Deployment failed: ''{0}'' Reason: ''{1}''' -f $_.Exception.Message, $_.Exception.InnerException.Message)
    }
}
if($newway)
{
# new publish Options class.
# we set what scripts we want to generate (ie both deploy report and deploy script, or just one or the other
#script paths are optional, we can pipe to Out-File
#have to "Out-File" the deployment report anyway because PublishOptions does not have a property for deploy report path
#Also notice that dacprofile.deployoptions are now a property of PublishOptions class.
$options = @{
    GenerateDeploymentScript = $true
    GenerateDeploymentReport = $true
    DatabaseScriptPath = "$logs\$targetDatabaseName.DatabaseScriptpath.sql"
    MasterDbScriptPath = "$logs\"+$targetDatabaseName+"_Master.MasterDbScriptPath.sql"
    DeployOptions = $dacProfile.DeployOptions
    }
    # Deploy package
    try 
    {
        Write-Host "Executing Deployment using new process..."
        #to try out just scripting, alter from publish method to script method
        #$result = $dacServices.script($dacPackage, $targetDatabaseName, $options)
        $result = $dacServices.publish($dacPackage, $targetDatabaseName, $options)
        Write-Host "Deployment successful!"
        Write-Host $result.DatabaseScript
        Write-Host $result.MasterDbScript
        $result.DeploymentReport | Out-File "$logs\$targetDatabaseName.Result.DeploymentReport.xml"
        Write-Host $options.databasescriptpath
        }  
    catch [Microsoft.SqlServer.Dac.DacServicesException] 
    {
        throw ('Deployment failed: ''{0}'' Reason: ''{1}''' -f $_.Exception.Message, $_.Exception.InnerException.Message)
    }
}

