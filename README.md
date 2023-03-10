## k8s的二进制部署
参考地址
```
https://blog.csdn.net/weixin_42072280/article/details/113405732
https://blog.csdn.net/hq_bingo/article/details/125969415
https://blog.csdn.net/qq_46902467/article/details/126660847
https://www.cnblogs.com/fengdejiyixx/p/16576021.html
https://www.likecs.com/ask-679205.html
```

*k8s 环境规划：*
*Pod* *网段：* *20.0.0.0/16*
*Service 网段： 10.255.0.0/16*

## 准备工具
```
[root@m1 ~]# wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
[root@m1 ~]# wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
[root@m1 ~]# wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
[root@m1 ~]# chmod +x cfssl_linux-amd64 cfssljson_linux-amd64 cfssl-certinfo_linux-amd64
[root@m1 ~]# mv cfssl_linux-amd64 /usr/local/bin/cfssl
[root@m1 ~]# mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
[root@m1 ~]# mv cfssl-certinfo_linux-amd64 /usr/local/bin/cfssl-certinfo
```
主机配置：


2.每台机器都安装centos的yum源
```
curl -o /etc/yum.repos.d/CentOS-Base.repo \
https://mirrors.aliyun.com/repo/Centos-7.repo

#工具
yum install -y yum-utils device-mapper-persistent-data lvm2

yum-config-manager --add-repo \
https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
```
3.必备工具安装
``` 
yum install wget jq psmisc vim net-tools telnet \
yum-utils device-mapper-persistent-data lvm2 git -y

```
4.安装ntpdate，用于同步时间
``` 
rpm -ivh http://mirrors.wlnmp.com/centos/wlnmp-release-centos.noarch.rpm
yum install ntpdate -y

```
5.yum升级
``` 
yum update -y --exclude=kernel*
```
6.所有节点安装ipvsadm
```
yum install ipvsadm ipset sysstat conntrack libseccomp -y

```
7.设置kubernetes国内镜像
``` 
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=0
repo_gpgcheck=0
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF


sed -i -e '/mirrors.cloud.aliyuncs.com/d' -e '/mirrors.aliyuncs.com/d' \
/etc/yum.repos.d/CentOS-Base.repo

```
8.关闭所有节点的防火墙、selinux、dnsmasq、swap

```
systemctl disable --now firewalld
#可能关闭失败,因为你压根没有这个服务,那就不用管了
systemctl disable --now dnsmasq
#公有云不要关闭
systemctl disable --now NetworkManager

setenforce 0
sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/sysconfig/selinux
sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config

```

9.关闭swap分区
```
swapoff -a && sysctl -w vm.swappiness=0
sed -ri '/^[^#]*swap/s@^@#@' /etc/fstab

```
10.所有节点同步时间
```` 
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
echo 'Asia/Shanghai' >/etc/timezone
ntpdate time2.aliyun.com
#加入到crontab
crontab -e

*/5 * * * * /usr/sbin/ntpdate time2.aliyun.com

````
11.所有节点配置limit
```` 
ulimit -SHn 65535

vim /etc/security/limits.conf
#末尾添加如下内容
* soft nofile 65536
* hard nofile 131072
* soft nproc 65535
* hard nproc 655350
* soft memlock unlimited
* hard memlock unlimited
````
12.master01节点配置免秘钥登录其他节点
配置完成之后使用ssh工具测试一下
```` 
ssh-keygen -t rsa


for i in k8s-master01 k8s-master02 k8s-master03 k8s-node01 k8s-node02; \
do ssh-copy-id -i .ssh/id_rsa.pub $i;done

````

13.下载安装所有的源码文件
````
 cd /root/
#国内下载
git clone https://gitee.com/dukuan/k8s-ha-install.git
#国外下载就用这个
git clone https://github.com/dotbalo/k8s-ha-install.git
````

三、内核配置
1.在master01节点下载内核
内核尽量升级至4.18+，推荐4.19，生产环境必须要升级
``` 
cd /root
wget http://193.49.22.109/elrepo/kernel/el7/x86_64/RPMS/kernel-ml-devel-4.19.12-1.el7.elrepo.x86_64.rpm
wget http://193.49.22.109/elrepo/kernel/el7/x86_64/RPMS/kernel-ml-4.19.12-1.el7.elrepo.x86_64.rpm
```

2.从master01节点传到其他节点
```
for i in k8s-master02 k8s-master03 k8s-node01 k8s-node02; \
do scp kernel-ml-4.19.12-1.el7.elrepo.x86_64.rpm \
kernel-ml-devel-4.19.12-1.el7.elrepo.x86_64.rpm $i:/root/ ; done

 ```

3.所有节点安装内核
```` 
cd /root
yum localinstall -y kernel-ml*

````
4.所有节点更改内核启动顺序
```` 
grub2-set-default 0 && grub2-mkconfig -o /etc/grub2.cfg
grubby --args="user_namespace.enable=1" --update-kernel="$(grubby --default-kernel)"

````
5.检查默认内核是不是4.19
```` 
[root@k8s-master01 ~]# grubby --default-kernel
/boot/vmlinuz-4.19.12-1.el7.elrepo.x86_64

````
6.所有节点配置ipvs模块
在内核4.19+版本nf_conntrack_ipv4已经改为nf_conntrack，4.18以下使用nf_conntrack_ipv4就可以了
```` 
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack

vim /etc/modules-load.d/ipvs.conf
#加入以下内容
ip_vs
ip_vs_lc
ip_vs_wlc
ip_vs_rr
ip_vs_wrr
ip_vs_lblc
ip_vs_lblcr
ip_vs_dh
ip_vs_sh
ip_vs_fo
ip_vs_nq
ip_vs_sed
ip_vs_ftp
ip_vs_sh
nf_conntrack
ip_tables
ip_set
xt_set
ipt_set
ipt_rpfilter
ipt_REJECT
ipip

