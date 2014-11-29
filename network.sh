#!/bin/bash -eux

### Configuration

ETH1=`hostname -I | cut -f2 -d' '`

if [ $ETH1 = 192.168.56.57 ];then
export MY_IP=192.168.56.57
export RABBITMQ_IP=192.168.56.56
export MYSQL_IP=192.168.56.56
export KEYSTONE_IP=192.168.56.56
export GLANCE_IP=192.168.56.56
export NEUTRON_IP=192.168.56.56
export NOVA_IP=192.168.56.56
export CINDER_IP=192.168.56.56
export HORIZON_IP=192.168.56.56
else
export MY_IP=172.16.99.101
export RABBITMQ_IP=172.16.99.100
export MYSQL_IP=172.16.99.100
export KEYSTONE_IP=172.16.99.100
export GLANCE_IP=172.16.99.100
export NEUTRON_IP=172.16.99.100
export NOVA_IP=172.16.99.100
export CINDER_IP=172.16.99.100
export HORIZON_IP=172.16.99.100
fi

export NEUTRON_EXTERNAL_NETWORK_INTERFACE=eth2

### Synchronize time

sudo ntpdate -u ntp.ubuntu.com

### Juno (run these one at a time)

sudo apt-get install -y ubuntu-cloud-keyring software-properties-common
 
sudo add-apt-repository -y cloud-archive:juno

sudo apt-get update

### Neutron

sudo apt-get install -y openvswitch-switch neutron-plugin-openvswitch-agent neutron-dhcp-agent neutron-l3-agent neutron-metadata-agent

sudo service neutron-plugin-openvswitch-agent stop
sudo service neutron-dhcp-agent stop
sudo service neutron-l3-agent stop
sudo service neutron-metadata-agent stop

sudo modprobe vxlan
sudo modprobe openvswitch

sudo service openvswitch-switch restart

cat <<EOF | sudo tee /etc/network/if-up.d/neutron
#!/bin/sh

set -e

ip link set dev $NEUTRON_EXTERNAL_NETWORK_INTERFACE up
EOF
sudo chmod +x /etc/network/if-up.d/neutron
sudo /etc/network/if-up.d/neutron

sudo ovs-vsctl add-br br-ex
sudo ovs-vsctl add-port br-ex $NEUTRON_EXTERNAL_NETWORK_INTERFACE

export SERVICE_TOKEN=ADMIN
export SERVICE_ENDPOINT=http://$KEYSTONE_IP:35357/v2.0

export SERVICE_TENANT_ID=`keystone tenant-get Services | awk '/ id / { print $4 }'`

sudo sed -i "s|connection = sqlite:////var/lib/neutron/neutron.sqlite|connection = mysql://neutron:notneutron@$MYSQL_IP/neutron|g" /etc/neutron/neutron.conf
sudo sed -i "s/#rabbit_host=localhost/rabbit_host=$RABBITMQ_IP/g" /etc/neutron/neutron.conf
sudo sed -i 's/# allow_overlapping_ips = False/allow_overlapping_ips = True/g' /etc/neutron/neutron.conf
sudo sed -i 's/# service_plugins =/service_plugins = router/g' /etc/neutron/neutron.conf
sudo sed -i 's/# auth_strategy = keystone/auth_strategy = keystone/g' /etc/neutron/neutron.conf
sudo sed -i "s/auth_host = 127.0.0.1/auth_host = $KEYSTONE_IP/g" /etc/neutron/neutron.conf
sudo sed -i 's/%SERVICE_TENANT_NAME%/Services/g' /etc/neutron/neutron.conf
sudo sed -i 's/%SERVICE_USER%/neutron/g' /etc/neutron/neutron.conf
sudo sed -i 's/%SERVICE_PASSWORD%/notneutron/g' /etc/neutron/neutron.conf
sudo sed -i "s|# nova_url = http://127.0.0.1:8774\(\/v2\)\?|nova_url = http://$NOVA_IP:8774/v2|g" /etc/neutron/neutron.conf
sudo sed -i "s/# nova_admin_username =/nova_admin_username = nova/g" /etc/neutron/neutron.conf
sudo sed -i "s/# nova_admin_tenant_id =/nova_admin_tenant_id = $SERVICE_TENANT_ID/g" /etc/neutron/neutron.conf
sudo sed -i "s/# nova_admin_password =/nova_admin_password = notnova/g" /etc/neutron/neutron.conf
sudo sed -i "s|# nova_admin_auth_url =|nova_admin_auth_url = http://$KEYSTONE_IP:35357/v2.0|g" /etc/neutron/neutron.conf

