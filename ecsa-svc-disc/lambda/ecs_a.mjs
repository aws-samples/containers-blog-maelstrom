import * as common from './common.mjs';

import { ECSClient, ListServicesCommand, ListTasksCommand, DescribeTasksCommand, DescribeContainerInstancesCommand, ListTagsForResourceCommand } from "@aws-sdk/client-ecs"; 
import { SSMClient, DescribeInstanceInformationCommand } from "@aws-sdk/client-ssm";

const ecsClient = new ECSClient();
const ssmClient = new SSMClient();

export const getClusterService = async(cluster) => {
    let command = new ListServicesCommand({
        cluster: cluster,
        launchType: "EXTERNAL"
    });
    let response = await ecsClient.send(command);
        
    return {
        "clusterArn": cluster,
        "service": Array.from(response.serviceArns, e => common.getLastElementFromArn(e))
    };
};


export const ecsClusterDetailHandler = async (clusterSvcs) => {

    const clusters = new Array();
    
    for(var clusterSvc of clusterSvcs) {
        const containerInstanceArns = new Array();
        const containerInstanceMap = new Map();
        const ec2InstanceIds = new Array();
        const taskMap = new Map();
        
        if(clusterSvc.service==null || clusterSvc.service.length==0) {
            console.warn(`Skipping ${clusterSvc.clusterArn} as its service is empty`);
            continue;
        }
        
        for(var service of clusterSvc.service) {
                
            let command = new ListTasksCommand({
                cluster: clusterSvc.clusterArn,
                serviceName: service,
                launchType: "EXTERNAL"
            });
            let response = await ecsClient.send(command);
            let taskArns = response.taskArns;
            //console.debug(response);
            
            //console.log(`taskArns=${JSON.stringify(taskArns, null, 2)}`);
            
            command = new DescribeTasksCommand({
                cluster: clusterSvc.clusterArn,
                tasks: taskArns
            });
            response = await ecsClient.send(command);
            // console.debug(response);
            
            const tasks = new Array();
            for(var task of response.tasks) {
                
                containerInstanceArns.push(task.containerInstanceArn);
                task.containers.sort((a,b)=>{
                    if(a.name > b.name) return 1;
                    else if(a.name < b.name) return -1;
                    return 0;
                });
                var hostPorts = new Array(task.containers.length);
                for(var i=0; i<hostPorts.length; i++) {
                    hostPorts[i]=task.containers[i].networkBindings[0].hostPort;
                }

                tasks.push({
                    "taskId": common.getLastElementFromArn(task.taskArn),
                    "containerInstanceId": common.getLastElementFromArn(task.containerInstanceArn),
                    "ec2Instance": null,
                    "desiredStatus": task.desiredStatus,
                    "lastStatus": task.lastStatus,
                    "hostPorts": hostPorts
                });
            }
            taskMap.set(service, tasks);
        }
        
        // console.log(`taskMap=${JSON.stringify(Object.fromEntries(taskMap), null, 2)}`);
        
        let command = new DescribeContainerInstancesCommand({
            cluster: clusterSvc.clusterArn,
            containerInstances: containerInstanceArns
        });
        let response = await ecsClient.send(command);
        // console.debug(response);
        
        for(var containerInstance of response.containerInstances) {
            containerInstanceMap.set(common.getLastElementFromArn(containerInstance.containerInstanceArn), {
                "ec2Instance": containerInstance.ec2InstanceId,
                "status": containerInstance.status,
                "agentConnected": containerInstance.agentConnected,
                "runningTasksCount": containerInstance.runningTasksCount,
                "pendingTasksCount": containerInstance.pendingTasksCount
            });
            
            ec2InstanceIds.push(containerInstance.ec2InstanceId);
        }
        // console.log(`containerInstanceMap=${JSON.stringify(containerInstanceMap, null, 2)}`);
        
        command = new DescribeInstanceInformationCommand({
            InstanceInformationFilterList: [{
                key: "InstanceIds",
                valueSet: ec2InstanceIds
            }]
        });
        response = await ssmClient.send(command);
        // console.debug(response);
            
        for(var iil of response.InstanceInformationList) {
            for(var v of containerInstanceMap.values()) {
                if(v.ec2Instance==iil.InstanceId) {
                    v.ec2Instance={
                        "ec2InstanceId": iil.InstanceId,
                        "computerName": iil.ComputerName,
                        "ipAddress": iil.IPAddress
                    };
                    break;
                }
            }
        }

        // console.log(`containerInstanceMap=${JSON.stringify(Object.fromEntries(containerInstanceMap), null, 2)}`);
        
        for(var s of clusterSvc.service) {
            const tasks = taskMap.get(s);
            
            for(var t of tasks) {
                t.ec2Instance = containerInstanceMap.get(t.containerInstanceId).ec2Instance;   
            }
        }
        
        // console.log(`taskMap=${JSON.stringify(Object.fromEntries(taskMap), null, 2)}`);
        
        const cluster = {
            "clusterArn": clusterSvc.clusterArn,
            "service": Object.fromEntries(taskMap),
            "containerInstance": Object.fromEntries(containerInstanceMap)
        };
        clusters.push(cluster);
    }
    
    return clusters;
};


export const getLbNameForService = async (clusterArn, service) => {
    const serviceArn = clusterArn.replace(":cluster/", ":service/")+"/"+service;
    
    let command = new ListTagsForResourceCommand({
        resourceArn: serviceArn
    });
    let response = await ecsClient.send(command);

    let lbNameTag =response.tags.find(e => e.key=="ecs-a.lbName");
    if(lbNameTag==null) return null;
    
    let lbNameTagValue = lbNameTag.value;
    let lbNames = lbNameTagValue.split(/\s+/).map(e => e.trim());
    
    return lbNames;
};

export const convertToClusterInfo = async (clusterDetail) => {

    return await Promise.all(clusterDetail.map(async(x) => {

        return {
            "clusterArn": x.clusterArn,
            "service": await Promise.all(Object.keys(x.service).map(async(y) => {
                const lbNames = await getLbNameForService(x.clusterArn, y);
                const tasks = new Array();
                
                let cn = 0;
                if(x.service[y].length>0) cn = x.service[y][0].hostPorts.length;
                
                for(let c=0; c<cn; c++) {
                    tasks.push(x.service[y].map(z => {
                        return z.ec2Instance.ipAddress+":"+z.hostPorts[c];
                    }));
                }
                
                return {"name": y,
                    "lbName": lbNames,
                    "tasks": tasks
                };
            }))
        };
    }));
};