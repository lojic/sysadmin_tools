#!/bin/bash

# This Bash script sets up a new Ubuntu web server.

# Copyright (C) 2011 by Brian J. Adkins

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

#------------------------------------------------------------
# Modify values below here
#------------------------------------------------------------

USERNAME=deploy
NOTIFICATION_EMAIL=  # fail2ban will send emails to this address

# To install postfix, specify a non-empty domain name for POSTFIX_DOMAIN
POSTFIX_DOMAIN=

# To setup ssh keys, specify a url containing a public key
PUBLIC_KEY_URL=


# Boolean flags 1 => true, 0 => false
CHKROOTKIT=1             # Install chkrootkit root kit checker via apt-get
ECHO_COMMANDS=0          # Echo commands from script
EMACS=1                  # Install Emacs via apt-get
FAIL2BAN=1               # Install fail2ban via apt-get
GEM_CREDITCARD=1         # Ruby gem: creditcard
GEM_JSON=1               # Ruby gem: json
GEM_WILL_PAGINATE=1      # Ruby gem: will_paginate
GHC=1                    # Install Glasgow Haskell Compiler via apt-get
MLTON=1                  # Install MLton Standard ML Compiler via apt-get
PASSENGER=1              # Install Phusion Passenger and nginx
POSTGRES=1               # Install Postgres database via apt-get
RKHUNTER=1               # Install rkhunter root kit checker via apt-get
SCREEN=1                 # Install screen via apt-get
SHOREWALL=1              # Install shorewall firewall via apt-get

# Prevent prompts during postfix installation
export DEBIAN_FRONTEND=noninteractive

# To install memcached, specify a RAM amount > 0 e.g. 16
MEMCACHED_RAM=16

# To install Rails, set RAILS_VERSION to a non-empty version string
RAILS_VERSION=3.0.7

# To install Ruby, specify a url for source
RUBY_SOURCE=http://ftp.ruby-lang.org/pub/ruby/1.9/ruby-1.9.2-p180.tar.gz

# To install Trust Commerce's tclink API, specify a url for source
TCLINK_SOURCE=https://vault.trustcommerce.com/downloads/tclink-3.4.4-ruby.tar.gz

# To install thttpd, specify a port > 0 e.g. 8000
THTTPD_PORT=0

TIMEZONE=US/Eastern
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
    sed -i.orig -e "/^-m 64/c-m ${MEMCACHED_RAM}" /etc/memcached.conf
  fi
  
  if [ "$POSTFIX_DOMAIN" ]; then
    install_postfix
  fi
  
  if [ "$POSTGRES" = 1 ]; then
    install_postgres
  fi
  
  if [ "$THTTPD_PORT" -gt 0 ]; then
    install_thttpd
  fi
  
  if [ "$PASSENGER" = 1 ]; then
    display_message "Installing libcurl4-openssl-dev for passenger"
    apt-get -y install libcurl4-openssl-dev
  fi
  
  if [ "$MLTON" = 1 ]; then
    display_message "Installing mlton"
    apt-get -y install mlton
  fi
  
  if [ "$FAIL2BAN" = 1 ]; then
    install_fail2ban
  fi
  
}