````
7.设置开机启动
```
 systemctl enable --now systemd-modules-load.service
```
8.开启k8s集群中必须的内核参数，所有节点都要配置k8s内核
``` 
cat <<EOF > /etc/sysctl.d/k8s.conf
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
fs.may_detach_mounts=1
net.ipv4.conf.all.route_localnet=1
vm.overcommit_memory=1
vm.panic_on_oom=0
fs.inotify.max_user_watches=89100
fs.file-max=52706963
fs.nr_open=52706963
net.netfilter.nf_conntrack_max=2310720

net.ipv4.tcp_keepalive_time=600
net.ipv4.tcp_keepalive_probes=3
net.ipv4.tcp_keepalive_intvl=15
net.ipv4.tcp_max_tw_buckets=36000
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_max_orphans=327680
net.ipv4.tcp_orphan_retries=3
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_max_syn_backlog=16384
net.ipv4.ip_conntrack_max=65536
net.ipv4.tcp_max_syn_backlog=16384
net.ipv4.tcp_timestamps=0
net.core.somaxconn=16384
EOF


sysctl --system

```
9.检查模块有没有被加载进来
```` 
lsmod | grep --color=auto -e ip_vs -e nf_conntrack

#重启所有机器再次检查
reboot
lsmod | grep --color=auto -e ip_vs -e nf_conntrack

````



2.1 准备cfssl证书生成工具
认识kubernetes HTTPS证书。
k8s所有组件均采用https加密通信，这些组件一般有两套根证书生成：k8s组件（apiserver）和Etcd。
假如按角色来分，证书分为管理节点和工作节点。
管理节点：指controller-manager和scheduler连接apiserver所需要的客户端证书。
工作节点：指kubelet和kube-proxy连接apiserver所需要的客户端证书，而一般都会启用Bootstrap TLS机制，所以kubelet的证书初次启动会向apiserver申请颁发证书，由controller-manager组件自动颁发。
```` 
#找任意一台服务器操作，这里用Master节点
[root@k8s-master1 ~]# wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
[root@k8s-master1 ~]# wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
[root@k8s-master1 ~]# wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
[root@k8s-master1 ~]# chmod +x cfssl_linux-amd64 cfssljson_linux-amd64 cfssl-certinfo_linux-amd64
[root@k8s-master1 ~]# mv cfssl_linux-amd64 /usr/local/bin/cfssl
[root@k8s-master1 ~]# mv cfssljson_linux-amd64 /usr/local/bin/cfssljson
[root@k8s-master1 ~]# mv cfssl-certinfo_linux-amd64 /usr/local/bin/cfssl-certinfo
````



#### 生成 Etcd证书
##### （1）自签证书颁发机构（CA）
```
[root@m1 ~]# mkdir -p ~/TLS/{etcd,k8s}
[root@m1 ~]# cd TLS/etcd
```
##### 自签 CA：
```
[root@m1 etcd]# cat > ca-config.json << EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "www": {
         "expiry": "87600h",
         "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ]
      }
    }
  }
}
EOF

[root@m1 etcd]# cat > ca-csr.json<< EOF 
{
    "CN": "etcd CA",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Beijing",
            "ST": "Beijing"
        }
    ]
}
EOF

```
#### 生成证书：
```
[root@m1 etcd]# cfssl gencert -initca ca-csr.json | cfssljson -bare ca -
2021/01/29 12:56:38 [INFO] generating a new CA key and certificate from CSR
2021/01/29 12:56:38 [INFO] generate received request
2021/01/29 12:56:38 [INFO] received CSR
2021/01/29 12:56:38 [INFO] generating key: rsa-2048
2021/01/29 12:56:38 [INFO] encoded CSR
2021/01/29 12:56:38 [INFO] signed certificate with serial number 626998253804116666178693896935885801741945418830

[root@m1 etcd]# ls
ca-config.json  ca.csr  ca-csr.json  ca-key.pem  ca.pem
[root@m1 etcd]# ls *pem
ca-key.pem ca.pem
```

#### 2）使用自签 CA 签发 Etcd HTTPS 证书
##### 创建证书申请文件：
```
cat > server-csr.json << EOF
{
  "CN": "etcd",
  "hosts": [
    "192.168.18.11",      
    "192.168.18.12",
    "192.168.18.13"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "BeiJing",
      "ST": "BeiJing"
    }
  ]
}
EOF
```
注：上述文件 hosts字段中 IP为所有 etcd节点的集群内部通信 IP，一个都不能少！为了方便后期扩容可以多写几个预留的 IP。

##### 生成证书：
```
[root@m1 etcd]# cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=www server-csr.json | cfssljson -bare server
2021/01/29 13:01:14 [INFO] generate received request
2021/01/29 13:01:14 [INFO] received CSR
2021/01/29 13:01:14 [INFO] generating key: rsa-2048
2021/01/29 13:01:14 [INFO] encoded CSR
2021/01/29 13:01:14 [INFO] signed certificate with serial number 352987269900645375778410919481069285400609343984
2021/01/29 13:01:14 [WARNING] This certificate lacks a "hosts" field. This makes it unsuitable for
websites. For more information see the Baseline Requirements for the Issuance and Management
of Publicly-Trusted Certificates, v.1.1.6, from the CA/Browser Forum (https://cabforum.org);
specifically, section 10.2.3 ("Information Requirements").
[root@m1 etcd]# 

[root@m1 etcd]# ls
ca-config.json  ca.csr  ca-csr.json  ca-key.pem  ca.pem  server.csr  server-csr.json  server-key.pem  server.pem
[root@m1 etcd]# 
[root@m1 etcd]# ls server*pem
server-key.pem  server.pem
[root@m1 etcd]# 

```
### 4.3 部署 Etcd集群
以下在节点 1 上操作，为简化操作，待会将节点 1 生成的所有文件拷贝到节点 2和节点 3.

