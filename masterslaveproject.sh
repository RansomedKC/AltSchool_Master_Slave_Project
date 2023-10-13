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

vagrant up

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

# Enable password authentication in SSH config, restart the SSH service
vagrant ssh $VM_Slave -c "sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config"
vagrant ssh $VM_Slave -c "sudo systemctl restart ssh"

# Generate SSH key pair for NewUser without a passphrase
vagrant ssh $VM_Master -c "sudo -u $NewUser ssh-keygen -t rsa -b 2048 -N '' -f /home/$NewUser/.ssh/id_rsa"
# Copy the SSH public key to VM_Slave
vagrant ssh $VM_Master -c "sudo -u $NewUser sshpass -p '$PassWD' ssh-copy-id $NewUser@$IP_Slave"
# Restart SSH service on VM_Master
vagrant ssh $VM_Master -c "sudo -u $NewUser sudo systemctl restart ssh"

# Disable password authentication in SSH config, restart the SSH service
vagrant ssh $VM_Slave -c "sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config"
vagrant ssh $VM_Slave -c "sudo systemctl restart ssh"

echo "ssh connection completed"

# Copy contents of /mnt/AltSchool from Master node to Slave
echo "Copying /mnt/AltSchool from master to slave..."
vagrant ssh $VM_Master -c "sudo -u $NewUser rsync -avz /mnt/AltSchool/ $NewUser@$IP_Slave:/mnt/AltSchool/slave/"

# Display overview of currently running processes on Master node
echo "Overview of currently running processes on Master"
vagrant ssh $VM_Master -c "ps aux > /home/$NewUser/running_process"

# Connect Slave to Master for management
echo "Connecting slave to master for management..."
vagrant ssh $VM_Slave <<EOF
sudo sed -i 's/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
sudo systemctl enable apache2
sudo systemctl start apache2
EOF

echo "Master and Slave VMs deployed successfully :)"
echo -e "$VM_Master: $VM_Master $IP_Master\n$VM_Slave: $VM_Slave $IP_Slave"
