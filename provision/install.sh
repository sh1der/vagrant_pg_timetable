#!/bin/bash

export DEBIAN_FRONTEND=noninteractive
version=4.6.1

################
## Postgresql ##
################

# Add repositories
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
echo "deb http://apt.postgresql.org/pub/repos/apt/ `lsb_release -cs`-pgdg main" |sudo tee /etc/apt/sources.list.d/pgdg.list

# Install postgresql
sudo apt update
sudo apt install -y postgresql-12 postgresql-contrib-12 postgresql-client-12

# Create user
echo "Creating scheduler user..."
sudo -u postgres bash -c "psql -c \"CREATE USER scheduler WITH PASSWORD 'supersecret';\""

# Create database
echo "Creating database..."
sudo -u postgres bash -c "psql -c 'CREATE DATABASE timetable;'"

# Granting privileges
echo "Granting privileges..."
sudo -u postgres bash -c 'psql -c "GRANT ALL PRIVILEGES ON DATABASE timetable TO scheduler;"'

# Create hba entry for user 'api'
sudo bash -c 'echo "host  timetable  scheduler  0.0.0.0/0  md5" >> /etc/postgresql/12/main/pg_hba.conf'

# Change listen address
sudo bash -c 'sed -i "s/^\(listen_addresses .*\)/# Commented out by custom script \1/" /etc/postgresql/12/main/postgresql.conf'
sudo bash -c "echo \"listen_addresses = '*'\" >> /etc/postgresql/12/main/postgresql.conf"

# Start pg cluster
sudo pg_ctlcluster 12 main start

# Ensure postgres is started and enabled
sudo systemctl enable postgresql
sudo systemctl restart postgresql

echo "DB Done"

#################
#  pg_timetable #
#################

# Download package
rm -rf /tmp/pg_timetable.deb
wget -O /tmp/pg_timetable.deb https://github.com/cybertec-postgresql/pg_timetable/releases/download/v${version}/pg_timetable_${version}_Linux_x86_64.deb

# Install package
sudo apt install /tmp/pg_timetable.deb

# Create user to run service
sudo adduser --system --no-create-home --group scheduler

# Create directory for init script
sudo mkdir -p /opt/pg_timetable

# Change permission on files
sudo find /opt/pg_timetable -type f -exec chmod 600 {} \;

# Change permission on directories
sudo find /opt/pg_timetable -type d -exec chmod 700 {} \;

# Create pg_timetable config file
sudo bash -c 'cat > /opt/pg_timetable/config.yml << EOF
clientname: worker001

# - PostgreSQL Connection Credentials -
connection:
  dbname: timetable
  host: localhost
  user: scheduler
  password: supersecret
  port: 5432
  sslmode: disable
  timeout: 45

# - Logging Settings -
logging:
  log-level: debug
  log-database-level: debug
  log-file: session.log
  log-file-format: text

# - Resource Settings -
resource:
  cron-workers: 10
  interval-workers: 6
  chain-timeout: 0
  task-timeout: 0

# - REST API Settings -
rest:
  rest-port: 8008

EOF'

# Create startup script (wait for db server to be ready)
sudo bash -c "cat > /opt/pg_timetable/start_pg_timetable.sh << EOF
#!/bin/bash
while ! nc -z localhost 5432
do
  sleep 1
done

bash -c 'pg_timetable --config=./config.yml'
EOF"

# Change owner of directory
sudo chown -R scheduler:scheduler /opt/pg_timetable

# Create service file
sudo bash -c "cat > /etc/systemd/system/pg_timetable.service << EOF
[Unit]
Description=pg_timetable service

[Service]
Type=simple
User=scheduler
Group=scheduler
WorkingDirectory=/opt/pg_timetable
ExecStart=/bin/bash './start_pg_timetable.sh'
Restart=always

[Install]
WantedBy=multi-user.target
EOF"

# Reload systemd daemon
sudo systemctl daemon-reload

# Enable unit
sudo systemctl enable pg_timetable
sudo systemctl restart pg_timetable

exit 0
