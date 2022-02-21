#!/bin/bash

# Update hosts file
echo "[TASK 1] Update /etc/hosts file"
cat >>/etc/hosts<<EOF
172.42.42.100 master.example.com master
172.42.42.101 worker1.example.com worker1
172.42.42.102 worker2.example.com worker2
EOF


echo "[TASK 2] Install docker container engine"
apt-get install apt-transport-https ca-certificates curl software-properties-common -y
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update -y
apt-get install docker-ce -y

# add ccount to the docker group
usermod -aG docker vagrant

# Following configurations are recomended in the kubenetes documentation for Docker runtime.
# Please refer to https://kubernetes.io/docs/setup/production-environment/container-runtimes/#docker

cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m"
  },
  "storage-driver": "overlay2"
}
EOF

echo "Docker Runtime Configured Successfully"

# Enable docker service
echo "[TASK 3] Enable and start docker service"
systemctl enable docker >/dev/null 2>&1
systemctl daemon-reload
sudo systemctl restart docker


# Add sysctl settings
echo "[TASK 6] Add sysctl settings"
cat >>/etc/sysctl.d/kubernetes.conf<<EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system >/dev/null 2>&1

# Disable swap
echo "[TASK 7] Disable and turn off SWAP"
sed -i '/swap/d' /etc/fstab
swapoff -a

# Install apt-transport-https pkg
echo "[TASK 8] Installing apt-transport-https pkg"
apt-get update && apt-get install -y apt-transport-https curl ca-certificates 
# curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
curl -fsSLo /usr/share/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg

# Add he kubernetes sources list into the sources.list directory
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
# deb https://apt.kubernetes.io/ kubernetes-xenial main
deb [signed-by=/usr/share/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main
EOF
# verify
ls -ltr /etc/apt/sources.list.d/kubernetes.list

apt-get update -y

# Install Kubernetes
echo "[TASK 9] Install Kubernetes kubeadm, kubelet and kubectl"
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl

# Start and Enable kubelet service
echo "[TASK 10] Enable and start kubelet service"
systemctl enable kubelet >/dev/null 2>&1
systemctl start kubelet >/dev/null 2>&1

# Enable ssh password authentication
echo "[TASK 11] Enable ssh password authentication"
sed -i 's/^PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config
systemctl reload sshd

# Set Root password
echo "[TASK 12] Set root password"
echo -e "kubeadmin\nkubeadmin" | passwd root
#echo "kubeadmin" | passwd --stdin root >/dev/null 2>&1

# Update vagrant user's bashrc file
echo "export TERM=xterm" >> /etc/bashrc