#####（1）创建工作目录并下载二进制包
下载地址：https://github.com/etcd-io/etcd/releases/download/v3.4.9/etcd-v3.4.9-linux-amd64.tar.gz
````
[root@m1 etcd]# cd ~
[root@m1 ~]# wget https://github.com/etcd-io/etcd/releases/download/v3.4.9/etcd-v3.4.9-linux-amd64.tar.gz
````
````
[root@m1 ~]# mkdir /opt/etcd/{bin,cfg,ssl} -p    #bin里面存放的是可执行文件,cfg配置文件,ssl证书
[root@m1 ~]# tar zxvf etcd-v3.4.9-linux-amd64.tar.gz
[root@m1 ~]# mv etcd-v3.4.9-linux-amd64/{etcd,etcdctl} /opt/etcd/bin/

````
#### （2）创建 etcd配置文件
````
[root@m1 ~]# cat > /opt/etcd/cfg/etcd.conf << EOF
#[Member]
ETCD_NAME="etcd-1"
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="https://192.168.18.11:2380" 
ETCD_LISTEN_CLIENT_URLS="https://192.168.18.11:2379" 
#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://192.168.18.11:2380"
ETCD_ADVERTISE_CLIENT_URLS="https://192.168.18.11:2379"
ETCD_INITIAL_CLUSTER="etcd-1=https://192.168.18.11:2380,etcd-2=https://192.168.18.12:2380,etcd-3=https://192.168.18.13:2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster" 
ETCD_INITIAL_CLUSTER_STATE="new"
EOF

````
ETCD_NAME：节点名称，集群中唯一
ETCD_DATA_DIR：数据目录
ETCD_LISTEN_PEER_URLS：集群通信监听地址
ETCD_LISTEN_CLIENT_URLS：客户端访问监听地址
ETCD_INITIAL_ADVERTISE_PEER_URLS：集群通告地址
ETCD_ADVERTISE_CLIENT_URLS：客户端通告地址

ETCD_INITIAL_CLUSTER：集群节点地址
ETCD_INITIAL_CLUSTER_TOKEN：集群 Token
ETCD_INITIAL_CLUSTER_STATE：加入集群的当前状态，new是新集群，existing表示加入已有集群

#### （3）systemd管理 etcd
```
[root@m1 ~]# cat > /usr/lib/systemd/system/etcd.service << EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
[Service]
Type=notify
EnvironmentFile=/opt/etcd/cfg/etcd.conf
ExecStart=/opt/etcd/bin/etcd \
    --cert-file=/opt/etcd/ssl/server.pem \
    --key-file=/opt/etcd/ssl/server-key.pem \
    --peer-cert-file=/opt/etcd/ssl/server.pem \
    --peer-key-file=/opt/etcd/ssl/server-key.pem \
    --trusted-ca-file=/opt/etcd/ssl/ca.pem \
    --peer-trusted-ca-file=/opt/etcd/ssl/ca.pem \
    --logger=zap
Restart=on-failure
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF

```
### 4）拷贝刚才生成的证书
把刚才生成的证书拷贝到配置文件中的路径：
````
 [root@m1 ~]# cp ~/TLS/etcd/ca*pem ~/TLS/etcd/server*pem /opt/etcd/ssl/
````
#### 5）将上面节点 1 所有生成的文件拷贝到节点 2 和节点 3
````
for i in k8s-master2 k8s-master3; do scp -r /opt/etcd/ $i:/opt/etcd/; done
for i in k8s-master2 k8s-master3; do scp /usr/lib/systemd/system/etcd.service $i:/usr/lib/systemd/system/etcd.service; done
````
#### 然后在节点 2 和节点 3 分别修改 etcd.conf 配置文件中的节点名称和当前服务器 IP：
```
vim /opt/etcd/cfg/etcd.conf
#[Member]
ETCD_NAME="etcd-2" # 修改此处，节点 2 改为 etcd-2，节点 3改为 etcd-3
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="https://192.168.18.12:2380" # 修改此处为当前服务器 IP ETCD_LISTEN_CLIENT_URLS="https://192.168.31.71:2379" # 修改此处为当前服务器 IP
#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://192.168.18.12:2380" # 修改此处为当前服务器 IP
ETCD_ADVERTISE_CLIENT_URLS="https://192.168.18.12:2379" # 修改此处为当前服务器IP
ETCD_INITIAL_CLUSTER="etcd-1=https://192.168.18.11:2380,etcd-2=https://192.168.18.12:2380,etcd-3=https://192.168.18.13:2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_INITIAL_CLUSTER_STATE="new"



vim /opt/etcd/cfg/etcd.conf
#[Member]
ETCD_NAME="etcd-3" # 修改此处，节点 2 改为 etcd-2，节点 3改为 etcd-3
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="https://192.168.18.13:2380" # 修改此处为当前服务器 IP ETCD_LISTEN_CLIENT_URLS="https://192.168.31.71:2379" # 修改此处为当前服务器 IP
#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://192.168.18.13:2380" # 修改此处为当前服务器 IP
ETCD_ADVERTISE_CLIENT_URLS="https://192.168.18.13:2379" # 修改此处为当前服务器IP
ETCD_INITIAL_CLUSTER="etcd-1=https://192.168.18.11:2380,etcd-2=https://192.168.18.12:2380,etcd-3=https://192.168.18.13:2380"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_INITIAL_CLUSTER_STATE="new"

```
#### etcd 开启开机自启
```
systemctl daemon-reload 
systemctl start etcd 
systemctl enable etcd
systemctl status etcd 
```

### （7）查看集群状态
```` 
ETCDCTL_API=3 /opt/etcd/bin/etcdctl --cacert=/opt/etcd/ssl/ca.pem --cert=/opt/etcd/ssl/server.pem --key=/opt/etcd/ssl/server-key.pem --endpoints="https://192.168.18.11:2379,https://192.168.18.12:2379,https://192.168.18.13:2379" endpoint health 


