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
        [Parameter(Mandatory=$true)][Microsoft.SharePoint.Client.Web]$web
    )
    $Ctx.Load($web.Lists);
    $Ctx.ExecuteQuery();
    foreach($list in $web.Lists){
        $Ctx.Load($list);
        $Ctx.ExecuteQuery();
        $ListTitle = $list.Title;
        $BaseTemplate = $list.BaseTemplate
        Write-Host "Title: $ListTitle, Template: $BaseTemplate"
        if(($list.BaseTemplate -eq 101 ) -and ($list.Title -ne "Site Assets"))
        {
            Get-DocumentLibraryFiles -Library $list
        }
    }
}

#Function to get all files of a folder
Function Get-AllFilesFromFolder()
{
    param(
        [Parameter(Mandatory=$true)][Microsoft.SharePoint.Client.Folder]$Folder
    )
    #Get All Files of the Folder
    $Ctx =  $Folder.Context;
    $Ctx.load($Folder.files);
    $Ctx.ExecuteQuery();
  
    #Get all files in Folder
    ForEach ($File in $Folder.files)
    {
        #Get the File Name or do something
        $fileName =$File.Name;
        $folderName =  $fileName -replace '\s','_';
        $folderName = $folderName -replace  '\.', '-'
        Write-Host -f Green $folderName
        $absoluteFolderPath = [System.IO.Path]::Combine([System.IO.Path]::Combine($currentDirectory, $folderName));
        if(-Not (Test-Path $absoluteFolderPath)){
            New-Item -Path $folderName -ItemType directory;
            }
        $latestVersionPath = [System.IO.Path]::Combine([System.IO.Path]::Combine($currentDirectory,$folderName), $fileName);
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
            $currentDirectory =Get-Location;
            $targetPath = [System.IO.Path]::Combine($currentDirectory,$folderName);
            $targetPath = [System.IO.Path]::Combine($targetPath,$version.VersionLabel);
            if(-Not (Test-Path $targetPath)){
            New-Item -Path $targetPath -ItemType directory;
            }
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
    $Ctx.load($Folder.Folders)
    $Ctx.ExecuteQuery()
  
    #Exclude "Forms" system folder and iterate through each folder
    ForEach($SubFolder in $Folder.Folders | Where {$_.Name -ne "Forms"})
    {
        Get-AllFilesFromFolder -Folder $SubFolder;
    }
    
  }
#powershell list all documents in sharepoint online library
Function Get-DocumentLibraryFiles()
{
    param
    (
        [Parameter(Mandatory=$true)] [Microsoft.SharePoint.Client.List] $Library
    )
    Try {
      
        #Get the Library and Its Root Folder
        $ctx = Get-PnPContext;
        $ctx.Load($Library.RootFolder);
        $ctx.ExecuteQuery();
  
        #Call the function to get Files of the Root Folder
        Get-AllFilesFromFolder -Folder $Library.RootFolder
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
Process-Web -web $RootWeb;

foreach($web in $RootWeb.Webs){
    Process-Web -web $web    
}
Disconnect-PnPOnline
