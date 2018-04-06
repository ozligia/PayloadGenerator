Param(
    [String[]]$dirPaths=$null,
    [Int]$fileCount=1,
    [String[]]$Files=@(),
    [UInt64]$DataSize=$null,
    [UInt64]$StartOffset=0,
    [UInt64]$EndOffset=$null,
    [UInt64]$BlockSize=(1024*1024),
    [string]$FillPattern,
    [switch]$Overwrite = $false,
    [switch]$Update = $false,
    [switch]$Truncate = $false,
    [switch]$SkipMd5,
    [switch]$Quiet,
    [timespan]$TargetScriptTime = (New-TimeSpan -Days 365)
)

$ErrorActionPreference = "Stop";

function UnitsToBytes{
    Param([string]$Value)
    [uint64]$sizeInBytes = 0;
    $i=0;
    for(; $i -lt $Value.Length; $i++){
        if(![char]::IsDigit($Value[$i])){
            break;
        }
    }
    try{
        $sizeInBytes = [System.Convert]::ToInt64($Value.Substring(0,$i));
    }catch{
        Write-Host "Failed to convert string to number";
        return "N/A";
    }
    $Units = [string]($Value.Substring($i,$Value.Length-$i)).ToLower();
    if($Units.Contains("k")){
        $sizeInBytes = $sizeInBytes * 1024;
    }else{
        if($Units.Contains("m")){
            $sizeInBytes = $sizeInBytes * 1024*1024;
        }else{
            if($Units.Contains("g")){
                $sizeInBytes = $sizeInBytes * 1024*1024*1024;
            }else{
                if($Units.Contains("t")){
                    $sizeInBytes = $sizeInBytes * 1024*1024*1024*1024;
                }else{
                    if($Units.Contains("p")){
                        $sizeInBytes = $sizeInBytes * 1024*1024*1024*1024;
                    }
                }
            }
        }
    }
    return $sizeInBytes;
}

function GetUnits{
    Param([UInt64]$Value)

}

function EnableAutopilot{
    $LogFilePath = "C:\Temp\PayloadGenerator.txt";
    $totalDataSizePerVol = (10*1024*1024*1024);
    $DataSize = (1*1024*1024);
    $FileCount = [math]::Floor($totalDataSizePerVol/($DataSizeMb*1024*1024));
    $defaultDataPath = "\Payload";
    $TargetScriptTime = New-Object -TypeName Timespan (0,10,0);
    $vols = Get-WMIObject -Class Win32_Volume | Select-Object DriveLetter,DriveType,FreeSpace,Capacity,DeviceID,Label;
    $dirPaths = @();
    foreach($vol in $vols){
        if($vol.DriveType -eq 3 -and (-not [string]::IsNullOrEmpty($vol.DriveLetter))){
            try{
                $existingDataSize = (Get-ChildItem -Path "$($vol.DriveLetter)\$defaultDataPath" | Measure-Object -property length -sum).Sum;
            }catch{}
            $minFreeSpace = (10*1024*1024*1024)+$totalDataSizePerVol - $existingDataSize;
            if($vol.FreeSpace -ge $minFreeSpace){
                $dirPaths += "$($vol.DriveLetter)$defaultDataPath";
            }
        }
    }
    if($dirPaths.Count -le 0){
        Write-Host "No sutiable volumes found, exiting..." -ForegroundColor Yellow;
        return;
    }
    Write-Host "Following data paths will be created:" -ForegroundColor Yellow;
    foreach($dirPath in $dirPaths){
        Write-Host $dirPath -ForegroundColor Yellow;
    }
    Write-Host "Current settings:" -ForegroundColor Yellow;
    Write-Host "`t Data size per volume: $($totalDataSizePerVol/(1024*1024))" -ForegroundColor Yellow;
    Write-Host "`t Generation time not greater than: $($TargetScriptTime.ToString())" -ForegroundColor Yellow;
}

function Write-Host{
    Param(
        [parameter(position=0)]$Object,
        [ConsoleColor]$ForegroundColor="White",
        [switch]$NoNewline
    )
    if($LogFilePath -ne $null){
        Write-Log $Object -LogFilePath $LogFilePath;
    }else{
        if(!$Quiet){
            Microsoft.Powershell.Utility\Write-Host -Object $Object -ForegroundColor:$ForegroundColor -NoNewline:$NoNewline;
        }
    }
}

function Write-Log{
    Param(
        [parameter(position=0)]$Object,
        $LogFilePath
    )
    if(-not(Test-Path -Path (Split-Path -Path $LogFilePath))){
        $null = New-Item -Path $LogFilePath -ItemType File -Force;
    }
    Out-File -InputObject "$([DateTime]::Now) $Object" -FilePath $LogFilePath -Append -Encoding ascii;
}

