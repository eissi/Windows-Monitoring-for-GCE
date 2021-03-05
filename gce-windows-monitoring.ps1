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

    #change $true if you want to collect metrics per GPU core
    [switch]$collect_each_core = $false
)

$metadata_server = "http://metadata/computeMetadata/v1/instance/"
$metadata = Invoke-RestMethod -Uri $metadata_server'zone' -Headers @{'Metadata-Flavor' = 'Google'}
$zone = $metadata.split("/")[3]
$project_id = $metadata.split("/")[1].Tostring()

$instance_id = (Invoke-RestMethod -Uri $metadata_server'id'  -Headers @{'Metadata-Flavor' = 'Google'}).tostring()

$counters = @()

$cnt = get-counter -listset "processor"
#$counters += @{counter="$($cnt.PathsWithInstances -match "% Processor Time" -match "(_Total)")"; name="CPU_USAGE_TOTAL"}
$counters += $cnt.PathsWithInstances -match "% Processor Time" -match "(_Total)"

$cnt = get-counter -ListSet "memory"
$counters += $cnt.Paths -match "MBytes"

$cnt = Get-Counter -ListSet "network adapter"
$counters += $cnt.PathsWithInstances -match "\\Packets/sec" -match "Google"
$counters += $cnt.PathsWithInstances -match "Packets received/sec" -match "Google"
$counters += $cnt.PathsWithInstances -match "Packets sent/sec" -match "Google"
$counters += $cnt.PathsWithInstances -match "Bytes" -match "Google"

$cnt = get-counter -listset "logicaldisk"
$counters += $cnt.PathsWithInstances -match "\\disk" -match "total"

$cnt = get-counter -listset "nvidia gpu" -ErrorAction Continue
if ($cnt) {
    $counters += $cnt.PathsWithInstances -match "% gpu"
}



#$cnt = get-counter -ListSet "NVIDIA GPU"  -ErrorAction Stop 
#$counters += $cnt.PathsWithInstances -match 'GPU USAGE'
#$counters += $cnt.PathsWithInstances -match 'GPU MEMORY USAGE'

$access_token_command = 'gcloud auth application-default print-access-token'
#$access_token = Invoke-Expression $access_token_command

$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("Authorization", "Bearer "+$access_token)
$headers.Add("Content-Type", 'application/json; charset=utf-8')


while(1){

    $values = Get-Counter -Counter $counters -SampleInterval $interval 

    #$mem_usage*100

    $data = @{'timeSeries'=@()}

    foreach ($value in $values.CounterSamples){

        $countername=("windows_"+($value.Path.split('\')[-1] -replace'[\W]','_' -replace '__','') + "_"+($value.InstanceName -replace '[\W]','_' )) -replace "_$","" -replace '__',"_"
        #$countername="ncsoft_"+($value.Path.split('\')[-1] -replace'[\W]','_') 
        #$countername+='_core' + $value.InstanceName.substring(1,1) + '_percent'

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
                            'endTime'=$value.Timestamp.ToString("O")
                            }
                        'value'=@{
                            'doubleValue'=$value.CookedValue
                            }                    
                    }        
                )
            }                
    }


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

#start-sleep -Seconds $interval
}