function configure_logrotate() {
  cat >> /etc/logrotate.conf <<'EOF'
/usr/local/nginx/logs/*.log {
    missingok
    notifempty
    sharedscripts
    postrotate
        test ! -f /usr/local/nginx/logs/nginx.pid || kill -USR1 `cat /usr/local/nginx/logs/nginx.pid`
    endscript
}
EOF
}

function configure_nginx() {
  cat > /etc/init.d/nginx <<'EOF'
# Description: Startup script for nginx webserver on Debian. Place in /etc/init.d and 
# run 'sudo update-rc.d nginx defaults', or use the appropriate command on your
# distro.
#
# Author:       Ryan Norbauer <ryan.norbauer@gmail.com>
# Modified:     Geoffrey Grosenbach http://topfunky.com

set -e

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
DESC="nginx daemon"
NAME=nginx
DAEMON=/usr/local/nginx/sbin/$NAME
CONFIGFILE=/usr/local/nginx/conf/nginx.conf
#PIDFILE=/var/run/$NAME.pid
PIDFILE=/usr/local/nginx/logs/$NAME.pid
SCRIPTNAME=/etc/init.d/$NAME

# Gracefully exit if the package has been removed.
test -x $DAEMON || exit 0

d_start() {
  $DAEMON -c $CONFIGFILE || echo -n " already running"
}

d_stop() {
  kill -QUIT `cat $PIDFILE` || echo -n " not running"
}

d_reload() {
  kill -HUP `cat $PIDFILE` || echo -n " can't reload"
}

case "$1" in
  start)
        echo -n "Starting $DESC: $NAME"
        d_start
        echo "."
        ;;
  stop)
        echo -n "Stopping $DESC: $NAME"
        d_stop
        echo "."
        ;;
  reload)
echo -n "Reloading $DESC configuration..."
d_reload
        echo "reloaded."
  ;;
  restart)
        echo -n "Restarting $DESC: $NAME"
        d_stop
        # One second might not be time enough for a daemon to stop, 
        # if this happens, d_start will fail (and dpkg will break if 
        # the package is being upgraded). Change the timeout if needed
        # be, or change d_stop to have start-stop-daemon use --retry. 
        # Notice that using --retry slows down the shutdown process somewhat.
        sleep 1
        d_start
        echo "."
        ;;
  *)
          echo "Usage: $SCRIPTNAME {start|stop|restart|force-reload}" >&2
          exit 3
        ;;
esac

exit 0
EOF
  chmod 755 /etc/init.d/nginx
  display_message "Setting update-rc.d defaults for nginx"
  update-rc.d nginx defaults  
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
  sed -i.orig "\$a$username ALL=ALL" /etc/sudoers

  # Configure command history
  cp /home/${username}/.bashrc /home/${username}/.bashrc.orig
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

function install_fail2ban() {
  display_message "Installing fail2ban"
  apt-get -y install fail2ban
  cp /etc/fail2ban//jail.conf /etc/fail2ban/jail.local
  sed -i -e '/^bantime/cbantime = 1800' /etc/fail2ban/jail.local

  if [ "$NOTIFICATION_EMAIL" ]; then
    sed -i -e "/^destemail/cdestemail = ${NOTIFICATION_EMAIL}" /etc/fail2ban/jail.local
  fi
  
  /etc/init.d/fail2ban restart
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
  configure_nginx
}

function install_postfix() {
  display_message "Installing postfix"
  apt-get -y install postfix
  display_message "Modifying /etc/postfix/main.cf"
  cp /etc/postfix/main.cf /etc/postfix/main.cf.orig
  sed -i -e "/^myhostname/cmyhostname = ${POSTFIX_DOMAIN}" /etc/postfix/main.cf
  sed -i -e "/^mydestination/cmydestination = localhost.localdomain, localhost" /etc/postfix/main.cf
  sed -i -e "/^inet_interfaces/cinet_interfaces = loopback-only" /etc/postfix/main.cf
}

function install_postgres() {
  display_message "Installing postgresql"
  apt-get -y install libecpg-dev postgresql
  su -c psql postgres <<EOF
create role $USERNAME superuser login;
EOF
}

function install_rails() {
  local rails_version=$1

  if [ $rails_version ]; then
    display_message "Installing Rails ${rails_version} - this will take a while"
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

  sed -i.orig -e '/^startup=/cstartup=1' /etc/default/shorewall
}

function install_tclink() {
  local tclink_src=$1
  
  if [ $tclink_src ]; then
    pushd /usr/local/src
    display_message "Downloading tclink"
    wget $tclink_src
    local fname=$(file_name_from_path $tclink_src)
    display_message "Extracting tclink"
    tar xzf $fname
    local prefix=${fname%\.tar\.gz}
    cd $prefix
    display_message "Patching tclink"
    # Patch rb_tclink.c & tctest.rb
    cat > patch.txt <<EOF
diff --git a/rb_tclink.c b/rb_tclink.c
index 1443c15..890b09f 100644
--- a/rb_tclink.c
+++ b/rb_tclink.c
@@ -48,8 +48,8 @@ tclink_send(VALUE obj, VALUE params) {
 		input_key = rb_funcall(input_keys, rb_intern("[]"), 1,
                                        INT2FIX(i));
 		input_value = rb_hash_aref(params, input_key);
-		TCLinkPushParam(handle, RSTRING(StringValue(input_key))->ptr,
-                                RSTRING(StringValue(input_value))->ptr);
+		TCLinkPushParam(handle, RSTRING_PTR(StringValue(input_key)),
+                                RSTRING_PTR(StringValue(input_value)));
 	}
 
 	/* send the transaction */
diff --git a/tctest.rb b/tctest.rb
index 27c640e..df7b6f2 100755
--- a/tctest.rb
+++ b/tctest.rb
@@ -8,7 +8,7 @@ begin
   require 'tclink'
 rescue LoadError
   print "Failed to load TCLink extension\n"
-  exit
+  exit 1
 end
 
 print "TCLink version " + TCLink.getVersion() + "\n"
@@ -35,3 +35,5 @@ print "done!\n\nTransaction results:\n"
 for key in result.keys()
   print "\t" + key + "=" + result[key] + "\n"
 end
+
+exit 1 unless result['status'] == 'approved'
EOF
    patch <patch.txt
    display_message "Building tclink"
    ./build.sh
    display_message "Copying to Ruby extensions directory"
    cp tclink.so /usr/local/lib/ruby/1.9.1/x86_64-linux/
    display_message "Testing tclink"
    ruby tctest.rb
    popd
  fi
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
  sed -i.orig -e '/^ENABLED=/cENABLED=yes' /etc/default/thttpd
  popd
}

function epilogue() {
  if [ "$SHOREWALL" = 1 ]; then
    cat <<EOF

Test the firewall via: shorewall safe-start (and verify ssh)
EOF
  fi
  cat <<EOF

Root has been disabled from logging in via ssh.
Use the new user $USERNAME in conjunction with sudo.

Password login has been disabled, you must have your public
key installed in ~/.ssh/authorized_keys

Reboot is recommended to verify processes start properly at boot
EOF
}

# Prevent root login
# Prevent password login
function secure_ssh() {
  cp /etc/ssh/sshd_config /etc/ssh/sshd_config.orig

  # Ensure root can't ssh in
  sed -i -e '/PermitRootLogin/s/yes/no/' /etc/ssh/sshd_config

  # Don't allow password login if public key has been supplied
  if [ "$PUBLIC_KEY_URL" ]; then
    sed -i -e '/^#PasswordAuthentication yes/cPasswordAuthentication no' /etc/ssh/sshd_config
  fi

  # Restart sshd
  /etc/init.d/ssh restart
}

function update_ubuntu() {
  display_message "Updating Ubuntu"
  apt-get -y update
  apt-get -y upgrade
}

#------------------------------------------------------------
# Main
#------------------------------------------------------------

initialize
configure_timezone $TIMEZONE
display_message 'Changing root password:'
passwd # Change root passwd
create_user $USERNAME $PUBLIC_KEY_URL
secure_ssh
update_ubuntu
apt_get_packages
install_ruby $RUBY_SOURCE
install_rails $RAILS_VERSION
install_passenger
install_gems
install_tclink $TCLINK_SOURCE
epilogue
