#!/bin/bash

# Setup an Ubuntu VPS

#------------------------------------------------------------
# Modify values below here
#------------------------------------------------------------

CHKROOTKIT=1
ECHO_COMMANDS=0
EMACS=1

GEM_CREDITCARD=1
GEM_JSON=1
GEM_WILL_PAGINATE=1

# To install memcached, specify a RAM amount > 0 e.g. 16
MEMCACHED_RAM=16

PASSENGER=1
POSTFIX=1
POSTGRES=1
PUBLIC_KEY_URL=http://lojic.com/id_rsa.pub

# To install Rails, set RAILS_VERSION to a non-empty version string
RAILS_VERSION=3.0.7

RKHUNTER=1
RUBY_SOURCE=http://ftp.ruby-lang.org/pub/ruby/1.9/ruby-1.9.2-p180.tar.gz
SCREEN=1
SHOREWALL=1

# To install thttpd, specify a port > 0 e.g. 8000
THTTPD_PORT=8000

TIMEZONE=US/Eastern
USERNAME=badkins1
UPDATE_UBUNTU=1
WWW_DIR=/var/www

#------------------------------------------------------------
# Modify values above here
#------------------------------------------------------------

#------------------------------------------------------------
# Help Information:
#
# nginx:
#   example server block:
#      server {
#        listen 80;
#        server_name www.yourhost.com;
#        root /somewhere/public;   # <--- be sure to point to 'public'!
#        passenger_enabled on;
#      }
#------------------------------------------------------------

#------------------------------------------------------------
# Functions
#------------------------------------------------------------

function apt_get_packages_common() {
  display_message "Installing common packages"
  apt-get -y install build-essential dnsutils git-core imagemagick libpcre3-dev \
             libreadline5-dev libssl-dev libxml2-dev locate rsync zlib1g-dev
}

function apt_get_packages() {
  display_message "Installing packages"
  apt_get_packages_common
  
  # rkhunter root kit checker
  if [ "$RKHUNTER" = 1 ]; then
    display_message "Installing rkhunter"
    apt-get -y install rkhunter
    # The rkhunter --update command may have a non-zero return code
    # even when no error occurs. From the man page:
    # 
    # An exit code of zero for  this  command  option  means  that  no
    # updates  were  available.  An  exit  code  of  one  means that a
    # download error occurred, and a code of two means that  no  error
    # occurred but updates were available and have been installed.
    set +e
    rkhunter --update
    if [ $? -eq 1 ]; then
      display_message "rkhunter --update failed"
      exit 1
    fi
    set -e
  fi
  
  if [ "$CHKROOTKIT" = 1 ]; then
    display_message "Installing chkrootkit"
    apt-get -y install chkrootkit
  fi
  
  if [ "$SHOREWALL" = 1 ]; then
    install_shorewall_firewall
  fi
  
  if [ "$EMACS" = 1 ]; then
    display_message "Installing emacs"
    apt-get -y install emacs23-nox
  fi

  if [ "$SCREEN" = 1 ]; then
    display_message "Installing screen"
    apt-get -y install screen
  fi

  if [ "$MEMCACHED_RAM" -gt 0 ]; then
    display_message "Installing memcached"
    apt-get -y install memcached
    sed -i -e "/^-m 64/c-m ${MEMCACHED_RAM}" /etc/memcached.conf
  fi
  
  if [ "$POSTFIX" = 1 ]; then
    display_message "Installing postfix"
    apt-get -y install postfix
  fi
  
  if [ "$POSTGRES" = 1 ]; then
    display_message "Installing postgresql"
    apt-get -y install libecpg-dev postgresql
  fi
  
  if [ "$THTTPD_PORT" -gt 0 ]; then
    install_thttpd
  fi
  
  if [ "$PASSENGER" = 1 ]; then
    display_message "Installing libcurl4-openssl-dev for passenger"
    apt-get -y install libcurl4-openssl-dev
  fi
  
}

function configure_timezone() {
  local tz=$1

  if [ $tz ]; then
    echo $tz > /etc/timezone
    dpkg-reconfigure -f noninteractive tzdata
  fi
}

# Create new user with user:
# create_user username [ public_key_url ]
function create_user() {
  local username=$1
  local pub_key_url=$2
  display_message "Adding new user ${username}:"
  adduser $username

  # Add user to sudoer lsit
  sed -i "\$a$username ALL=ALL" /etc/sudoers

  # Configure command history
  sed -i -e '/^HISTSIZE/cHISTSIZE=8192' /home/${username}/.bashrc
  sed -i -e '/^HISTFILESIZE/cHISTFILESIZE=8192' /home/${username}/.bashrc
  sed -i -e '/^HISTCONTROL=ignoredups:ignorespace/cHISTCONTROL=ignoredups:ignorespace:erasedups' /home/${username}/.bashrc

  if [ $pub_key_url ]; then
    # Setup ssh keys
    mkdir /home/${username}/.ssh
    chown ${username}:${username} /home/${username}/.ssh
    wget -O /home/${username}/.ssh/authorized_keys $pub_key_url
    chown ${username}:${username} /home/${username}/.ssh/authorized_keys
    chmod 400 /home/${username}/.ssh/authorized_keys
  fi
  
  if [ $SCREEN ]; then
    # use C-\ instead of C-a to avoid Emacs conflicts
    echo 'escape \034\034' > /home/${username}/.screenrc
    chown ${username}:${username} /home/${username}/.screenrc
  fi
}

