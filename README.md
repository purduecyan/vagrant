# Vagrant Resources
This repository provides Vagrant resources various projects.

## Getting Started
### Install Vagrant and VirtualBox
To install Vagrant on an Ubuntu machine with VirtualBox as the provider, run:
```shell
sudo apt update
sudo apt install virtualbox virtualbox-guest-additions-iso vagrant 
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
