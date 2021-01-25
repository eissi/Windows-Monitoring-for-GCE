# Copyright 2021 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
 
 
 Param(
    #configure the interval, default is 5 and configure bigger than 5 to avoid throttling
    $interval = 5,

    #cuda is not supported yet
    [switch]$collect_each_core = $false
)

function get_nvidia_smi_utilization{
    param(
        $metric_name
    )
    $path = "C:\Program Files\NVIDIA Corporation\NVSMI\nvidia-smi.exe"

    $result = & $path --query-gpu=$metric_name --format=csv
   
    $final = ($result|?{$_ -match " %"}) -replace " %", ""
   
    ($final|Measure-Object -Average).Average
}

function get_timeseries_entry{
    param(
        $metric_time, 
        $nvidia_metric,
        $gcp_metric_name
        )


   @{'metric'=@{
        'type'="custom.googleapis.com/$gcp_metric_name"
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
                    'endTime'=$metric_time
                    }
                'value'=@{
                    'int64Value'= get_nvidia_smi_utilization -metric_name $nvidia_metric
                    }
                    
            }        
        )
    }

}


$metadata_server = "http://metadata/computeMetadata/v1/instance/"
$metadata = Invoke-RestMethod -Uri $metadata_server'zone' -Headers @{'Metadata-Flavor' = 'Google'}
$zone = $metadata.split("/")[3]
$project_id = $metadata.split("/")[1].Tostring()

$instance_id = (Invoke-RestMethod -Uri $metadata_server'id'  -Headers @{'Metadata-Flavor' = 'Google'}).tostring()



$access_token_command = 'gcloud auth application-default print-access-token'
#$access_token = Invoke-Expression $access_token_command

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Authorization", "Bearer "+$access_token)
$headers.Add("Content-Type", 'application/json; charset=utf-8')


while(1){

    $data = @{'timeSeries'=@()}

    #gpu total
    $now=(get-date).ToString("O")
    $gpu = get_nvidia_smi_utilization -metric_name "utilization.gpu"
    $memory = get_nvidia_smi_utilization -metric_name "utilization.memory"

    $data.timeSeries += get_timeseries_entry -metric_time $now -nvidia_metric "utilization.gpu" -gcp_metric_name "gpu_utilization"
    $data.timeSeries += get_timeseries_entry -metric_time $now -nvidia_metric "utilization.memory" -gcp_metric_name "gpu_memory_utilization"


    $body = $data | ConvertTo-Json -Depth 6

    $body
    try{
        $result=Invoke-RestMethod -Method Post -Headers $headers -Uri "https://monitoring.googleapis.com/v3/projects/$project_id/timeSeries" -Body $body    
    }
    catch{
        #if the token is expired, set it again and send the metrics
        $access_token = Invoke-Expression $access_token_command
        $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
        $headers.Add("Authorization", "Bearer "+$access_token)
        $headers.Add("Content-Type", 'application/json; charset=utf-8') 

        $result=Invoke-RestMethod -Method Post -Headers $headers -Uri "https://monitoring.googleapis.com/v3/projects/$project_id/timeSeries" -Body $body    
    }

    start-sleep -Seconds $interval
} 
