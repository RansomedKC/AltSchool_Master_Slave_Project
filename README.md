# AltSchool_Master_Slave_Project
This repository contains solutions to the AltSchool second semester virtual box vagrant master slave project. 
# Creating Master and Slave Virtual Machines with Vagrant

## Task:

Create two Virtual Machines (VMs), one as a "master" and the other as a "slave" using Vagrant. The VMs should be configured with specific IP addresses, user accounts, and additional software installations. 

## How can I achieve this using a Bash script and Vagrant?

## Solution:

### Step 1: Variable Declarations

I started by declaring variables that will be used throughout the script. These variables include file names, IP addresses, usernames, passwords, and more.
### Shebang:
#!/bin/bash

# Variable declarations

V_File="Vagrantfile"
VM_Master="master"
VM_Slave="slave"
IP_Master="192.168.33.10"
IP_Slave="192.168.33.11"
NewUser="altschool"
PassWD="Ansome"
SQL_dUser="altschool"
SQL_dUserPasswd="altschool"

### Step 2: Adding Configs to Vagrantfile

In this step, I modify the Vagrantfile to define the configuration for the master and slave VMs. I set their base boxes, assign IP addresses, and configure the memory allocation. This ensures that the VMs will be created with the specified properties.
# Adding Configs to Vagrantfile to create Master and Slave VM
cat <<EOT >> $V_File
# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure("2") do |config|
  # Define the VM settings
  config.vm.define "master" do |master|
    master.vm.box = "ubuntu/focal64"
    master.vm.network "private_network", ip: "$IP_Master"
    master.vm.provider "virtualbox" do |vb|
      vb.memory = "1024"
    end
  end

  config.vm.define "slave" do |slave|
    slave.vm.box = "ubuntu/focal64"
    slave.vm.network "private_network", ip: "$IP_Slave"
    slave.vm.provider "virtualbox" do |vb|
      vb.memory = "1024"
    end
  end

  # Provisioning scripts
  config.vm.provision "shell", inline: <<-SHELL
    # Create new user and grant root privileges
    echo "Creating new user - altschool and granting root privileges..."
    sudo useradd -m -s /bin/bash -G root,sudo $NewUser
    echo "$NewUser:$PassWD" | sudo chpasswd
    sudo apt-get update && sudo apt upgrade -y
    sudo apt-get install sshpass -y
    sudo apt-get install -y avahi-daemon libnss-mdns
    echo "Installing LAMP Stack..."
    sudo apt install -y apache2 mysql-server php libapache2-mod-php php-mysql
    # Configure Apache2 to start on boot
    echo "Apache2 to start on boot..."
    sudo systemctl enable apache2
    sudo systemctl start apache2
    # Validate PHP functionality with Apache
    echo "Generating PHP test file..."
    echo -e '<?php\n\tphpinfo();\n?>' | sudo tee /var/www/html/index.php
  SHELL
end
EOT

### Step 3: Vagrant Up

I use the `vagrant up` command to start the VMs based on the Vagrantfile's configuration. This command will create and provision the VMs as defined.

### Step 4: Securing MySQL Installation

This step focuses on securing the MySQL installation on both the master and slave VMs. We use the `vagrant ssh` command to remotely execute the `mysql_secure_installation` script on each VM. This script sets the root password, removes anonymous users, disallows root login remotely, and removes the test database.

### Step 5: Initializing MySQL Users

After securing MySQL, we create a new MySQL user and grant them privileges. This is done on both the master and slave VMs, ensuring they are set up for future database management.
echo "Secure MySQL installation on VMs..."
echo "Initializing MySQL with default user and password for master..."
vagrant ssh $VM_Master -c "sudo mysql_secure_installation <<EOF
$SQL_dUserPasswd
n
y
y
y
y
EOF"
# SSH into VM_Master and execute MySQL commands
vagrant ssh $VM_Master <<EOF
sudo mysql -u root -e "CREATE USER '$SQL_dUser'@'localhost' IDENTIFIED BY '$SQL_dUserPasswd';"
sudo mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO '$SQL_dUser'@'localhost' WITH GRANT OPTION;"
sudo mysql -u root -e "FLUSH PRIVILEGES;"
EOF

echo "Initializing MySQL with default user and password for slave..."
vagrant ssh $VM_Slave -c "sudo mysql_secure_installation <<EOF
$SQL_dUserPasswd
n
y
y
y
y
EOF"
### Step 6: Modifying Sudoers File

