# Load-Balance-RTSP

Solution for load balancing and failover of RTSP Video Provider Service using keepalived.

## About

This configuration will ensure High Availability of RTSP service, where:
- Load balancing between two (more possible) RTSP Video Servers is ensured. If one server fails, the second one now handles all the workload (Active-Active mode).
- Redundancy of Load Balancers is ensured. If one server fails, the second one takes over the workload (Active-Backup mode).

Additionally, network bonding on Load Balancer nodes ensures a more roboust solution in case of network failures.


## Configuration

Before starting, make sure network bonding and VLANs are configured as per your requirements. It is possible, but NOT suggested, to run this configuration without bonding.
The example assumes the following configuration.

**Keepalived server(s):**
- Bonding type 0 (balance, round robin) configured (bond0 interface).

- Configured three (3) tagged VLANs on top of bond inteface
  - management VLAN, bond0.101 (10.10.1.0/24) - MANAGEMENT traffic (Video Server ingest, API calls, etc).
  - rtsp VLAN, bond0.103 (10.10.3.0/24) - RTSP playout requests initiated by Video Consumers (Clients).
  - cluster VLAN, bond0.105 (10.10.5.0/24) - KEEPALIVED cluster communication happens here.

Kernel parameters to change:
```
$ vim /etc/sysctl.conf
net.ipv4.ip_forward = 1
net.ipv4.conf.default.rp_filter = 2
```

Save the changes and restart networking:
```
$ sysctl -p
$ service network restart
```


**RTSP Video servers:**
- eth1 is management, while eth2 is streaming interface
- Configured lo:1 and lo:2 interfaces on both Video Servers with VIP. Ensure RTSP service listens on these interfaces.

In the below case, both rtsp_playout and rtsp_management service listens on VIP defined in lo:1 and lo:2:
```
$ cat /etc/sysconfig/network-scripts/ifcfg-lo:1
DEVICE=lo:1
IPADDR=10.10.1.30
NETMASK=255.255.255.255
ONBOOT=yes
NAME=loopback:1

$ cat /etc/sysconfig/network-scripts/ifcfg-lo:2
DEVICE=lo:2
IPADDR=10.10.3.30
NETMASK=255.255.255.255
ONBOOT=yes
NAME=loopback:2

$ netstat -tulpn |grep -E "rtsp_playout|rtsp_management" |grep -i listen
tcp        0      0 10.10.1.20:8090        0.0.0.0:*                   LISTEN      29962/rtsp_management   
tcp        0      0 10.10.3.20:8090        0.0.0.0:*                   LISTEN      29962/rtsp_management   
tcp        0      0 10.10.1.30:8090        0.0.0.0:*                   LISTEN      29962/rtsp_management   
tcp        0      0 10.10.3.30:8090        0.0.0.0:*                   LISTEN      29962/rtsp_management   
tcp        0      0 127.0.0.1:8090         0.0.0.0:*                   LISTEN      29962/rtsp_management   
tcp        0      0 10.10.1.20:554         0.0.0.0:*                   LISTEN      22971/rtsp_playout      
tcp        0      0 10.10.3.20:554         0.0.0.0:*                   LISTEN      22971/rtsp_playout      
tcp        0      0 127.0.0.1:554          0.0.0.0:*                   LISTEN      22971/rtsp_playout      
tcp        0      0 10.10.3.30:554         0.0.0.0:*                   LISTEN      22971/rtsp_playout      
tcp        0      0 10.10.1.30:554         0.0.0.0:*                   LISTEN      22971/rtsp_playout      
```

If an arp request is received on eth1/eth2, it should respond only if that address is configured on these interfaces - it should not respond if the address is configured on loopback interface(s).
Additionally, when making an ARP request sent through eth0/eth1, it should always use an address that is configured on eth1/eth2 as the source address of the ARP request.

A few kernel parameters need to be set on RTSP servers to achieve this:

```
$ vim /etc/sysctl.conf
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.eth1.arp_ignore = 1
net.ipv4.conf.eth2.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
net.ipv4.conf.eth1.arp_announce = 2
net.ipv4.conf.eth2.arp_announce = 2
```

Save the changes and restart networking:
```
$ sysctl -p
$ service network restart
```

### Communication flow

Example flow, MANAGEMENT communication between Middleware and RTSP Video Server:
![LB_content_management](https://github.com/diarpi/Load-Balance-RTSP/blob/master/LB_content_management.png)

Example flow, RTSP playout requests by Video Consumers (Clients):
![LB_rtsp_playout](https://github.com/diarpi/Load-Balance-RTSP/blob/master/LB_rtsp_playout.png)

In both cases, RTSP Video Servers communicates with Video Consumers / Middleware server directly after establishing a connection, bypassing Load Balancers.

### Installation

Via YUM:
```
$ yum install keepalived
```

Tested keepalived version, on CentOS release 6.4:
```
$ keepalived -v
Keepalived v1.2.13 (03/19,2015)
```


### Keepalived configuration file

Put keepalived.conf to /etc/keepalived. 

Make sure to specify correct VLAN intefaces, VIP addresses, real servers and change the SMTP address.
Consult official keepalived documentation for more info regarding this parameters.


### Keepalived failover

It is a good idea to have a second keepalived server ready, in case of failures.
Configuration stays the same, except for one parameter. Priority value should be HIGHER on the backup keepalived node:
```
vrrp_instance VI_1 {
...
    priority 100
...
```


### Firewall marks

Required for service/protocol grouping. Must be set on keepalived server(s).

Configure Firewall mark 1 (this number must match one in keepalived.conf):
```
$ iptables -A PREROUTING -t mangle -p tcp -d 10.10.3.30 --dport 554 -j MARK --set-mark 1
$ iptables -A PREROUTING -t mangle -p udp -d 10.10.3.30 --dport 6950:7150 -j MARK --set-mark 1
```

Make the rules persistent:
```
$ service iptables save
```


### RTSP check script

Put the RTSP check script (rtsp.sh) into /etc/keepalived folder.
The script will periodically connect to the VOD provider on port 554 and execute "OPTIONS / RTSP/1.0". 
Expected value is "RTSP/1.0 200 OK". If this fails, service is deemed as unavailable and no new playout requests will be directed to this node. 


## Working with keepalived

Starting/Stopping the service:
```
$ service keepalived start
$ service keepalived stop
```

Checking the logs:
```
$ tail -50f /var/log/messages
```

