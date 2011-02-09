#!/usr/bin/ruby

# cat > setup.rb
# paste contents of this file

class UbuntuSetup
  GEMS_COMMON        = %w(creditcard json)
  GEMS_POSTGRES      = %w(postgres)
  GEMS_RAILS         = %w(mislav-will_paginate passenger rails)
  NGINX_VERSION      = 'nginx-0.7.67'
  PACKAGES_COMMON    = %w(build-essential dnsutils git-core imagemagick
                          libopenssl-ruby libpcre3-dev libreadline5-dev
                          libssl-dev libxml2-dev locate rake rsync ruby1.8-dev
                          zlib1g-dev)
  PACKAGES_MEMCACHED = %w(memcached)
  PACKAGES_POSTFIX   = %w(postfix)
  PACKAGES_POSTGRES  = %w(libecpg-dev postgresql)
  PACKAGES_THTTPD    = %w(thttpd)
  RUBYGEMS_VERSION   = '1.3.7'
  THTTPD_PORT        = 8000
  UBUNTU_VERSION     = '10.04'

  def initialize options
    # Merge called options with defaults
    @options = {
      :home_dir  => '/home/badkins',
      :memcached => 16,
      :postfix   => true,
      :postgres  => true,
      :rails     => true,
      :thttpd    => false,
      :timezone  => 'US/Eastern'
    }.merge(options)
    @instructions = []
  end

  def run
    puts "Starting Setup for Ubuntu #{UBUNTU_VERSION}"
    # Export variable to prevent postfix (or other packages) from prompting
    # (doesn't seem to work for postfix though :(  )
    ENV['DEBIAN_FRONTEND'] = 'noninteractive'
    command("mkdir #{@options[:home_dir]}/www")
    command("mkdir #{@options[:home_dir]}/www/thttpd") if @options[:thttpd]
    command("mkdir #{@options[:home_dir]}/software")
    # Following line should be unnecessary if not running this w/ sudo
    # 8/14/10 command("chown -R badkins:badkins #{@options[:home_dir]}/www")
    configure_timezone
    install_packages
    install_from_source
    install_gems
    configure_dot_files
    print_instructions
  end

  private

  # Install a set of Ubuntu packages
  def apt_get_install packages
    command("sudo apt-get -y install #{packages.join(' ')}")
  end

  # Write to a file and echo command
  def cat path, data
    puts "Command: cat > #{path}"
    File.open(path, "w") do |file|
      file.print(data)
    end
  end

  # Change directory and echo path
  def cd path
    puts "Command: cd #{path}"
    Dir.chdir(path)
  end

  # Execute a shell command
  # Raise an exception if command is not successful.
  def command str
    puts "Command: #{str}"
    `#{str}`
    raise "Command failed: #{str}" unless $?.success?
  end

  def configure_dot_files
    # Used to configure .screenrc here, but that's in the bash script now
  end

  # Configure timezone for US/Eastern
  def configure_timezone
    cat("/etc/timezone", "#{@options[:timezone]}")
    command('sudo dpkg-reconfigure -f noninteractive tzdata')
  end

  # Assumes caller has created software directory
  def download_nginx
    cd("#{@options[:home_dir]}/software")
    command("wget http://nginx.org/download/#{NGINX_VERSION}.tar.gz")
    command("tar xzf #{NGINX_VERSION}.tar.gz")
    cd("#{NGINX_VERSION}/conf")
    command('cp nginx.conf orig.nginx.conf')
    cat("nginx.conf", FileData.nginx_conf)
  end

  # Install a set of Ruby gems per specified options
  def install_gems
    gems = GEMS_COMMON.dup
    gems.concat(GEMS_RAILS) if @options[:rails]
    gems.concat(GEMS_POSTGRES) if @options[:postgres]
    command("sudo gem sources -a http://gems.github.com")
    command("sudo gem install --no-rdoc --no-ri #{gems.join(' ')}")
  end

  #------------------------------------------------------------
  # Install nginx software
  #------------------------------------------------------------
  def install_nginx
    download_nginx

    if @options[:rails]
      # If :rails, the passenger install will build nginx
      @instructions << <<BJAEOF