function GenerateFile{
    Param([String]$filePath, $DataSize, $StartOffset, $BlockSize)
    
    try{
        $fstream = New-Object -TypeName System.IO.FileStream($filePath,[System.IO.FileMode]::OpenOrCreate);
        $fwriter = New-Object -TypeName System.IO.BinaryWriter($fstream,[System.Text.Encoding]::ASCII);
    }catch{
        Write-Host "Failed to open file: $filePath, $($_.Exception.Message)" -ForegroundColor Red;
        return;
    }

    if($StartOffset -gt 0){
        $null = $fstream.Seek($StartOffset,[System.IO.SeekOrigin]::Begin);
    }

    Write-Host "Generating file $filePath, requested size $($DataSize) $Units..." -ForegroundColor Yellow;
    #init buffer
    if($DataSize -lt $BlockSize){
        $BlockSize = $DataSize;
        Write-Host "DataSize was less than BlockSize, BlockSize changed accordingly" -ForegroundColor Yellow;
    }
    $buffer = New-Object -TypeName System.Byte[] ($BlockSize);
    
    if($FillPattern){
        $buffer = New-Object -TypeName System.Byte[] ($BlockSize);
        [Byte[]]$fillBytes = [System.Text.Encoding]::Default.GetBytes($FillPattern);
        for($i = 0; $i -lt $buffer.Count; $i++){
            $buffer[$i] = $fillbytes[$i%$fillBytes.Count];
        }
    }

    if($rng -eq $null){
        $rng = New-Object -TypeName System.Random;
    }

    $res = Measure-Command{
        for($index = 0; $index -lt $DataSize; $index += $BlockSize){
            if(-not($FillPattern)){
                $rng.NextBytes($buffer);
            }
            $fwriter.Write($buffer);
        }
        $fwriter.Close();
    }
    Write-Host "Generated $($dataSize) $Units of data to $filePath in $("{0:N2}" -f $res.TotalSeconds) sec." -ForegroundColor Yellow;
    return $true;
}

function UpdateFile{
    Param([String]$filePath, $dataSize, $StartOffset, $BlockSize)
    
    try{
        $file = Get-Item -Path $filePath;
    }catch{
        Write-Host "Cannot find file $filePath" -ForegroundColor Red;
        return;
    }
    Write-Host "Preparing offsets map..." -ForegroundColor Yellow;
    [UInt64[]]$offsets = @() ; $i = 0;
    while($i -lt ($DataSize/$BlockSize)){
        $offsetIndex = [Math]::Floor((Get-Random -Minimum $([UInt64]0) -Maximum $([Math]::Floor($file.Length/$BlockSize))));
        if($offsets -notcontains $offsetIndex*$BlockSize){
            $offsets += $offsetIndex*$BlockSize;
            $i++;
        }
    }
    $offsets = $offsets|Sort-Object;

    Write-Host "Updating file $filePath, requested changes size $($DataSize) $Units..." -ForegroundColor Yellow;

    try{
        $fstream = New-Object -TypeName System.IO.FileStream($filePath,[System.IO.FileMode]::Open);
        $fwriter = New-Object -TypeName System.IO.BinaryWriter($fstream,[System.Text.Encoding]::ASCII);
    }catch{
        Write-Host "Failed to open file: $filePath, $($_.Exception.Message)" -ForegroundColor Red;
        return;
    }

    $randBuffer = New-Object -TypeName System.Byte[] ($BlockSize);

    $res = Measure-Command{
        foreach($offset in $offsets){
            Write-Debug "Index: $index";
            $rng.NextBytes($randBuffer);
            Write-Debug "randBufferLength: $($randBuffer.Count)";
            $fwriter.BaseStream.Seek($offset,[System.IO.SeekOrigin]::Begin);
            $fwriter.Write($randBuffer);
        }
        $fwriter.Close();
    }
    Write-Host "Updated $($DataSize) $Units of data to $filePath in $("{0:N2}" -f $res.TotalSeconds) sec." -ForegroundColor Yellow;
}

function CalcMd5{
    Param([String]$filePath)
    Write-Host "Calculating MD5 for $filePath..." -ForegroundColor Yellow;

    if($md5 -eq $null){
        $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
    }
    $fstream = [System.IO.File]::Open($filePath,[System.IO.FileMode]::Open);
    $res = Measure-Command{
        $hash = [System.BitConverter]::ToString($md5.ComputeHash($fstream));
        $hash = $hash.Replace(“-“,””);
    }
    Write-Host "MD5 for $filePath was calculated in $("{0:N2}" -f $res.TotalSeconds) sec." -ForegroundColor Yellow;
    $fstream.Close();
    return @{"$hash" = "$filePath"};
}

