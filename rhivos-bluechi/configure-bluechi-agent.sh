#!/bin/sh

set -e

# Check if /swapfile exists, create one if it doesn't exist
if [ ! -f /swapfile ]; then
        dd if=/dev/zero of=/swapfile count=1024 bs=1MiB
        mkswap /swapfile
        chmod 600 /swapfile
        swapon /swapfile
fi

if [ ! -f /usr/bin/bluechi ]; then
        dnf clean packages
        dnf update --nogpgcheck -y
        dnf install -y epel-release
        dnf install -y \
                bluechi-0.5.0-1.el9iv \
                bluechi-agent-0.5.0-1.el9iv \
                bluechi-selinux-0.5.0-1.el9iv \
                bluechi-ctl-0.5.0-1.el9iv \
                python3-bluechi-0.5.0-1.el9 \
                awscli-1.23.10-3.el9 \
                jq-1.6-16.el9
fi

# Get AWS Region
export AWS_REGION=$(curl --silent http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r .region)

# Get IP Addresses of managed nodes

while [ -z "${MANAGER_IP}" ]; do
  echo "Waiting for Manager IP address..."
  MANAGER_IP=$(aws ec2 describe-instances \
	--filters "Name=tag:Name,Values=AutoSD_Manager" \
	"Name=instance-state-name,Values=running" \
	--query 'Reservations[*].Instances[0].PrivateIpAddress' \
	--output text \
	--region ${AWS_REGION})
  sleep 5
done

# Configure the agent
echo -e "[bluechi-agent]\nManagerHost=${MANAGER_IP}\nManagerPort=2020\n" > /etc/bluechi/agent.conf.d/1.conf

systemctl enable bluechi-agent
systemctl restart  bluechi-agent
