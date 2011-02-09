#!/bin/bash

# 1) ssh to server
# 2) cat > setup.bash   # copy this file
# 3) chmod +x setup.bash
# 4) ./setup.bash

# Exit on first error, echo commands
set -e -x

# Change root password
echo "Change root password"
passwd

# Create non-root administrative user
echo "Change badkins password"
adduser badkins
sed -i.bak '$abadkins ALL=ALL' /etc/sudoers
sed -i.bak -e '/^HISTSIZE/cHISTSIZE=8192' /home/badkins/.bashrc
sed -i.bak2 -e '/^HISTFILESIZE/cHISTFILESIZE=8192' /home/badkins/.bashrc

# Setup ssh keys
mkdir /home/badkins/.ssh
chown badkins:badkins /home/badkins/.ssh
wget -O /home/badkins/.ssh/authorized_keys http://lojic.com/id_rsa.pub 
chown badkins:badkins /home/badkins/.ssh/authorized_keys
chmod 400 /home/badkins/.ssh/authorized_keys

# Ensure root can't ssh in
sed -i.bak -e '/PermitRootLogin/s/yes/no/' /etc/ssh/sshd_config
# Don't allow password login
sed -i.bak2 -e '/^#PasswordAuthentication yes/cPasswordAuthentication no' /etc/ssh/sshd_config
/etc/init.d/ssh restart

# Update Ubuntu
apt-get -y update
apt-get -y upgrade

# rkhunter
apt-get -y install rkhunter
rkhunter --update

# chkrootkit
apt-get -y install chkrootkit

# Install/configure shorewall firewall
apt-get -y install shorewall shorewall-doc
cd /etc/shorewall

cat > interfaces <<BJAEOF
#
# Shorewall version 4 - Interfaces File
#
# For information about entries in this file, type "man shorewall-interfaces"
#
# The manpage is also online at
# http://www.shorewall.net/manpages/shorewall-interfaces.html
#
###############################################################################
#ZONE   INTERFACE       BROADCAST       OPTIONS
net     eth0     -          routefilter,tcpflags
#LAST LINE -- ADD YOUR ENTRIES BEFORE THIS ONE -- DO NOT REMOVE
BJAEOF

cat > policy <<BJAEOF
#SOURCE ZONE   DESTINATION ZONE   POLICY   LOG LEVEL   LIMIT:BURST
\$FW            net                ACCEPT
net            all                DROP     info
all            all                REJECT   info
BJAEOF

cat > rules <<BJAEOF
#
# Shorewall version 4 - Rules File
#
# For information on the settings in this file, type "man shorewall-rules"
#
# The manpage is also online at
# http://www.shorewall.net/manpages/shorewall-rules.html
#
############################################################################################################################
#ACTION         SOURCE          DEST            PROTO   DEST    SOURCE          ORIGINAL        RATE            USER/   MARK
#                                                       PORT    PORT(S)         DEST            LIMIT           GROUP
#SECTION ESTABLISHED
#SECTION RELATED
SECTION NEW
Web/ACCEPT      net     \$FW
SSH/ACCEPT      net     \$FW
#LAST LINE -- ADD YOUR ENTRIES BEFORE THIS ONE -- DO NOT REMOVE
BJAEOF

cat > zones <<BJAEOF
#ZONE   TYPE    OPTIONS                 IN                      OUT
#                                       OPTIONS                 OPTIONS
fw      firewall
net     ipv4
BJAEOF

sed -i.bak -e '/^startup=/cstartup=1' /etc/default/shorewall

# Install Ruby
apt-get -y install ruby irb

# Install Emacs
apt-get -y install emacs23-nox

# Install Screen
apt-get -y install screen
# use C-\ instead of C-a to avoid Emacs conflicts
# use single quotes to avoid expanding the escape sequence
echo "escape \034\034" > /home/badkins/.screenrc
chown badkins:badkins /home/badkins/.screenrc

# Stop echoing commands
set -

echo "Root password has been changed"
echo "Ubuntu has been updated"
echo "badkins user has been created and added to sudoers"
echo "Root has been prevented from using ssh"
echo "Password login has been disabled - use ssh keys"
echo "Ruby has been installed"
echo "Emacs 23 has been installed"
echo "Screen has been installed"
echo "Test the firewall via: shorewall safe-start (and verify ssh)"
echo "shutdown -r now"
echo "Then login as badkins to continue setup"
