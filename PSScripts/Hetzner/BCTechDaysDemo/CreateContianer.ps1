﻿. (Join-Path $PSScriptRoot '.\_Settings.ps1')

$artifactUrl = Get-BCArtifactUrl `
    -Type OnPrem `
    -Select Weekly `
    -Country be 

$ContainerName = 'BCTechDays'
# $ImageName = $ContainerName

$includeTestToolkit = $true
$includeTestLibrariesOnly = $true
$includeTestFrameworkOnly = $false
$includePerformanceToolkit = $true
$forceRebuild = $true
# $bcpt_appinsights = "InstrumentationKey=f8c1258a-940b-4deb-b680-d79c99e15493;IngestionEndpoint=https://westeurope-5.in.applicationinsights.azure.com/;LiveEndpoint=https://westeurope.livediagnostics.monitor.azure.com/"
# $bcpt_appinsights = "InstrumentationKey=444af6dc-a16c-4b09-8c39-3beeec98a6b7;IngestionEndpoint=https://westeurope-5.in.applicationinsights.azure.com/;LiveEndpoint=https://westeurope.livediagnostics.monitor.azure.com/"
# $bcpt_appinsights = "InstrumentationKey=c5149260-22bd-4364-a330-541eeefb9829;IngestionEndpoint=https://westeurope-5.in.applicationinsights.azure.com/;LiveEndpoint=https://westeurope.livediagnostics.monitor.azure.com/"
$bcpt_appinsights = "InstrumentationKey=26c1544e-87fe-422b-b6ff-0c0ac230a281;IngestionEndpoint=https://westeurope-5.in.applicationinsights.azure.com/;LiveEndpoint=https://westeurope.livediagnostics.monitor.azure.com/;ApplicationId=5991cadf-60cd-42fb-8bf8-9eee9c1be21e"

$StartMs = Get-date

New-BcContainer `
    -accept_eula `
    -containerName $ContainerName  `
    -artifactUrl $artifactUrl `
    -Credential $ContainerCredential `
    -auth "UserPassword" `
    -updateHosts `
    -alwaysPull:$true `
    -includeTestToolkit:$includeTestToolkit `
    -includeTestFrameworkOnly:$includeTestFrameworkOnly `
    -includeTestLibrariesOnly:$includeTestLibrariesOnly `
    -licenseFile $SecretSettings.containerLicenseFile `
    -enableTaskScheduler `
    -forceRebuild:$forceRebuild `
    -assignPremiumPlan `
    -isolation hyperv `
    -multitenant:$false `
    -includePerformanceToolkit:$includePerformanceToolkit
    # -myScripts @("https://raw.githubusercontent.com/tfenster/nav-docker-samples/swaggerui/AdditionalSetup.ps1") `
    # -imageName $imageName `

if ($includePerformanceToolkit) {
    #When Performance toolkig, you don't want this:

    write-host "Removing Performance killers" -foregroundcolor green
    UnInstall-BcContainerApp -containerName bccurrent -name "Tests-TestLibraries" -ErrorAction SilentlyContinue
    UnInstall-BcContainerApp -containerName bccurrent -name "Tests-Misc" -ErrorAction SilentlyContinue
}


if ($includePerformanceToolkit) {
    $BcContainerCountry = Get-BcContainerCountry -containerOrImageName $ContainerName
    $BcContainerArtifactUrl = Get-BcContainerArtifactUrl -containerName $ContainerName
    $BcContainerArtifactUrl = $BcContainerArtifactUrl -replace 'https://bcartifacts.azureedge.net/', 'C:/bcartifacts.cache/'
    $BcContainerArtifactUrl = $BcContainerArtifactUrl -replace 'https://bcinsider.azureedge.net/', 'C:/bcartifacts.cache/'
    $BcContainerArtifactUrl = $BcContainerArtifactUrl.Replace($SecretSettings.InsiderSASToken, '')
    $BcContainerArtifactUrl = $BcContainerArtifactUrl -replace $BcContainerCountry, 'platform'
    $PerformanceToolkitSamples = (Get-ChildItem -Recurse -Path $BcContainerArtifactUrl -Filter "*Microsoft_Performance Toolkit Samples.app*").FullName
    
    if ($PerformanceToolkitSamples) {             
        Publish-BcContainerApp `
        -containerName $ContainerName `
        -appFile $PerformanceToolkitSamples `
        -install `
        -sync `
        -syncMode ForceSync `
        -ignoreIfAppExists
    }
}

Invoke-ScriptInBcContainer -containerName $ContainerName -scriptblock {

    Write-Host "Setting SamplingInterval to 1" -foregroundcolor green

    Set-NAVServerConfiguration `
        -ServerInstance "BC" `
        -KeyName  SamplingInterval `
        -KeyValue 1 `
        -ApplyTo All `
        -verbose

    Set-NAVServerInstance -ServerInstance bc -Restart
}


Invoke-ScriptInBcContainer -containerName $containerName -scriptblock {

    param
    (
        $bcpt_appinsights
    )

    # Write-Host "*** Uninstall ANY and Dependencies"
    # Uninstall-NAVApp -ServerInstance BC -Publisher "Microsoft" -Name "Any" -Force:$true -ErrorAction:SilentlyContinue

    # Write-Host "*** Uninstall Test-Upgrade and Dependencies"
    # Uninstall-NAVApp -ServerInstance BC -Publisher "Microsoft" -Name "Tests-Upgrade" -Force:$true -ErrorAction:SilentlyContinue

    # Write-Host "*** Check for remaining Test-Apps"
    # $TestApps = Get-NAVAppInfo -ServerInstance BC -Tenant default -TenantSpecificProperties
    # $TestAppsExists = $TestApps | Where-Object { $_.IsInstalled -and $_.Name.ToUpper().Contains("TEST") -and $_.Name -ne "Test Runner" }
    # if ($null -ne $TestAppsExists){
    #     Write-Host "$($TestAppsExists | Format-List | Out-String)"
    #     Write-Error "*** Test CUs still exist"
    # }

    install-packageprovider -name NuGet -MinimumVersion 2.8.5.201 -Force
    install-module MSAL.PS -force
    Install-Module alops.externaldeployer -force
    import-module ALOps.ExternalDeployer
    Install-ALOpsExternalDeployer

    Set-NAVServerConfiguration -ServerInstance "BC" `
                                -KeyName  EnableLockTimeoutMonitoring  `
                                -KeyValue $true

    Set-NAVServerConfiguration -ServerInstance "BC" `
                                -KeyName  EnableDeadlockMonitoring  `
                                -KeyValue $true
   
    Set-NAVServerConfiguration -ServerInstance "BC" `
                                -KeyName  SqlLongRunningThresholdForApplicationInsights  `
                                -KeyValue 500
   
    Set-NAVServerConfiguration -ServerInstance "BC" `
                                -KeyName  ALLongRunningFunctionTracingThresholdForApplicationInsights  `
                                -KeyValue 10000

    Set-NAVServerConfiguration -ServerInstance "BC" -KeyName "ApplicationInsightsConnectionString" -KeyValue $bcpt_appinsights -ApplyTo All
    
    Set-NAVServerInstance -ServerInstance "BC" -Restart

    # Get-navserverconfiguration -ServerInstance "BC"

} -argumentList $bcpt_appinsights

$EndMs = Get-date
Write-host "This script took $(($EndMs - $StartMs).TotalSeconds) seconds to run"