function UpdateMd5File {
    Param(
        [hashtable]$HashRecords
    )
    #Read existing MD5 file.
    try{
        $content = Get-Content -Path "$(Split-Path $filePath)\CHECKSUM.md5";
    }catch{}

    $md5FileContent = New-Object -TypeName System.Collections.ArrayList($HashRecords.Count + $content.Count);
    if($content.Count -eq 1){
        $null = $md5FileContent.Add($content);
    }else{
        foreach($str in $content){
            $null = $md5FileContent.Add($str);
        }
    }
 
    foreach($key in $HashRecords.Keys){
        $relFilePath = ".\$(Split-Path -Path "$($HashRecords[$key])" -Leaf)";
        $newMd5String = "$($key) $relFilePath";
        
        for($index = 0; $index -lt $md5FileContent.Count; $index++){
            if($md5FileContent[$index].Contains("$relFilePath")){
                $md5FileContent.RemoveAt($index);
                break;
            }
        }
        $null = $md5FileContent.Add($($newMd5String));
    }
    Set-Content -Path "$(Split-Path $filePath)\CHECKSUM.md5" -Encoding ascii -Value $md5FileContent -Force;
    Write-Host "MD5 file updated, $($HashRecords.Count) records were added.";
}

#Main
function Main{
    if($dirPaths.Count -le 0 -and $Files.Count -le 0){
        $timeoutSec = 3;
        Write-Host "No locations specified, entering autopilot mode in $timeoutSec seconds..." -ForegroundColor Red;
        While($timeoutSec-- -gt 0){
            Write-Host "Autopilot in $($timeoutSec+1)..." -ForegroundColor Yellow;
            Start-Sleep -Seconds 1;
        }
        . EnableAutopilot;
    }

    if($fileCount -le 0){
        Write-Host "`$FileCount is too smal, should be greater than zero" -ForegroundColor Red;
        return;
    }

    if($Overwrite){
        Write-Host "Currently not supported, default: always overwrite" -ForegroundColor Magenta;
    }
    if($Truncate){
        
        Write-Host "Currently not supported, default: always no truncate" -ForegroundColor Magenta;
    }

    $DataSize = UnitsToBytes -Value $DataSize;
    if($DataSize -le 0){
        Write-Host "DataSize not specified" -ForegroundColor Red;
        return;
    }

    #
    $StartOffset = UnitsToBytes -Value $StartOffset;
    $EndOffset = UnitsToBytes -Value $EndOffset;
    $BlockSize = UnitsToBytes -Value $BlockSize;

    #Create specified path if it doesnot exist
    if(-not($dirPaths.Count -le 0)){
        foreach($dirPath in $dirPaths){
            if(-not(Test-Path -Path $dirPath)){
                Write-Host "Specified path does not exist, creating..." -ForegroundColor Yellow;
                try{
                    $res = New-Item -Path $dirPath -ItemType Directory -Force;
                }catch{
                    Write-Host "Failed to create path: $dirPath, $($_.Exception.Message)" -ForegroundColor Red;
                    return;
                }
            }
        }
    }

    #init global rand generator to speed up script
    $rng = New-Object -TypeName System.Random;
    #init global hash object to speed up script
    $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider

    #If -dirPath specified, preinit files list
    if($Files.Count -le 0){
       $Files = New-Object System.String[]($fileCount);
       for($i = 0; $i -lt $fileCount; $i++){
           $Files[$i] = "$dirPath\$($i+1).tmp";
       }
    }

    #timer to stop script if exceding target script time
    $sw = [Diagnostics.Stopwatch]::StartNew();
    $avLoopExecTime = New-TimeSpan;
    $safetyMargin = New-TimeSpan -Seconds 30;

    $hashRecords = New-Object hashtable($Files.Count); #minor performance issue, set estimated capacity on init
    $res = Measure-Command{
        foreach($filePath in $Files){
            $loopExecTime = Measure-Command{
                if(-not $Update){
                    $res = GenerateFile -filePath $filePath -DataSize $DataSize -StartOffset $StartOffset -BlockSize $BlockSize;
                }else{
                    $res = UpdateFile -filePath $filePath -DataSize $DataSize -StartOffset $StartOffset -BlockSize $BlockSize;
                }
                if($res -eq $true){
                    if(-not $SkipMd5){
                        $hashRecords += CalcMd5 -filePath $filePath;
                    }
                }
            }
            #check if enough time
            if($avLoopExecTime.TotalSeconds -eq 0){
                $avLoopExecTime = $loopExecTime;
            }
            $avLoopExecTime = New-TimeSpan -Seconds ([Math]::Ceiling((($avLoopExecTime.TotalMilliSeconds+$loopExecTime.TotalMilliSeconds)/2/1000)));
            Write-Host "Average time per item: $($avLoopExecTime.TotalSeconds) seconds" -ForegroundColor Yellow;

            if($TargetScriptTime-$sw.Elapsed-$avLoopExecTime-$safetyMargin -lt 0){
                Write-Host "Generation stopped due to target execution time limitation" -ForegroundColor Red;
                break;
            }
            Write-Host "Time left: $(($TargetScriptTime-$sw.Elapsed-$safetyMargin).TotalSeconds) seconds, including safety margin with $($safetyMargin.TotalSeconds) seconds" -ForegroundColor Yellow;
        }
    }
    Write-Output "Main loop: $($res.TotalMilliSeconds) milliseconds";

    UpdateMd5File -HashRecords $hashRecords;

    $sw.Stop();
}

. Main