function display_message() {
  if [ "$1" ]; then
    echo ' '
    echo '************************************************************'
    echo "$1"
    echo '************************************************************'
    echo ' '
  fi
}

function file_name_from_path() {
  echo ${1##*/}
}

function initialize() {
  # Exit on first error, echo commands
  set -e

  if [ "$ECHO_COMMANDS" = 1 ]; then
      set -x
  fi
  
  # Set default values
  MEMCACHED_RAM=${MEMCACHED_RAM:-0}
  THTTPD_PORT=${THTTPD_PORT:-0}
}

function install_gems() {
  if [ "$POSTGRES" = 1 ]; then
    display_message "Installing pg gem"
    gem install --no-rdoc --no-ri pg
  fi  

  if [ "$GEM_CREDITCARD" = 1 ]; then
    display_message "Installing creditcard gem"
    gem install --no-rdoc --no-ri creditcard
  fi  

  if [ "$GEM_JSON" = 1 ]; then
    display_message "Installing json gem"
    gem install --no-rdoc --no-ri json
  fi  

  if [ "$GEM_WILL_PAGINATE" = 1 ]; then
    display_message "Installing will_paginate gem"
    gem install --no-rdoc --no-ri will_paginate
  fi  
}

function install_passenger() {
  display_message "Installing passenger"
  gem install --no-rdoc --no-ri passenger
  passenger-install-nginx-module --auto --auto-download --prefix=/usr/local/nginx
}

function install_rails() {
  local rails_version=$1

  if [ $rails_version ]; then
    display_message "Installing Rails ${rails_version}"
    gem install --no-rdoc --no-ri -v ${rails_version} rails
  fi
}

# install_ruby <ruby source url>
function install_ruby() {
  local ruby_src=$1
  
  if [ $ruby_src ]; then
    display_message "Installing Ruby"
    pushd /usr/local/src
    wget $ruby_src
    local fname=$(file_name_from_path $ruby_src)
    tar xzf $fname
    local prefix=${fname%\.tar\.gz}
    cd $prefix
    ./configure
    make
    make install
    popd
  fi
}

function install_shorewall_firewall() {
  display_message "Installing shorewall firewall"
  apt-get -y install shorewall shorewall-doc

  cat > /etc/shorewall/interfaces <<EOF
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
EOF

  cat > /etc/shorewall/policy <<EOF
#SOURCE ZONE   DESTINATION ZONE   POLICY   LOG LEVEL   LIMIT:BURST
\$FW            net                ACCEPT
net            all                DROP     info
all            all                REJECT   info
EOF

  cat > /etc/shorewall/rules <<EOF
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
EOF

  cat > /etc/shorewall/zones <<EOF
#ZONE   TYPE    OPTIONS                 IN                      OUT
#                                       OPTIONS                 OPTIONS
fw      firewall
net     ipv4
EOF

  sed -i -e '/^startup=/cstartup=1' /etc/default/shorewall
}

function install_thttpd() {
  display_message "Installing thttpd"
  apt-get -y install thttpd
  pushd /etc/thttpd
  cp thttpd.conf orig.thttpd.conf
  cat > /etc/thttpd/thttpd.conf <<EOF
port=${THTTPD_PORT}
dir=${WWW_DIR}/thttpd
nochroot
user=www-data
cgipat=**.rb
throttles=/etc/thttpd/throttle.conf
logfile=/var/log/thttpd.log
EOF
  sed -i -e '/^ENABLED=/cENABLED=yes' /etc/default/thttpd
  popd
}

function prologue() {
  if [ "$SHOREWALL" = 1 ]; then
    echo "Test the firewall via: shorewall safe-start (and verify ssh)"
  fi

  if [ $MEMCACHED_RAM -gt 0 ]; then
    cat <<EOF

Configure memcached via:
sudo vim /etc/memcached.conf
EOF
  fi
  
  if [ "$POSTFIX" = 1 ]; then
    cat <<EOF

vim /etc/postfix/main.cf
 * remove foo.com from mydestination to not deliver locally
 * change: myhostname = foo.com
 * change: inet_interfaces = loopback-only
/etc/init.d/postfix restart
EOF
  fi
  
  if [ "$POSTGRES" = 1 ]; then
    cat <<EOF

Configure postgresql:
su postgres
psql
create role ${USERNAME} superuser login;
EOF
  fi
}

# Prevent root login
# Prevent password login
function secure_ssh() {
  # Ensure root can't ssh in
  sed -i -e '/PermitRootLogin/s/yes/no/' /etc/ssh/sshd_config

  # Don't allow password login
  sed -i -e '/^#PasswordAuthentication yes/cPasswordAuthentication no' /etc/ssh/sshd_config

  # Restart sshd
  /etc/init.d/ssh restart
}

function update_ubuntu() {
  if [ "$UPDATE_UBUNTU" = 1 ]; then
    display_message "Updating Ubuntu"
    apt-get -y update
    apt-get -y upgrade
  fi
}

#------------------------------------------------------------
# Main
#------------------------------------------------------------

initialize
configure_timezone $TIMEZONE
echo 'Changing root password:'
passwd # Change root passwd
create_user $USERNAME $PUBLIC_KEY_URL
secure_ssh
update_ubuntu
apt_get_packages
install_ruby $RUBY_SOURCE
install_rails $RAILS_VERSION
install_passenger
install_gems
prologue