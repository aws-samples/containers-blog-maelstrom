
import * as ecs_a from './ecs_a.mjs';
import * as lb from './lb-alb.mjs';


export const handler = async(event) => {
    try {
    
        // console.debug(event);
        const clusterSvcs = new Array();

        // It is NOT a singel event, but batch event from SQS
        if(event.Records!=null) {
            const clusterMap = new Map();
            
            console.log(`event.Records.length=${event.Records.length}`);
            for(var record of event.Records) {
                const body = JSON.parse(record.body);
                
                if(body.detail.group.startsWith("service:")) {
                    if(clusterMap.get(body.detail.clusterArn)==null)
                        clusterMap.set(body.detail.clusterArn, new Set());
                    
                    clusterMap.get(body.detail.clusterArn).add(body.detail.group.replace("service:","") );
                }
            }
            
            for(var k of clusterMap.keys()) {
                clusterSvcs.push({
                    "clusterArn": k,
                    "service": Array.from(clusterMap.get(k))
                });
            }
        }
        // For a scheduled jobs, with only provide the clusterArn
        else if(event.clusterArn!=null) {
            for(var c of event.clusterArn) {
                console.log(`Getting service for ${c}`);
                
                clusterSvcs.push(await ecs_a.getClusterService(c));
            }
        }
        else {
            if(event.detail.group.startsWith("service:")) {
                clusterSvcs.push({
                    "clusterArn": event.detail.clusterArn,
                    "service": [ event.detail.group.replace("service:","") ]
                });
            }
        }
        
        console.log(`clusterSvcs=${JSON.stringify(clusterSvcs, null, 2)}`);

        const ecsClusterDetail = await ecs_a.ecsClusterDetailHandler(clusterSvcs);
                
        console.log(`ecsClusterDetail=${JSON.stringify(ecsClusterDetail, null, 2)}`);
        
        
        
        const ecsClusterInfo = await ecs_a.convertToClusterInfo(ecsClusterDetail);
        
        console.log(`ecsClusterInfo=${JSON.stringify(ecsClusterInfo, null, 2)}`);
        
        var updatedLbInfos = new Array();
        for(let c of ecsClusterInfo) {
            let clusterArn = c.clusterArn;
            
            for(let s of c.service) {
                let service = s.name;
                
                for(let t in s.tasks) {
                    const targetLbInfo = {
                        "clusterArn": clusterArn, "service": service, "container": t, "lbName": s.lbName!=null ? s.lbName[t]:null, "hostIpPorts": s.tasks[t]
                        };
                    
                    console.log(`targetLbInfo=${JSON.stringify(targetLbInfo, null, 2)}`);
                    
                    if(targetLbInfo.lbName!=null) {
                        const changeLbInfo = await lb.compareLoadBalancingInfo(targetLbInfo);
                        console.log(`changeLbInfo=${JSON.stringify(changeLbInfo, null, 2)}`);
                        
                        const updatedLbInfo = await lb.applyLoadBalancingInfo(changeLbInfo);
                        console.log(`updatedLbInfo=${JSON.stringify(updatedLbInfo, null, 2)}`);
                        
                        updatedLbInfos.push(updatedLbInfo);
                    }
                    else console.warn(`lbName is null for ${targetLbInfo.clusterArn} service:${targetLbInfo.service}`);
                }
            }
        }
        
        return {
            "ecsClusterInfo": ecsClusterInfo,
            "updatedLbInfo": updatedLbInfos
        };
    }
    catch(e) {
        console.error(e);
        throw e;
    }
};
