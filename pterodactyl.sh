#!/bin/bash
# Made by ajthemacboy

START_DIR=`pwd`

# Artisan Environment options
MYSQL_ROOT_PASS=""
DBHOST="localhost"
DBPORT="3306"
DBNAME="pterodb"
DBUSER="pterouser"
URL="http://panel.eyestra.in/"
TIMEZONE="America/New_York"
DRIVER="memcached"
SESSION_DRIVER="database"
QUEUE_DRIVER="database"

# Artisan Mail options
EMAIL_DRIVER="mail"
EMAIL_ORIGIN="admin@panel.eyestra.in"
EMAIL_NAME="Pterodactyl Panel"

RANDOMPASSWORD=`date +%s | sha256sum | base64 | head -c 24 ; echo`

# Set timezone - only needed for running in LXC
rm -f /etc/localtime
cp /usr/share/zoneinfo/$TIMEZONE /etc/localtime

# Add additional PHP packages.
add-apt-repository -y ppa:ondrej/php

# Update repositories list
apt update

# Install Dependencies
apt-get -y install php7.0 php7.0-cli php7.0-gd php7.0-mysql php7.0-pdo php7.0-mbstring php7.0-tokenizer php7.0-bcmath php7.0-xml php7.0-fpm php7.0-memcached php7.0-curl php7.0-zip mariadb-server nginx curl tar unzip git memcached

mkdir -p /var/www/html/pterodactyl
cd /var/www/html/pterodactyl

curl -Lo v0.6.0.tar.gz https://github.com/Pterodactyl/Panel/archive/v0.6.0.tar.gz
tar --strip-components=1 -xzvfv0.6.0.tar.gz
chmod -R 755 storage/* bootstrap/cache

curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

cp .env.example .env
composer install --no-dev
php artisan key:generate --force

echo "CREATE USER '$DBUSER'@'$DBHOST' IDENTIFIED BY '$RANDOMPASSWORD';" > /tmp/mysqlscript.txt
echo "CREATE DATABASE $DBNAME;" >> /tmp/mysqlscript.txt
echo "USE $DBNAME;" >> /tmp/mysqlscript.txt
echo "GRANT ALL PRIVILEGES ON *.* TO '$DBUSER'@'$DBHOST' WITH GRANT OPTION;" >> /tmp/mysqlscript.txt
echo "FLUSH PRIVILEGES;" >> /tmp/mysqlscript.txt

mysql --user=root --password=$MYSQL_ROOT_PASS < /tmp/mysqlscript.txt

rm /tmp/mysqlscript.txt

echo "Setting up env"
php artisan pterodactyl:env --dbhost="$DBHOST" --dbport="$DBPORT" --dbname="$DBNAME" --dbuser="$DBUSER" --dbpass="$RANDOMPASSWORD" --url="$URL" --driver="$DRIVER" --session-driver="$SESSION_DRIVER"  --queue-driver="$QUEUE_DRIVER" --timezone="$TIMEZONE"
echo "Setting up mail"
php artisan pterodactyl:mail --driver="$EMAIL_DRIVER" --email="$EMAIL_ORIGIN" --from-name="$EMAIL_NAME"
echo "Migrating DB"
php artisan migrate -n --force
echo "Seeding DB"
php artisan db:seed -n --force

chown -R www-data:www-data *

(crontab -l 2>/dev/null; echo "* * * * * php /var/www/html/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -

apt-get install -y supervisor
systemctl enable supervisor
service supervisor start

cp $START_DIR/pterodactyl-worker.conf /etc/supervisor/conf.d/

sudo supervisorctl reread
sudo supervisorctl update

sudo supervisorctl start pterodactyl-worker:*

cp $START_DIR/pterodactyl.conf /etc/nginx/sites-available/

ln -s /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/sites-enabled/pterodactyl.conf

service nginx restart




echo "Beginning daemon setup"

apt install -y linux-image-extra-$(uname -r) linux-image-extra-virtual

curl -sSL https://get.docker.com/ | sh
systemctl enable docker

curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -
apt install -y nodejs tar unzip make gcc g++ python-minimal

mkdir -p /srv/daemon /srv/daemon-data
cd /srv/daemon

curl -Lo v0.4.0.tar.gz https://github.com/Pterodactyl/Daemon/archive/v0.4.0.tar.gz
tar --strip-components=1 -xzvf v0.4.0.tar.gz

npm install --only=production

cp $START_DIR/wings.service /etc/systemd/system
systemctl daemon-reload
systemctl enable wings

cd /var/www/html/pterodactyl
echo "Please setup your user account"
php artisan pterodactyl:user

echo "All done! Here's the $DBNAME password, in case you need it: $RANDOMPASSWORD"
echo "Please setup a location and node in the panel on $URL, and copy the config to /srv/daemon/config/core.json."
echo "Then, run 'service wings start' to start the daemon."