# Configure Neutron ML2
sudo sed -i 's|# type_drivers = local,flat,vlan,gre,vxlan|type_drivers = flat,vxlan|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sudo sed -i 's|# tenant_network_types = local|tenant_network_types = flat,vxlan|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sudo sed -i 's|# mechanism_drivers =|mechanism_drivers = openvswitch,l2population|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sudo sed -i 's|# flat_networks =|flat_networks = physnet1|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sudo sed -i 's|# vni_ranges =|vni_ranges = 100:500|g' /etc/neutron/plugins/ml2/ml2_conf.ini
sudo sed -i 's|# enable_security_group = True|firewall_driver = neutron.agent.linux.iptables_firewall.OVSHybridIptablesFirewallDriver\nenable_security_group = True|g' /etc/neutron/plugins/ml2/ml2_conf.ini

# Configure Neutron ML2 continued...
( cat | sudo tee -a /etc/neutron/plugins/ml2/ml2_conf.ini ) <<EOF

[ovs]
local_ip = $MY_IP
tunnel_type = vxlan
enable_tunneling = True
physical_interface_mappings = physnet1:br-ex

[agent]
l2_population = True
tunnel_type = vxlan
physical_interface_mappings = physnet1:br-ex

[vxlan]
enable_vxlan = True
vxlan_group = 224.0.0.1
l2_population = True

[l2pop]
agent_boot_time = 180
EOF

# Configure Neutron DHCP Agent
sudo sed -i 's/# interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver/interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver/g' /etc/neutron/dhcp_agent.ini
sudo sed -i 's/# enable_isolated_metadata = False/enable_isolated_metadata = True/g' /etc/neutron/dhcp_agent.ini
sudo sed -i 's/# enable_metadata_network = False/enable_metadata_network = True/g' /etc/neutron/dhcp_agent.ini

# Configure Neutron L3 Agent
sudo sed -i 's/# interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver/interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver/g' /etc/neutron/l3_agent.ini
sudo sed -i 's/# use_namespaces = True/use_namespaces = True/g' /etc/neutron/l3_agent.ini

# Configure Neutron Metadata Agent
sudo sed -i "s/# nova_metadata_ip = 127.0.0.1/nova_metadata_ip = $MY_IP/g" /etc/neutron/metadata_agent.ini
sudo sed -i 's/# metadata_proxy_shared_secret =/metadata_proxy_shared_secret = openstack/g' /etc/neutron/metadata_agent.ini
sudo sed -i "s|auth_url = http://localhost:5000/v2.0|auth_url = http://$KEYSTONE_IP:5000/v2.0|g" /etc/neutron/metadata_agent.ini
sudo sed -i 's/%SERVICE_TENANT_NAME%/Services/g' /etc/neutron/metadata_agent.ini
sudo sed -i 's/%SERVICE_USER%/neutron/g' /etc/neutron/metadata_agent.ini
sudo sed -i 's/%SERVICE_PASSWORD%/notneutron/g' /etc/neutron/metadata_agent.ini

sudo service neutron-plugin-openvswitch-agent start
sudo service neutron-dhcp-agent start
sudo service neutron-l3-agent start
sudo service neutron-metadata-agent start
