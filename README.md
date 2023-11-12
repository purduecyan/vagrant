# Vagrant Resources
This repository provides Vagrant resources various projects.

## Getting Started
### Install Vagrant and VirtualBox
To install Vagrant on an Ubuntu machine with VirtualBox as the provider, run:
```shell
sudo apt update
sudo apt install virtualbox virtualbox-guest-additions-iso vagrant
```

### Install and configure `kubectl`
```shell
# Install `kubectl` utility
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.28/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.24/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update && sudo apt install kubectl

# Setup `kubectl` for use with VMs
vagrant ssh master -c "sudo cp /etc/kubernetes/admin.conf /vagrant"
echo "export KUBECONFIG=`pwd`/admin.conf" >> ~/.bashrc && export "KUBECONFIG=`pwd`/admin.conf"
kubectl get nodes
```

### Clone the repository
To clone this repository, use:
```shell
git clone https://github.com/purduecyan/vagrant.git
```

### Create the VMs
Navigate to the desired folder to create the necessary VMs. For example:
```shell
cd vagrant/kubernetes
```
Allow the network `172.42.42.0/24` for your VirtualBox machines
```shell
sudo mkdir /etc/vbox
sudo echo "* 172.42.42.0/24" >> /etc/vbox/networks.conf
```
Bring up the VMs using
```shell
vagrant up
```
Once the VMs are created, you can login to a VM using `vagrant ssh`. 
For example, after creating the kubernetes cluster, you can login to the master node using
```shell
vagrant ssh master
```
You can also stop all running VMs withing a project using 
```shell
vagrant halt
```

### Teardown
To delete all the VMs created, run
```shell
vagrant destroy
```

## Additional resources
You can find more information about Vagrant at https://www.vagrantup.com.
