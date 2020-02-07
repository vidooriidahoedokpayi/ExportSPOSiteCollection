Function Create-Folder(){
    param([Parameter(Mandatory=$true)][string]$folder)
     if(-Not (Test-Path $folder)){
        New-Item -Path $folder -ItemType directory;
    }
}
Function Generate-File-Folder(){
    param([Parameter(Mandatory=$true)][string]$fileName)
     $folderName =  $fileName -replace '\s','_';
     $folderName = $folderName -replace  '\.', '-';
     $folderName = $folderName -replace  ',', '';
     return $folderName;
}

Function Generate-Site-Folder(){
    param([Parameter(Mandatory=$true)][string]$url)
     $folderName =  $url -replace 'https://','';
     $folderName = $folderName -replace  '.com', '';
     return Generate-File-Folder -fileName $folderName;
}

Function Combine-URI()
{
param
    (
        [Parameter(Mandatory=$true)] [string] $uri1,
        [Parameter(Mandatory=$true)] [string] $uri2
    )
    $uri1 = $uri1.TrimEnd('/');
    $uri2 = $uri2.TrimStart('/');
    return "$uri1/$uri2";
}

Function Process-Web()
{

    param
    (
        [Parameter(Mandatory=$true)][Microsoft.SharePoint.Client.Web]$web,
        [Parameter(Mandatory=$true)][string]$rootFolder

    )
    $Ctx.Load($web.Lists);
    $Ctx.ExecuteQuery();
    $webFolder = Generate-Site-Folder -url $web.Title;
    $path = [System.IO.Path]::Combine($rootFolder, $webFolder);
    Create-Folder -folder $path;
    foreach($list in $web.Lists){
        $Ctx.Load($list);
        $Ctx.ExecuteQuery();
        $ListTitle = $list.Title;
        $BaseTemplate = $list.BaseTemplate
        Write-Host "Title: $ListTitle, Template: $BaseTemplate"
        if(($list.BaseTemplate -eq 101 ) `
            -and ($list.Title -ne "Site Assets") `
            -and ($list.Title -ne "Style Library")`
            -and ($list.Title -ne "Form Templates"))
        {
            Get-DocumentLibraryFiles -Library $list -RootFolder $path
        }
    }

    $Ctx.Load($web.Webs);
    $Ctx.ExecuteQuery();
    foreach($childWeb in $web.Webs){
        Process-Web -web $childWeb -rootFolder $path
    }
    return $path;
}

#Function to get all files of a folder
Function Get-AllFilesFromFolder()
{
    param(
        [Parameter(Mandatory=$true)][Microsoft.SharePoint.Client.Folder]$Folder,
        [Parameter(Mandatory=$true)][string]$RootFolder
    )
    #Get All Files of the Folder
    $Ctx =  $Folder.Context;
    $Ctx.Load($Folder);
    $Ctx.Load($Folder.files);
    $Ctx.ExecuteQuery();
    $RootFolder = [System.IO.Path]::Combine($RootFolder, $Folder.Name);
  
    #Get all files in Folder
    ForEach ($File in $Folder.files)
    {
        #Get the File Name or do something
        $fileName =$File.Name;
        $folderName =  Generate-File-Folder -fileName $fileName
        Write-Host -f Green $folderName
        $folderName = [System.IO.Path]::Combine([System.IO.Path]::Combine($RootFolder, $folderName));
        Create-Folder -folder $folderName;
        $latestVersionPath = [System.IO.Path]::Combine($folderName, $fileName);
        if(-Not (Test-Path $latestVersionPath))
        {
            Get-PnPFile -Url $File.ServerRelativeUrl -Path $folderName -FileName $fileName -AsFile;
        }
        $versions = $File.Versions;
        $Ctx.load($versions);
        $Ctx.ExecuteQuery();
        foreach($version in $versions){
            $versionUrl = $version.Url;
            $versionFullURL = Combine-URI -uri1 $Ctx.Url -uri2 $versionUrl;
            $targetPath = [System.IO.Path]::Combine($folderName ,$version.VersionLabel);
            Create-Folder -folder $targetPath
            $targetPath = [System.IO.Path]::Combine($targetPath,$fileName);
            if(-Not (Test-Path $targetPath)){            
                $versionStream = $version.OpenBinaryStream();
                $Ctx.Load($version);
                $Ctx.ExecuteQuery();
                $destination = [System.IO.File]::OpenWrite($targetPath);
                $versionStream.Value.CopyTo($destination);
                $destination.Dispose();
                }
        }
    }
          
    #Recursively Call the function to get files of all folders
    $Ctx.Load($Folder.Folders);
    $Ctx.Load($Folder);
    $Ctx.ExecuteQuery();
  
    #Exclude "Forms" system folder and iterate through each folder
    ForEach($SubFolder in $Folder.Folders | Where {$_.Name -ne "Forms"})
    {
        Get-AllFilesFromFolder -Folder $SubFolder -RootFolder $folderRoot;
    }
    
  }
#powershell list all documents in sharepoint online library
Function Get-DocumentLibraryFiles()
{
    param
    (
        [Parameter(Mandatory=$true)] [Microsoft.SharePoint.Client.List] $Library,
        [Parameter(Mandatory=$true)] [string] $RootFolder
    )
    Try {
      
        #Get the Library and Its Root Folder
        $ctx = Get-PnPContext;
        $ctx.Load($Library.RootFolder);
        $ctx.ExecuteQuery();
  
        #Call the function to get Files of the Root Folder
        Get-AllFilesFromFolder -Folder $Library.RootFolder -rootFolder $RootFolder
     }
    Catch {
        write-host -f Red "Error:" $_.Exception.Message
    }
}
#Config Parameters
$SiteCollectionUrl = Read-Host -prompt 'Please enter the target site collection';
Connect-PnPOnline -Url $SiteCollectionUrl -UseWebLogin
$Ctx = get-PnPContext;
$RootWeb = $Ctx.web;
$Ctx.Load($RootWeb);
$Ctx.Load($RootWeb.Webs);
$Ctx.Load($RootWeb.Lists);
$Ctx.ExecuteQuery();
$currentDirectory =Get-Location;
$rootPath = Process-Web -web $RootWeb -rootFolder $currentDirectory;
Disconnect-PnPOnline