ETCDCTL_API=3 /opt/etcd/bin/etcdctl --cacert=/opt/etcd/ssl/ca.pem --cert=/opt/etcd/ssl/server.pem --key=/opt/etcd/ssl/server-key.pem --endpoints="https://192.168.18.11:2379,https://192.168.18.12:2379,https://192.168.18.13:2379" endpoint health --write-out=table
````

### 三、安装Docker
这里使用Docker作为容器引擎，也可以换成别的，例如containerd

下载地址：https://download.docker.com/linux/static/stable/x86_64/docker-19.03.9.tgz

以下在所有节点操作。这里采用二进制安装，用yum安装也一样。

#### 1.解压二进制包
[root@k8s-master1 ~]# tar zxvf docker-19.03.9.tgz
[root@k8s-master1 ~]# mv docker/* /usr/bin

#### 2.systemd管理docker
````
[root@k8s-master1 ~]# cat > /usr/lib/systemd/system/docker.service << EOF
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
ExecStart=/usr/bin/dockerd
ExecReload=/bin/kill -s HUP $MAINPID
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TimeoutStartSec=0
Delegate=yes
KillMode=process
Restart=on-failure
StartLimitBurst=3
StartLimitInterval=60s

[Install]
WantedBy=multi-user.target
EOF

````
### 3.创建配置文件
#### registry-mirrors 阿里云镜像加速器
````
[root@k8s-master1 ~]# mkdir /etc/docker
[root@k8s-master1 ~]# cat > /etc/docker/daemon.json << EOF
{
"registry-mirrors": ["https://b9pmyelo.mirror.aliyuncs.com"]
}
EOF
````
#### 4.启动并设置开机启动
```` 
systemctl daemon-reload
systemctl start docker
systemctl enable docker
````

#### 四、部署MasterNode
## 4.1 生成kube-apiserver证书
### 4.1.1 自签证书颁发机构（CA）
```
[root@k8s-master1 ~]# cd ~/TLS/k8s
[root@k8s-master1 k8s]# cat > ca-config.json << EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
         "expiry": "87600h",
         "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ]
      }
    }
  }
}
EOF
 
[root@k8s-master1 k8s]# cat > ca-csr.json << EOF
{
    "CN": "kubernetes",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Beijing",
            "ST": "Beijing",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
EOF
 
2.生成证书：
[root@k8s-master1 k8s]# cfssl gencert -initca ca-csr.json | cfssljson -bare ca -
#会生成ca.pem和ca-key.pem文件。
```

#### 4.1.2 使用自签CA签发Kube-apiserverHTTPS证书

