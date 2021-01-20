Param(
    #configure the interval, default is 5 and configure bigger than 5 to avoid throttling
    $interval = 5,

    #change $true if you want to collect metrics per GPU core
    [switch]$collect_each_core = $false
)

$metadata_server = "http://metadata/computeMetadata/v1/instance/"
$metadata = Invoke-RestMethod -Uri $metadata_server'zone' -Headers @{'Metadata-Flavor' = 'Google'}
$zone = $metadata.split("/")[3]
$project_id = $metadata.split("/")[1].Tostring()

$instance_id = (Invoke-RestMethod -Uri $metadata_server'id'  -Headers @{'Metadata-Flavor' = 'Google'}).tostring()

$counters = @()
$cnt = get-counter -ListSet "NVIDIA GPU"  -ErrorAction Stop 
$counters += $cnt.PathsWithInstances -match 'GPU USAGE'
$counters += $cnt.PathsWithInstances -match 'GPU MEMORY USAGE'

$access_token_command = 'gcloud auth application-default print-access-token'
$access_token = Invoke-Expression $access_token_command

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Authorization", "Bearer "+$access_token)
$headers.Add("Content-Type", 'application/json; charset=utf-8')


while(1){

    $values = Get-Counter -Counter $counters -SampleInterval $interval

    #$mem_usage*100

    $data = @{'timeSeries'=@()}
    if ($collect_each_core){
        foreach ($value in $values.CounterSamples){
            $countername=$value.Path.split('\')[-1] -replace'[\W]','' 
            $countername+='_core' + $value.InstanceName.substring(1,1) + '_percent'
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
    }

    #gpu total
    $gpuusage = $values.countersamples|?{$_.path -match "gpu usage"}
    $data.timeSeries +=
        @{'metric'=@{
            'type'="custom.googleapis.com/gpu_utilization"
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
                        'doubleValue'=($gpuusage.Cookedvalue|Measure-Object -Average).Average
                        }
                    
                }        
            )
        }

    #gpu memory total
    $gpuusage = $values.countersamples|?{$_.path -match "memory"}
    $data.timeSeries +=
        @{'metric'=@{
            'type'="custom.googleapis.com/gpu_memory_utilization"
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
                        'doubleValue'=($gpuusage.Cookedvalue|Measure-Object -Average).Average
                        }                    
                }        
            )
        }


    $body = $data | ConvertTo-Json -Depth 6

    $body
    try{
        $result=Invoke-RestMethod -Method Post -Headers $headers -Uri "https://monitoring.googleapis.com/v3/projects/$project_id/timeSeries" -Body $body    
    }
    catch{
        #if the token is expired, set it again and send the metrics
        $access_token_command = 'gcloud auth application-default print-access-token'
        $result=Invoke-RestMethod -Method Post -Headers $headers -Uri "https://monitoring.googleapis.com/v3/projects/$project_id/timeSeries" -Body $body    
    }

#start-sleep -Seconds $interval
}
