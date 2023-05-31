import * as common from './common.mjs';

import { ElasticLoadBalancingV2Client, DescribeTargetHealthCommand, RegisterTargetsCommand, DeregisterTargetsCommand, DescribeTagsCommand } from "@aws-sdk/client-elastic-load-balancing-v2";

import { BlockList } from "net"

const elbClient = new ElasticLoadBalancingV2Client();

export const getCurrentLoadBalancingInfo = async(lbInfo) => {
    let command = new DescribeTargetHealthCommand({
        "TargetGroupArn": lbInfo.lbName
    });
    let response = await elbClient.send(command);
    
    // console.debug(`DescribeTargetHealthCommandOutput=${JSON.stringify(response, null, 2)}`);
    
    const ipPortInfo = {
        "clusterArn": lbInfo.clusterArn,
        "service": lbInfo.service,
        "container": lbInfo.container,
        "lbName": lbInfo.lbName,
        "hostIpPorts": response.TargetHealthDescriptions.filter(e => e.TargetHealth==null || e.TargetHealth.Reason!="Target.DeregistrationInProgress").map(e => e.Target.Id+":"+e.Target.Port)
    };
    
    //console.debug(`ipPortInfo=${JSON.stringify(ipPortInfo, null, 2)}`);
    
    return ipPortInfo;
}

export const compareLoadBalancingInfo = async(targetLbInfo) => {
    
    const targetIpPortInfo =  targetLbInfo.hostIpPorts.slice();
    const ipPortInfo = (await getCurrentLoadBalancingInfo(targetLbInfo)).hostIpPorts;
    const itemToAdd = new Array();
    const itemToRemove = new Array();
    
    ipPortInfo.forEach(e => {
        if(!targetIpPortInfo.find(e2 => e==e2)) itemToRemove.push(e);
    });

    targetIpPortInfo.forEach(e => {
        if(!ipPortInfo.find(e2 => e==e2)) itemToAdd.push(e);
    });
    
    return {
        "clusterArn": targetLbInfo.clusterArn,
        "service": targetLbInfo.service,
        "container": targetLbInfo.container,
        "lbName": targetLbInfo.lbName,
        "itemToAdd": itemToAdd,
        "itemToRemove": itemToRemove
    };
};

export const applyLoadBalancingInfo = async(changeLbInfo) => {
    
    let vpcCidrCheckList = null;
    let toAdd = changeLbInfo.itemToAdd && changeLbInfo.itemToAdd.length>0;
    let toRemove = changeLbInfo.itemToRemove && changeLbInfo.itemToRemove.length>0;
    
    if(toAdd || toRemove) {
        let command = new DescribeTagsCommand({
          ResourceArns: [
            changeLbInfo.lbName
          ]
        });
        let response = await elbClient.send(command);
        if(response.TagDescriptions && response.TagDescriptions[0] && response.TagDescriptions[0].Tags) {
            let vpcCidrTag = response.TagDescriptions[0].Tags.find(e => e.Key=="ecs-a.lbVpcCidr");

            if(vpcCidrTag && vpcCidrTag.Value && vpcCidrTag.Value.indexOf("/")>0) {
                let vpcCidrArr = vpcCidrTag.Value.split("/");
                vpcCidrCheckList = new BlockList();
                vpcCidrCheckList.addSubnet(vpcCidrArr[0], parseInt(vpcCidrArr[1]), "ipv4");
            }
        }
    }
    
    if(toAdd) {
        let command = new RegisterTargetsCommand({
            "TargetGroupArn": changeLbInfo.lbName,
            "Targets": changeLbInfo.itemToAdd.map(e => {
                const ae = e.split(":");
                let az = "all";
                if(vpcCidrCheckList && vpcCidrCheckList.check(ae[0])) az = null;
                return {
                    Id: ae[0],
                    Port: ae[1],
                    AvailabilityZone: az
                };
            })
        });
        let response = await elbClient.send(command);
        
        //console.debug(`RegisterTargetsCommand=${JSON.stringify(command, null, 2)}`);
    }
    
    if(toRemove) {
        let command = new DeregisterTargetsCommand({
            "TargetGroupArn": changeLbInfo.lbName,
            "Targets": changeLbInfo.itemToRemove.map(e => {
                const ae = e.split(":");
                let az = "all";
                if(vpcCidrCheckList && vpcCidrCheckList.check(ae[0])) az = null;
                return {
                    Id: ae[0],
                    Port: ae[1],
                    AvailabilityZone: az
                };
            })
        });
        let response = await elbClient.send(command);
        
        //console.debug(`DeregisterTargetsCommand=${JSON.stringify(command, null, 2)}`);
    }
    
    return getCurrentLoadBalancingInfo(changeLbInfo);
}