````
1 #创建证书申请文件：
[root@k8s-master1 k8s]# cat > server-csr.json << EOF                                                                                                 
{
    "CN": "kubernetes",
    "hosts": [
      "127.0.0.1",
      "10.255.0.1",
      "192.168.18.11",
      "192.168.18.11",
      "192.168.18.11",
      "kubernetes",
      "kubernetes.default",
      "kubernetes.default.svc",
      "kubernetes.default.svc.cluster",
      "kubernetes.default.svc.cluster.local"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "BeiJing",
            "ST": "BeiJing",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
EOF
#注：上述文件hosts字段中IP为所有Master/LB/VIPIP，一个都不能少！为了方便后期扩容可以多写几个预留的IP。
 
2.生成证书：
[root@k8s-master1 k8s]# cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes server-csr.json | cfssljson -bare server
#会生成server.pem和server-key.pem文件。
````

## 4.2 从Github下载二进制文件
```
下载地址： 浏览器访问，下载Server Binaries下kubernetes-server-linux-amd64.tar.gz包即可
https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.20.md
具体下载地址：wget https://dl.k8s.io/v1.20.9/kubernetes-server-linux-amd64.tar.gz
```
## 4.3 解压二进制包
```
[root@k8s-master1 ~]# mkdir -p /opt/kubernetes/{bin,cfg,ssl,logs}
[root@k8s-master1 ~]# tar zxvf kubernetes-server-linux-amd64.tar.gz
[root@k8s-master1 ~]# cd kubernetes/server/bin
[root@k8s-master1 bin]# cp kube-apiserver kube-scheduler kube-controller-manager /opt/kubernetes/bin
[root@k8s-master1 bin]# cp kubectl /usr/bin/
```
## 4.4 部署kube-apiserver
```
1. #创建配置文件
[root@k8s-master1 ~]# cat > /opt/kubernetes/cfg/kube-apiserver.conf << EOF
KUBE_APISERVER_OPTS="--logtostderr=false \\
--v=2 \\
--log-dir=/opt/kubernetes/logs \\
--etcd-servers=https://192.168.18.11:2379,https://192.168.18.12:2379,https://192.168.18.13:2379  \\
--bind-address=192.168.18.11  \\
--secure-port=6443  \\
--advertise-address=192.168.18.11  \\
--allow-privileged=true  \\
--service-cluster-ip-range=10.255.0.0/16  \\
--enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota,NodeRestriction  \\
--authorization-mode=RBAC,Node  \\
--enable-bootstrap-token-auth=true  \\
--token-auth-file=/opt/kubernetes/cfg/token.csv  \\
--service-node-port-range=30000-32767  \\
--kubelet-client-certificate=/opt/kubernetes/ssl/server.pem  \\
--kubelet-client-key=/opt/kubernetes/ssl/server-key.pem  \\
--tls-cert-file=/opt/kubernetes/ssl/server.pem   \\
--tls-private-key-file=/opt/kubernetes/ssl/server-key.pem  \\
--client-ca-file=/opt/kubernetes/ssl/ca.pem  \\
--service-account-key-file=/opt/kubernetes/ssl/ca-key.pem  \\
--service-account-issuer=api  \\
--service-account-signing-key-file=/opt/kubernetes/ssl/server-key.pem \\
--etcd-cafile=/opt/etcd/ssl/ca.pem  \\
--etcd-certfile=/opt/etcd/ssl/server.pem  \\
--etcd-keyfile=/opt/etcd/ssl/server-key.pem  \\
--requestheader-client-ca-file=/opt/kubernetes/ssl/ca.pem \\
--proxy-client-cert-file=/opt/kubernetes/ssl/server.pem  \\
--proxy-client-key-file=/opt/kubernetes/ssl/server-key.pem \\
--requestheader-allowed-names=kubernetes \\
--requestheader-extra-headers-prefix=X-Remote-Extra-  \\
--requestheader-group-headers=X-Remote-Group \\
--requestheader-username-headers=X-Remote-User  \\
--enable-aggregator-routing=true  \\
--audit-log-maxage=30  \\
--audit-log-maxbackup=3  \\
--audit-log-maxsize=100  \\
--audit-log-path=/opt/kubernetes/logs/k8s-audit.log"
EOF
 
#注：上面两个\ \ 第一个是转义符，第二个是换行符，使用转义符是为了使用EOF保留换行符。
#配置文件详解
--logtostderr：启用日志
---v：日志等级
--log-dir：日志目录
--etcd-servers：etcd集群地址
--bind-address：监听地址
--secure-port：https安全端口
--advertise-address：集群通告地址
--allow-privileged：启用授权
--service-cluster-ip-range：Service虚拟IP地址段
--enable-admission-plugins：准入控制模块
--authorization-mode：认证授权，启用RBAC授权和节点自管理
--enable-bootstrap-token-auth：启用TLS
--token-auth-file：bootstrap：bootstrap机制、token文件
--service-node-port-range：Service nodeport类型默认分配端口范围
--kubelet-client-xxx：apiserver访问kubelet客户端证书
--tls-xxx-file：apiserverhttps证书
1.20版本必须加的参数：--service-account-issuer，--service-account-signing-key-file
--etcd-xxxfile：连接Etcd集群证书ee
--audit-log-xxx：审计日志
启动聚合层相关配置：--requestheader-client-ca-file，--proxy-client-cert-file，--proxy-client-key-file，--requestheader-allowed-names，--requestheader-extra-headers-prefix，--requestheader-group-headers，--requestheader-username-headers，--enable-aggregator-routing
 
2.拷贝刚才生成的证书
#把刚才生成的证书拷贝到配置文件中的路径：
[root@k8s-master1 ~]# cp ~/TLS/k8s/ca*pem ~/TLS/k8s/server*pem /opt/kubernetes/ssl/
```
4.4.1 启动TLS Bootstrapping 机制
````
TLS Bootstraping： Master apiserver启用TLS认证后，Node节点kubelet和kube-proxy要与kube-apiserver进行通信，
必须使用CA签发的有效证书才可以，当Node节点很多时，这种客户端证书颁发需要大量工作，同样也会增加集群扩展复杂度。
为了简化流程，Kubernetes引入了TLS bootstraping机制来自动颁发客户端证书，
kublet会以一个低权限用户自动向apiserver申请证书，
kubelet的证书由apiserver动态签署。所以强烈建议在Node上使用这种方式，
目前主要用与kubelet。kube-proxy还是由我们统一颁发一个证书。
````

``` 
1.#创建上述配置文件中token文件：
[root@k8s-master1 ~]# cat > /opt/kubernetes/cfg/token.csv << EOF
c47ffb939f5ca36231d9e3121a252940,kubelet-bootstrap,10001,"system:node-bootstrapper"
EOF
 
格式：token，用户名，UID，用户组
token也可自行生成替换：
head -c 16 /dev/urandom | od -An -t x | tr -d ' '
```

4.4.2 systemd管理apiserver
``` 
1.systemd管理apiserver
[root@k8s-master1 ~]# cat > /usr/lib/systemd/system/kube-apiserver.service << EOF
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
 
[Service]
EnvironmentFile=/opt/kubernetes/cfg/kube-apiserver.conf
ExecStart=/opt/kubernetes/bin/kube-apiserver \$KUBE_APISERVER_OPTS
Restart=on-failure
 
[Install]
WantedBy=multi-user.target
EOF		
#转义符\是为了使用EOF
```
```
2.启动并设置开机启动
 systemctl daemon-reload
 systemctl start kube-apiserver
 systemctl enable kube-apiserver
 systemctl status kube-apiserver
```
## 4.5 部署kube-controller-manager
````
1.创建配置文件
[root@k8s-master1 ~]#  cat > /opt/kubernetes/cfg/kube-controller-manager.conf << EOF
KUBE_CONTROLLER_MANAGER_OPTS="--logtostderr=false \\
--v=2 \\
--log-dir=/opt/kubernetes/logs \\
--leader-elect=true \\
--kubeconfig=/opt/kubernetes/cfg/kube-controller-manager.kubeconfig \\
--bind-address=127.0.0.1 \\
--allocate-node-cidrs=true \\
--cluster-cidr=20.0.0.0/16 \\
--service-cluster-ip-range=10.255.0.0/16 \\
--cluster-signing-cert-file=/opt/kubernetes/ssl/ca.pem \\
--cluster-signing-key-file=/opt/kubernetes/ssl/ca-key.pem  \\
--root-ca-file=/opt/kubernetes/ssl/ca.pem \\
--service-account-private-key-file=/opt/kubernetes/ssl/ca-key.pem \\
--cluster-signing-duration=87600h0m0s"
EOF
#配置文件详解
--kubeconfig：连接apiserver配置文件
--leader-elect：当该组件启动多个时，自动选举（HA）
--cluster-signing-cert-file/--cluster-signing-key-file：自动为kubelet颁发证书的CA，与apiserver保持一致。
 
2.生成kubeconfig文件
#生成kube-controller-manager证书：
 
#切换工作目录
[root@k8s-master1 ~]# cd ~/TLS/k8s
 
#创建证书请求文件
[root@k8s-master1 k8s]# cat > kube-controller-manager-csr.json << EOF
{
  "CN": "system:kube-controller-manager",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "BeiJing", 
      "ST": "BeiJing",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF
 
3.生成证书
[root@k8s-master1 k8s]# cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-controller-manager-csr.json | cfssljson -bare kube-controller-manager
 
4.生成kubeconfig文件（以下是shell命令，直接在终端执行）：
[root@k8s-master1 k8s]# KUBE_CONFIG="/opt/kubernetes/cfg/kube-controller-manager.kubeconfig"
[root@k8s-master1 k8s]# KUBE_APISERVER="https://192.168.18.11:6443"
 
[root@k8s-master1 k8s]# kubectl config set-cluster kubernetes \
--certificate-authority=/opt/kubernetes/ssl/ca.pem \
--embed-certs=true \
--server=${KUBE_APISERVER} \
--kubeconfig=${KUBE_CONFIG}
 
[root@k8s-master1 k8s]# kubectl config set-credentials kube-controller-manager \
--client-certificate=./kube-controller-manager.pem \
--client-key=./kube-controller-manager-key.pem \
--embed-certs=true \
--kubeconfig=${KUBE_CONFIG}
 
[root@k8s-master1 k8s]# kubectl config set-context default \
--cluster=kubernetes \
--user=kube-controller-manager \
--kubeconfig=${KUBE_CONFIG}
 
[root@k8s-master1 k8s]# kubectl config use-context default --kubeconfig=${KUBE_CONFIG}
 
5.systemd管理controller-manager
[root@k8s-master1 k8s]# cat > /usr/lib/systemd/system/kube-controller-manager.service << EOF
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes
 
[Service]
EnvironmentFile=/opt/kubernetes/cfg/kube-controller-manager.conf
ExecStart=/opt/kubernetes/bin/kube-controller-manager \$KUBE_CONTROLLER_MANAGER_OPTS
Restart=on-failure
 
[Install]
WantedBy=multi-user.target
EOF
 
6.启动并设置开机启动
[root@k8s-master1 k8s]# systemctl daemon-reload
[root@k8s-master1 k8s]# systemctl start kube-controller-manager
[root@k8s-master1 k8s]# systemctl enable kube-controller-manager
[root@k8s-master1 k8s]# systemctl status kube-controller-manager
````
## 4.6 部署kube-scheduler
````
1.创建配置文件
[root@k8s-master1 ~]# cat > /opt/kubernetes/cfg/kube-scheduler.conf << EOF
KUBE_SCHEDULER_OPTS="--logtostderr=false \\
--v=2 \\
--log-dir=/opt/kubernetes/logs \\
--leader-elect \\
--kubeconfig=/opt/kubernetes/cfg/kube-scheduler.kubeconfig \\
--bind-address=127.0.0.1"
EOF
 
#配置文件详解
--kubeconfig：连接apiserver配置文件
--leader-elect：当该组件启动多个时，自动选举（HA）
 
2.生成kubeconfig文件
#切换工作目录
[root@k8s-master1 ~]# cd ~/TLS/k8s
 
#创建证书请求文件
[root@k8s-master1 k8s]# cat > kube-scheduler-csr.json << EOF
{
  "CN": "system:kube-scheduler",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "BeiJing",
      "ST": "BeiJing",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF
 
3.生成证书
[root@k8s-master1 k8s]# cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-scheduler-csr.json | cfssljson -bare kube-scheduler
 
4.生成kubeconfig文件（以下是shell命令，直接在终端执行）：
[root@k8s-master1 k8s]# KUBE_CONFIG="/opt/kubernetes/cfg/kube-scheduler.kubeconfig"
[root@k8s-master1 k8s]# KUBE_APISERVER="https://192.168.18.11:6443"
 
[root@k8s-master1 k8s]# kubectl config set-cluster kubernetes \
--certificate-authority=/opt/kubernetes/ssl/ca.pem \
--embed-certs=true \
--server=${KUBE_APISERVER} \
--kubeconfig=${KUBE_CONFIG}
 
[root@k8s-master1 k8s]# kubectl config set-credentials kube-scheduler \
--client-certificate=./kube-scheduler.pem \
--client-key=./kube-scheduler-key.pem \
--embed-certs=true \
--kubeconfig=${KUBE_CONFIG}
 
[root@k8s-master1 k8s]# kubectl config set-context default \
--cluster=kubernetes \
--user=kube-scheduler \
--kubeconfig=${KUBE_CONFIG}
 
[root@k8s-master1 k8s]# kubectl config use-context default --kubeconfig=${KUBE_CONFIG}
 
5.systemd管理scheduler
[root@k8s-master1 k8s]# cat > /usr/lib/systemd/system/kube-scheduler.service << EOF
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes
 
[Service]
EnvironmentFile=/opt/kubernetes/cfg/kube-scheduler.conf
ExecStart=/opt/kubernetes/bin/kube-scheduler \$KUBE_SCHEDULER_OPTS
Restart=on-failure
 
[Install]
WantedBy=multi-user.target
EOF
 
6.启动并设置开机启动
[root@k8s-master1 k8s]# systemctl daemon-reload
[root@k8s-master1 k8s]# systemctl start kube-scheduler
[root@k8s-master1 k8s]# systemctl enable kube-scheduler
[root@k8s-master1 k8s]# systemctl status kube-scheduler
 
7.查看集群状态
生成kubectl连接集群的证书：（kubectl连接apiserver 需要证书及kubeconfig文件）
#切换工作目录
[root@k8s-master1 k8s]# cd ~/TLS/k8s
[root@k8s-master1 k8s]# cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "BeiJing",
      "ST": "BeiJing",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF
 
#生成证书
[root@k8s-master1 k8s]# cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare admin
 
#生成kubeconfig文件：
[root@k8s-master1 k8s]# mkdir /root/.kube
[root@k8s-master1 k8s]# KUBE_CONFIG="/root/.kube/config"
[root@k8s-master1 k8s]# KUBE_APISERVER="https://192.168.18.11:6443"
 
[root@k8s-master1 k8s]# kubectl config set-cluster kubernetes \
--certificate-authority=/opt/kubernetes/ssl/ca.pem \
--embed-certs=true \
--server=${KUBE_APISERVER} \
--kubeconfig=${KUBE_CONFIG}
 
[root@k8s-master1 k8s]# kubectl config set-credentials cluster-admin \
--client-certificate=./admin.pem \
--client-key=./admin-key.pem \
--embed-certs=true \
--kubeconfig=${KUBE_CONFIG}
 
[root@k8s-master1 k8s]# kubectl config set-context default \
--cluster=kubernetes \
--user=cluster-admin \
--kubeconfig=${KUBE_CONFIG}
 
[root@k8s-master1 k8s]# kubectl config use-context default --kubeconfig=${KUBE_CONFIG}
 
#通过kubectl工具查看当前集群组件状态：
[root@k8s-master1 k8s]# kubectl get cs
Warning: v1 ComponentStatus is deprecated in v1.19+
NAME                 STATUS    MESSAGE             ERROR
scheduler            Healthy   ok                  
controller-manager   Healthy   ok                  
etcd-0               Healthy   {"health":"true"}   
etcd-1               Healthy   {"health":"true"}   
etcd-2               Healthy   {"health":"true"} 
#如上输出说明Master节点组件运行正常。
 
8.授权kubelet-bootstrap用户允许请求证书
[root@k8s-master1 k8s]# kubectl create clusterrolebinding kubelet-bootstrap \
--clusterrole=system:node-bootstrapper \
--user=kubelet-bootstrap
````

## 五、部署 Work Node
下面还是在Master Node上操作，即同时作为Worker Node

5.1 创建工作目录并拷贝二进制文件
````
1.在所有workernode创建工作目录：
[root@k8s-master1 ~]# mkdir -p /opt/kubernetes/{bin,cfg,ssl,logs}
 
2.从master节点拷贝：
[root@k8s-master1 ~]# cd kubernetes/server/bin
[root@k8s-master1 bin]# cp kubelet kube-proxy /opt/kubernetes/bin
````

5.2 部署kubelet
````
1.创建配置文件
[root@k8s-master1 ~]# cat > /opt/kubernetes/cfg/kubelet.conf << EOF
KUBELET_OPTS="--logtostderr=false \\
--v=2 \\
--log-dir=/opt/kubernetes/logs \\
--hostname-override=k8s-master1 \\
--network-plugin=cni \\
--kubeconfig=/opt/kubernetes/cfg/kubelet.kubeconfig \\
--bootstrap-kubeconfig=/opt/kubernetes/cfg/bootstrap.kubeconfig \\
--config=/opt/kubernetes/cfg/kubelet-config.yml \\
--cert-dir=/opt/kubernetes/ssl \\
--pod-infra-container-image=registry.cn-hangzhou.aliyuncs.com/google_containers/pause:3.6"
EOF
 
#配置文件详解
--hostname-override：显示名称，集群中唯一
--network-plugin：启用CNI
--kubeconfig：空路径，会自动生成，后面用于连接apiserver
--bootstrap-kubeconfig：首次启动向apiserver申请证书
--config：配置参数文件
--cert-dir：kubelet证书生成目录
--pod-infra-container-image：管理Pod网络容器的镜像
 
2.配置参数文件
[root@k8s-master1 ~]# cat > /opt/kubernetes/cfg/kubelet-config.yml << EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
address: 0.0.0.0
port: 10250
readOnlyPort: 10255
cgroupDriver: cgroupfs
clusterDNS:
- 10.255.0.2
clusterDomain: cluster.local 
failSwapOn: false
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 2m0s
    enabled: true
  x509:
    clientCAFile: /opt/kubernetes/ssl/ca.pem 
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 5m0s
    cacheUnauthorizedTTL: 30s
evictionHard:
  imagefs.available: 15%
  memory.available: 100Mi
  nodefs.available: 10%
  nodefs.inodesFree: 5%
maxOpenFiles: 1000000
maxPods: 110
EOF
 
3.生成kubelet初次加入集群引导kubeconfig文件
（以下是shell命令，直接在终端执行）：
[root@k8s-master1 ~]# KUBE_CONFIG="/opt/kubernetes/cfg/bootstrap.kubeconfig"
[root@k8s-master1 ~]# KUBE_APISERVER="https://192.168.18.11:6443"
[root@k8s-master1 ~]# TOKEN="c47ffb939f5ca36231d9e3121a252940"    # 与token.csv里保持一致
 
#生成 kubelet bootstrap kubeconfig 配置文件
[root@k8s-master1 ~]# kubectl config set-cluster kubernetes \
--certificate-authority=/opt/kubernetes/ssl/ca.pem \
--embed-certs=true \
--server=${KUBE_APISERVER} \
--kubeconfig=${KUBE_CONFIG}
 
[root@k8s-master1 ~]# kubectl config set-credentials "kubelet-bootstrap" \
--token=${TOKEN} \
--kubeconfig=${KUBE_CONFIG}
 
[root@k8s-master1 ~]# kubectl config set-context default \
--cluster=kubernetes \
--user="kubelet-bootstrap" \
--kubeconfig=${KUBE_CONFIG}
 
[root@k8s-master1 ~]# kubectl config use-context default --kubeconfig=${KUBE_CONFIG}
 
4.systemd管理kubelet
cat > /usr/lib/systemd/system/kubelet.service << EOF
[Unit]
Description=Kubernetes Kubelet
After=docker.service
[Service]
EnvironmentFile=/opt/kubernetes/cfg/kubelet.conf
ExecStart=/opt/kubernetes/bin/kubelet \$KUBELET_OPTS
Restart=on-failure
LimitNOFILE=65536
[Install]
WantedBy=multi-user.target
EOF
 
5.启动并设置开机启动
[root@k8s-master1 ~]# systemctl daemon-reload
[root@k8s-master1 ~]# systemctl start kubelet
[root@k8s-master1 ~]# systemctl enable kubelet
[root@k8s-master1 ~]# systemctl status kubelet
````
5.3 批准kubelet证书申请加入集群

`````
1.查看kubelet证书请求
[root@k8s-master1 ~]# kubectl get csr
NAME                                                   AGE    SIGNERNAME                                    REQUESTOR           CONDITION
node-csr-1n2Vbxh8b378muwatZy6yRrD0PgmmgtBmD41qWUEmS8   2m1s   kubernetes.io/kube-apiserver-client-kubelet   kubelet-bootstrap   Pending
 
2.批准申请
[root@k8s-master1 ~]# kubectl certificate approve node-csr-1n2Vbxh8b378muwatZy6yRrD0PgmmgtBmD41qWUEmS8
 
3.查看节点
[root@k8s-master1 ~]# kubectl get node
NAME          STATUS     ROLES    AGE   VERSION
k8s-master1   NotReady   <none>   28s   v1.20.9
 
#注：由于网络插件还没有部署，节点会没有准备就绪 NotReady
`````
5.4 部署kube-proxy

```
1. 创建配置文件
[root@k8s-master1 ~]# cat > /opt/kubernetes/cfg/kube-proxy.conf << EOF
KUBE_PROXY_OPTS="--logtostderr=false \\
--v=2 \\
--log-dir=/opt/kubernetes/logs \\
--config=/opt/kubernetes/cfg/kube-proxy-config.yml"
EOF
 
2. 配置参数文件
[root@k8s-master1 ~]# cat > /opt/kubernetes/cfg/kube-proxy-config.yml << EOF
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
bindAddress: 0.0.0.0
metricsBindAddress: 0.0.0.0:10249
clientConnection:
  kubeconfig: /opt/kubernetes/cfg/kube-proxy.kubeconfig
hostnameOverride: k8s-master1
clusterCIDR: 10.255.0.0/16
EOF
 
3. 生成kube-proxy.kubeconfig文件
#切换工作目录
[root@k8s-master1 ~]# cd ~/TLS/k8s
 
#创建证书请求文件
[root@k8s-master1 k8s]# cat > kube-proxy-csr.json << EOF
{
  "CN": "system:kube-proxy",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "BeiJing",
      "ST": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ] 
}
EOF
 
#生成证书
[root@k8s-master1 k8s]# cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy
 
#生成kubeconfig文件：（以下是shell命令，直接在终端执行）：
[root@k8s-master1 k8s]# KUBE_CONFIG="/opt/kubernetes/cfg/kube-proxy.kubeconfig"
[root@k8s-master1 k8s]# KUBE_APISERVER="https://192.168.18.11:6443"
 
[root@k8s-master1 k8s]# kubectl config set-cluster kubernetes \
--certificate-authority=/opt/kubernetes/ssl/ca.pem \
--embed-certs=true \
--server=${KUBE_APISERVER} \
--kubeconfig=${KUBE_CONFIG}
 
[root@k8s-master1 k8s]# kubectl config set-credentials kube-proxy \
--client-certificate=./kube-proxy.pem \
--client-key=./kube-proxy-key.pem \
--embed-certs=true \
--kubeconfig=${KUBE_CONFIG}
 
[root@k8s-master1 k8s]# kubectl config set-context default \
--cluster=kubernetes \
--user=kube-proxy \
--kubeconfig=${KUBE_CONFIG}
 
[root@k8s-master1 k8s]# kubectl config use-context default --kubeconfig=${KUBE_CONFIG}
 
4.systemd管理kube-proxy
[root@k8s-master1 k8s]# cat > /usr/lib/systemd/system/kube-proxy.service << EOF
[Unit]
Description=Kubernetes Proxy
After=network.target
 
[Service]
EnvironmentFile=/opt/kubernetes/cfg/kube-proxy.conf
ExecStart=/opt/kubernetes/bin/kube-proxy \$KUBE_PROXY_OPTS
Restart=on-failure
LimitNOFILE=65536
 
[Install]
WantedBy=multi-user.target
EOF
 
5. 启动并设置开机启动
[root@k8s-master1 k8s]# systemctl daemon-reload
[root@k8s-master1 k8s]# systemctl start kube-proxy
[root@k8s-master1 k8s]# systemctl enable kube-proxy
[root@k8s-master1 k8s]# systemctl status kube-proxy
```


5.5 部署网络组件

````
 Calico是一个纯三层的数据中心网络方案，是目前Kubernetes主流的网络方案。
部署Calico： 此yaml文件使用的控制器是DaemonSet，所以所有的Node节点都会启动一个pod
````
````
[root@k8s-master1 k8s]# mkdir /root/yaml/Calico -p
cd /root/yaml/Calico
 
[root@k8s-master1 k8s]# wget --no-check-certificate https://docs.projectcalico.org/v3.9/manifests/calico.yaml #yaml文件下载地址 
kubectl apply -f calico.yaml
kubectl get pods -n kube-system
NAME                                       READY   STATUS    RESTARTS   AGE
calico-kube-controllers-56b44cd6d5-j2kch   1/1     Running   0          35m
calico-node-5rr2b                          1/1     Running   0          35m
 
等Calico Pod都Running，节点也会准备就绪：
[root@k8s-master1 k8s]# kubectl  get nodes
NAME          STATUS   ROLES    AGE   VERSION
k8s-master1   Ready    <none>   52m   v1.20.9

````


