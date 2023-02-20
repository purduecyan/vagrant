#!/bin/bash

# Join worker nodes to the Kubernetes cluster
echo "[TASK 1] Join node to Kubernetes Cluster"
rm /etc/containerd/config.toml
systemctl restart containerd
apt-get  install -y sshpass
sshpass -p "kubeadmin" scp -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no master.example.com:/joincluster.sh /joincluster.sh
# sshpass -p "kubeadmin" scp -o StrictHostKeyChecking=no master.example.com:/joincluster.sh /joincluster.sh
bash /joincluster.sh

