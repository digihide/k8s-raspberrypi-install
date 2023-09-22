#!/bin/sh

#k8sの推進環境にruntimeがcri-oなどの変更になっているので
#改めての導入方法を以下に記載する。
#以下の手順で、行う。
#ホスト名およびIPアドレスについては、環境に合わせること！

OS=Debian_10
CRIO_VERSION=1.23
IP_LIST=(
	192.168.10.10
	192.168.10.11
	192.168.10.12
	)


# IPの設定
raspi-config nonint do_hostname raspi-master
sudo raspi-config nonint do_change_timezone Asia/Tokyo
sudo raspi-config  --expand-rootfs
sudo apt-get update && sudo apt-get dist-upgrade -y
sudo apt-get update && sudo apt-get upgrade -y

for ip in ${IP_LIST[@]}
do
  ping_result=$(ping -c 3 $ip | grep 'timeout')

  if [[ -n $ping_result ]]; then
    echo static ip_address=192.168.10.$ip/24 >> /etc/dhcpcd.conf
  break  # 該当するMACアドレスが見つかったらループを終了
  fi
done

echo static routers=192.168.10.1 >> /etc/dhcpcd.conf
echo static domain_name_servers=192.168.10.1 8.8.8.8 >> /etc/dhcpcd.conf


# cat <<EOF >> /etc/dhcpcd.conf
# static ip_address=192.168.10.xx/24
# static routers=192.168.10.1
# static domain_name_servers=192.168.10.1 8.8.8.8
# EOF


# cgroup settings
sudo sed -i 's/$/ cgroup_enable=cpuset cgroup_memory=1 cgroup_enable=memory/g' /boot/cmdline.txt


# swap setting
sudo swapoff --all
sudo systemctl stop dphys-swapfile
sudo systemctl disable dphys-swapfile
systemctl status dphys-swapfile


# ip tables settings
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
br_netfilter
EOF

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF

sudo apt-get install -y iptables arptables ebtables
sudo update-alternatives --set iptables /usr/sbin/iptables-legacy
sudo update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
sudo update-alternatives --set arptables /usr/sbin/arptables-legacy
sudo update-alternatives --set ebtables /usr/sbin/ebtables-legacy
sudo sysctl --system


# crio(runtime for Docker) setting
cat <<EOF | sudo tee /etc/modules-load.d/crio.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system


echo "deb https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list
echo "deb http://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO_VERSION/$OS/ /" | sudo tee /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION.list
curl -L https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:$CRIO_VERSION/$OS/Release.key | sudo apt-key add -
curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | sudo apt-key add -
sudo apt update
sudo apt update
sudo apt upgrade -y
sudo apt install cri-o cri-o-runc -y
sudo systemctl daemon-reload
sudo systemctl enable crio
sudo systemctl start crio


# k8s install
sudo apt-get update && sudo apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF

sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
cat <<EOF | sudo tee /etc/default/kubelet
KUBELET_EXTRA_ARGS=--container-runtime-endpoint='unix:///var/run/crio/crio.sock'
EOF

systemctl daemon-reload
systemctl restart kubelet

sudo reboot

