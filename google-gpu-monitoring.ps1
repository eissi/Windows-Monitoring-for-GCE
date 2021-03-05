New-Item -Path "c:\" -Name gpu-monitoring-script -ItemType Directory

@'
$metadata_server = "http://metadata/computeMetadata/v1/instance/"
$metadata = Invoke-RestMethod -Uri $metadata_server'zone' -Headers @{'Metadata-Flavor' = 'Google'}
$zone = $metadata.split("/")[3]
$project_id = $metadata.split("/")[1].Tostring()

$instance_id = (Invoke-RestMethod -Uri $metadata_server'id'  -Headers @{'Metadata-Flavor' = 'Google'}).tostring()


#$total_mem = (Get-CimInstance -ClassName Win32_ComputerSystem).totalphysicalmemory

$counters = @(
'\Processor(_total)\% Processor Time',
#'\\localhost\Memory\Available Bytes',
'\\localhost\Memory\Available KBytes'
)


$interval = 5
$access_token_command = 'gcloud auth application-default print-access-token'
$access_token = Invoke-Expression $access_token_command


$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Authorization", "Bearer "+$access_token)
$headers.Add("Content-Type", 'application/json; charset=utf-8')

while(1){

    $values = Get-Counter -Counter $counters -SampleInterval $interval

    #$mem_usage*100

    $data = @{'timeSeries'=@()}
    foreach ($value in $values.CounterSamples){
        $value
        $countername=$value.Path.split('\')[-1] -replace'[\W]',''
        $data.timeSeries +=
            @{'metric'=@{
                'type'="custom.googleapis.com/$countername"
                }
        
            'resource'=@{
                'type'='gce_instance'
                'labels'=@{
                    'project_id'= $project_id
                    'instance_id'=$instance_id
                    'zone'=$zone
                    }
                }
        
            'points' = @(
                    @{
                        'interval'=@{
                            'endTime'=$values.Timestamp.ToString("O")
                            }
                        'value'=@{
                            'doubleValue'=$value.CookedValue
                            }
                    
                    }        
                )
            }
        
      
                
    }

    $body = $data | ConvertTo-Json -Depth 6

    #$body

    $result=Invoke-RestMethod -Method Post -Headers $headers -Uri "https://monitoring.googleapis.com/v3/projects/$project_id/timeSeries" -Body $body

#start-sleep -Seconds $interval
}
'@|out-file c:\gpu-monitoring-script\google-gpu-monitoring.ps1 -Force

$trigger = New-JobTrigger -AtStartup -RandomDelay 00:01:00
Register-ScheduledJob -Trigger $trigger -FilePath c:\gpu-monitoring-script\google-gpu-monitoring.ps1 -Name Google-GPU-monitoring


$os=(get-computerinfo).windowsProductName
if($os -match 'windows server 2016'){
    $url="https://storage.googleapis.com/nvidia-drivers-us-public/GRID/GRID7.1/412.16_grid_win10_server2016_64bit_international.exe"
} else if($os -match 'server 2019'){
    $url="https://storage.googleapis.com/nvidia-drivers-us-public/GRID/GRID8.1/426.04_grid_win10_server2016_server2019_64bit_international.exe"
} else if($os -match '2012r2'){
    $url ="https://storage.googleapis.com/nvidia-drivers-us-public/GRID/GRID7.1/412.16_grid_win8_win7_server2012R2_server2008R2_64bit_international.exe"
}
else{
    new-item -name "DRIVER IS NOT INSTALLED. Please, run"
}

$output = "C:\gpu-monitoring-script\nvidia_driver.exe"
Invoke-WebRequest -Uri $url -OutFile $output