In this step, I modifyed the sudoers file to allow the specified user (NewUser) to execute commands without a password prompt. This is done on both the master and slave VMs using the `sudo sed` and `sudo tee` commands.
# SSH into VM_Master and execute MySQL commands
vagrant ssh $VM_Master <<EOF
sudo mysql -u root -e "CREATE USER '$SQL_dUser'@'localhost' IDENTIFIED BY '$SQL_dUserPasswd';"
sudo mysql -u root -e "GRANT ALL PRIVILEGES ON *.* TO '$SQL_dUser'@'localhost' WITH GRANT OPTION;"
sudo mysql -u root -e "FLUSH PRIVILEGES;"
EOF

# SSH into VM_Master
# Make sudoers file writable and append the NOPASSWD entry for NewUser in sudoers
vagrant ssh $VM_Master -c "sudo sed -i 's/.*NOPASSWD:ALL.*//' /etc/sudoers"
vagrant ssh $VM_Master -c "sudo tee -a /etc/sudoers <<EOT
$NewUser ALL=(ALL) NOPASSWD:ALL
EOT"

# SSH into VM_Slave
# Make sudoers file writable and append the NOPASSWD entry for NewUser in sudoers
vagrant ssh $VM_Slave -c "sudo sed -i 's/.*NOPASSWD:ALL.*//' /etc/sudoers"
vagrant ssh $VM_Slave -c "sudo tee -a /etc/sudoers <<EOT
$NewUser ALL=(ALL) NOPASSWD:ALL
EOT"

### Step 7: Enabling Password Authentication for SSH

I enabled password authentication for SSH on the slave VM to allow password-based login. After modifying the SSH configuration, we restart the SSH service to apply the changes.
# Enable password authentication in SSH config, restart the SSH service
vagrant ssh $VM_Slave -c "sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config"
vagrant ssh $VM_Slave -c "sudo systemctl restart ssh"

### Step 8: SSH Key Pair Generation and Copying

I generated an SSH key pair for the NewUser on the master VM without a passphrase. Then, we copy the SSH public key to the slave VM, enabling passwordless SSH login. The SSH service on the master is restarted to apply the changes.
# Generate SSH key pair for NewUser without a passphrase
vagrant ssh $VM_Master -c "sudo -u $NewUser ssh-keygen -t rsa -b 2048 -N '' -f /home/$NewUser/.ssh/id_rsa"
# Copy the SSH public key to VM_Slave
vagrant ssh $VM_Master -c "sudo -u $NewUser sshpass -p '$PassWD' ssh-copy-id $NewUser@$IP_Slave"
# Restart SSH service on VM_Master
vagrant ssh $VM_Master -c "sudo -u $NewUser sudo systemctl restart ssh"

### Step 9: Disabling Password Authentication for SSH

In this step, we disable password authentication for SSH on the slave VM to enhance security. We modify the SSH configuration and restart the SSH service.
# Disable password authentication in SSH config, restart the SSH service
vagrant ssh $VM_Slave -c "sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
vagrant ssh $VM_Slave -c "sudo systemctl restart ssh"

echo "ssh connection completed"

### Step 10: Copying Files from Master to Slave

We use the `rsync` command to copy the contents of the `/mnt/AltSchool` directory from the master VM to the slave VM. This is a common method for syncing files between VMs.
# Copy contents of /mnt/AltSchool from Master node to Slave
echo "Copying /mnt/AltSchool from master to slave..."
vagrant ssh $VM_Master -c "sudo -u $NewUser rsync -avz /mnt/AltSchool/ $NewUser@$IP_Slave:/mnt/AltSchool/slave/"

### Step 11: Displaying Running Processes

I generated a list of currently running processes on the master VM and save it to a file named `running_process`. This provides an overview of the active processes.
# Display overview of currently running processes on Master node
echo "Overview of currently running processes on Master"
vagrant ssh $VM_Master -c "ps aux > /home/$NewUser/running_process"

### Step 12: Connecting Slave to Master

To manage the slave VM, we configure Apache on the slave VM to allow overriding settings and start the Apache service. This connects the slave to the master for further management.
# Connect Slave to Master for management
echo "Connecting slave to master for management..."
vagrant ssh $VM_Slave <<EOF
sudo sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
sudo systemctl enable apache2
sudo systemctl start apache2
EOF

### Step 13: Completion Message

Finally, we display a message to indicate that the master and slave VMs have been successfully deployed. The script also includes the VM names and IP addresses for reference.
### echo "Master and Slave VMs deployed successfully :)"
echo "Master and Slave VMs deployed successfully :)"
echo -e "$VM_Master: $VM_Master $IP_Master\n$VM_Slave: $VM_Slave $IP_Slave"

### This script combines Vagrant configuration, system administration tasks, and file synchronization to create and manage a master-slave setup with specific configurations.
