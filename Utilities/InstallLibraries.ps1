Import-Module BitsTransfer

function
Copy-File
{
    [CmdletBinding()]
    param(
        [string]
        $SourcePath,
        
        [string]
        $DestinationPath
    )
    
    if ($SourcePath -eq $DestinationPath)
    {
        return
    }
          
    if (Test-Path $SourcePath)
    {
        Copy-Item -Path $SourcePath -Destination $DestinationPath
    }
    elseif (($SourcePath -as [System.URI]).AbsoluteURI -ne $null)
    {
        if (HasAzCopy -and (IsAzureBlob -Uri $SourcePath)) 
        {
            AzCopy -Source $SourcePath -Dest $DestinationPath
            if ((Test-Path ($DestinationPath) -PathType Leaf)) 
            {
                return
            }
            else
            {
                Remove-Item -Recurse -Force $DestinationPath
                Write-Warning "AzCopy operation failed, please ensure you have AzCopy 7.1.0 or later installed."
            }
        }
        
        if (Test-Nano)
        {
            $handler = New-Object System.Net.Http.HttpClientHandler
            $client = New-Object System.Net.Http.HttpClient($handler)
            $client.Timeout = New-Object System.TimeSpan(0, 30, 0)
            $cancelTokenSource = [System.Threading.CancellationTokenSource]::new() 
            $responseMsg = $client.GetAsync([System.Uri]::new($SourcePath), $cancelTokenSource.Token)
            $responseMsg.Wait()

            if (!$responseMsg.IsCanceled)
            {
                $response = $responseMsg.Result
                if ($response.IsSuccessStatusCode)
                {
                    $downloadedFileStream = [System.IO.FileStream]::new($DestinationPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
                    $copyStreamOp = $response.Content.CopyToAsync($downloadedFileStream)
                    $copyStreamOp.Wait()
                    $downloadedFileStream.Close()
                    if ($copyStreamOp.Exception -ne $null)
                    {
                        throw $copyStreamOp.Exception
                    }      
                }
            }  
        }
        elseif ($PSVersionTable.PSVersion.Major -ge 5)
        {
            #
            # We disable progress display because it kills performance for large downloads (at least on 64-bit PowerShell)
            #
            $ProgressPreference = 'SilentlyContinue'
            wget -Uri $SourcePath -OutFile $DestinationPath -UseBasicParsing
            $ProgressPreference = 'Continue'
        }
        else
        {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($SourcePath, $DestinationPath)
        } 
    }
    else
    {
        throw "Cannot copy from $SourcePath"
    }
}

function 
Test-Nano()
{
    $EditionId = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'EditionID').EditionId

    return (($EditionId -eq "ServerStandardNano") -or 
            ($EditionId -eq "ServerDataCenterNano") -or 
            ($EditionId -eq "NanoServer") -or 
            ($EditionId -eq "ServerTuva"))
}

function Get-ETag {
    param(
        [string]
        $Uri
    )

    # Make HEAD request to get ETag header for blob
    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.Method = "HEAD"
    $request.Timeout = 10000
    $response = $request.GetResponse()
    $etag = $response.Headers["ETag"] 
    $request.Abort()
    return $etag
}

function Compare-Version {
    param(
        [string]
        $Version,

        [string]
        $Path
    )

    $versionPath = $Path + ".version"
    if ((Test-Path ($versionPath)) -eq $false) {
        return $false
    } 
    
    return [System.IO.File]::ReadAllText($versionPath) -eq $ETag
}

function Write-Version {
    param(
        [string]
        $Path,

        [string]
        $Version
    )

    [System.IO.File]::WriteAllText($Path + ".version", $ETag)
}

function HasAzCopy {
    $args = [string[]]@(${Env:ProgramFiles(x86)}, "Microsoft SDKs", "Azure", "AzCopy", "AzCopy.exe")
    return Test-Path ([System.IO.Path]::Combine($args))
}

function AzCopy {
    param(
        [string]
        $Source,

        [string]
        $Dest
    )

    $azCopy = [System.IO.Path]::Combine(${Env:ProgramFiles(x86)}, "Microsoft SDKs", "Azure", "AzCopy", "AzCopy.exe")
    $args = @("/Source:$Source", "/Dest:$Dest", "/Y")
    & $azCopy $args
}

function IsAzureBlob {
    param(
        [string]
        $Uri
    )

    return $Uri -match "blob\.core\.windows\.net"
}