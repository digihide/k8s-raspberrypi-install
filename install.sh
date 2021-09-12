#!/bin/sh


# user adding
sudo useradd -m -s /usr/bin/bash pi
/usr/bin/passwd pi <<EOF
raspberry
raspberry
EOF
sudo adduser pi sudo


# hostname adding
sudo hostnamectl set-hostname rasp-xxxx.local


#network adding
cat > /etc/netplan/99-network.yaml <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: false
      dhcp6: false
      addresses:
        - 192.168.13.xx/24
      gateway4: 192.168.13.99
      nameservers:
        addresses:
          - 8.8.8.8
EOF
sudo netplan apply


# host settings
echo 192.168.13.30      rasp-master rasp-master.local >> /etc/hosts
echo 192.168.13.31      rasp-node1 rasp-node1.local >> /etc/hosts
echo 192.168.13.32      rasp-node2 rasp-node2.local >> /etc/hosts


#time zone
sudo timedatectl set-timezone Asia/Tokyo


#ip6 stop
cp /etc/sysctl.conf /etc/sysctl.conf_old
cat > /etc/sysctl.conf << EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.eth0.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF
sudo sysctl -p


# nftables not use
sudo apt-get -y install iptables arptables ebtables
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
sudo update-alternatives --set arptables /usr/sbin/arptables-legacy
sudo update-alternatives --set ebtables /usr/sbin/ebtables-legacy


## Docker install
# (Install Docker CE)
## リポジトリをセットアップ
### HTTPS越しのリポジトリの使用をaptに許可するために、パッケージをインストール
apt-get update && apt-get install -y \
  apt-transport-https ca-certificates curl software-properties-common gnupg2

# Docker公式のGPG鍵を追加:
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -


# Dockerのaptレポジトリを追加:
add-apt-repository \
  "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) \
  stable"

# Docker CEのインストール
apt-get update && apt-get install -y \
containerd.io=1.2.13-2 \
docker-ce=5:19.03.11~3-0~ubuntu-$(lsb_release -cs) \
docker-ce-cli=5:19.03.11~3-0~ubuntu-$(lsb_release -cs)

## docker install(bata)
#sudo apt-get -y install \
#    apt-transport-https \
#    ca-certificates \
#    curl \
#    gnupg-agent \
#    software-properties-common
#curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
#sudo add-apt-repository "deb [arch=arm64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
#sudo apt-get update
#sudo apt-get -y install docker-ce docker-ce-cli containerd.io


# デーモンをセットアップ
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF
mkdir -p /etc/systemd/system/docker.service.d


# dockerを再起動
systemctl daemon-reload
systemctl restart docker
sudo systemctl enable docker


#cgroup
sed -i "s/$/ cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory/g" /boot/firmware/cmdline.txt


## CRI-O settings ##
modprobe overlay
modprobe br_netfilter

# 必要なカーネルパラメータの設定をします。これらの設定値は再起動後も永続化されます。
cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sysctl --system


OS=xUbuntu_20.04
VERSION=1.22

echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$VERSION/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$VERSION.list

curl -L https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$VERSION/$OS/Release.key | apt-key add -
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | apt-key add -

apt-get update
apt-get install cri-o cri-o-runc -y

systemctl daemon-reload
systemctl start crio


## kubeadm kubectl kubelet install ##
sudo apt-get update && sudo apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-get update
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl


sudo reboot