Passenger installation:
sudo /usr/lib/ruby/gems/1.8/gems/passenger-2.2.15/bin/passenger-install-nginx-module
Hit enter
Choose option 2 for customization
Source is in #{@options[:home_dir]}/software/nginx-0.7.67
Choose /usr/local/nginx for the prefix (not just /usr/local)
Extra config params: --with-http_ssl_module
Hit enter
BJAEOF
    else
      cd("#{@options[:home_dir]}/software/#{NGINX_VERSION}")
      command("./configure --with-http_ssl_module")
      command("make")
      command("sudo make install")
    end

    # Create startup script
    cat("/etc/init.d/nginx", FileData.nginx_startup_script)
    cd('/etc/init.d')
    command("sudo chmod +x nginx")
    command("sudo update-rc.d nginx defaults")
  end

  #------------------------------------------------------------
  # Install rubygems
  #------------------------------------------------------------
  # Assumes caller has created software directory
  def install_rubygems
    cd("#{@options[:home_dir]}/software")
    command("wget http://rubyforge.org/frs/download.php/70696/rubygems-#{RUBYGEMS_VERSION}.tgz")
    command("tar xzf rubygems-#{RUBYGEMS_VERSION}.tgz")
    cd("rubygems-#{RUBYGEMS_VERSION}")
    command("sudo ruby setup.rb")
    command("sudo ln -s /usr/bin/gem1.8 /usr/local/bin/gem")
  end

  #------------------------------------------------------------
  # Install packages
  #------------------------------------------------------------
  def install_packages
    packages = PACKAGES_COMMON.dup

    if @options[:memcached]
      packages.concat(PACKAGES_MEMCACHED)
      @instructions << <<BJAEOF
Configure via:
sudo vim /etc/memcached.conf
BJAEOF
    end

    if @options[:postfix]
      @instructions << <<BJAEOF
Postfix configuration:
sudo apt-get install #{PACKAGES_POSTFIX.join(' ')}
Choose internet site
sudo vim /etc/postfix/main.cf
 * remove foo.com from mydestination to not deliver locally
 * change: myhostname = foo.com
 * change: inet_interfaces = loopback-only
sudo /etc/init.d/postfix restart
BJAEOF
    end

    if @options[:postgres]
      packages.concat(PACKAGES_POSTGRES)
      @instructions << <<BJAEOF
Configure postgresql:
sudo su
su postgres
psql
create role badkins superuser login;
BJAEOF
    end

    if @options[:thttpd]
      packages.concat(PACKAGES_THTTPD)
    end

    apt_get_install(packages)

    # Configure memcached
    if @options[:memcached]
      command("sudo sed -i -e '/^-m 64/c-m #{@options[:memcached]}' /etc/memcached.conf")
    end

    # Configure thttpd to execute Ruby cgi scripts
    if @options[:thttpd]
      cd('/etc/thttpd')
      command('cp thttpd.conf orig.thttpd.conf')
      cat('/etc/thttpd/thttpd.conf', FileData.thttpd_conf(@options[:home_dir]))
      command("sudo sed -i -e '/^ENABLED=/cENABLED=yes' /etc/default/thttpd")
    end
  end

  # Install software from source
  def install_from_source
    install_nginx
    install_rubygems
  end

  # Print manual instructions for things I couldn't automate
  def print_instructions
    @instructions.each_with_index {|instruction,idx|
      puts ''
      puts "Instruction #{idx+1}"
      puts "=============="
      puts instruction
    }
  end

end

module FileData
  module_function

  def nginx_conf
    return <<BJAEOF
worker_processes  6;

events {
    worker_connections  1024;
}

http {
    include            mime.types;
    default_type       application/octet-stream;
    sendfile           on;
    keepalive_timeout  65;
    gzip               on;
    gzip_proxied       any;
    gzip_vary          on;
    gzip_disable "MSIE [1-6]\.";
    gzip_http_version  1.1;
    gzip_min_length    10;
    gzip_comp_level    1;
    gzip_types         text/plain text/css application/x-javascript text/xml application/xml application/xml+rss text/javascript;

    server {
        listen       80;
        server_name  localhost;

        location / {
            root   html;
            index  index.html index.htm;
        }

        # redirect server error pages to the static page /50x.html
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
    }
}
BJAEOF
  end

  def nginx_startup_script
    return <<BJAEOF
#! /bin/sh

# Description: Startup script for nginx webserver on Debian. Place in /etc/init.d and
# run 'sudo update-rc.d nginx defaults', or use the appropriate command on your
# distro.
#
# Author: Ryan Norbauer <ryan.norbauer@gmail.com>
# Modified:     Geoffrey Grosenbach http://topfunky.com

set -e

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
DESC="nginx daemon"
NAME=nginx
DAEMON=/usr/local/nginx/sbin/$NAME
CONFIGFILE=/usr/local/nginx/conf/nginx.conf
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
BJAEOF
  end

  def thttpd_conf home_dir
    return <<BJAEOF
port=8000
dir=#{home_dir}/www/thttpd
nochroot
user=www-data
cgipat=**.rb
throttles=/etc/thttpd/throttle.conf
logfile=/var/log/thttpd.log
BJAEOF
  end
end

UbuntuSetup.new({ :memcached => 16,
                  :postfix   => true,
                  :postgres  => true,
                  :rails     => true,
                  :thttpd    => false }).run

# chmod +x setup.rb
# sudo ./setup.rb > results.txt
