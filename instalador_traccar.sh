#!/bin/bash
# Instalador Automático do Traccar GPS Tracking
# Autor: Tonny Barros & Michaell Oliveira (refatorado com melhorias)
# Data: 2025-08-19
# Compatível: Ubuntu, Debian, CentOS, AlmaLinux, Fedora

set -e

### Função de Banner ###
banner() {
  clear
  echo -e "\n\033[1;34m████████╗██████╗  █████╗  ██████╗ ██████╗ █████╗ ██████╗\033[0m"
  echo -e "\033[1;34m╚══██╔══╝██╔══██╗██╔══██╗██╔════╝██╔════╝██╔══██╗██╔══██╗\033[0m"
  echo -e "\033[1;34m   ██║   ██████╔╝███████║██║     ██║     ███████║██████╔╝\033[0m"
  echo -e "\033[1;34m   ██║   ██╔══██╗██╔══██║██║     ██║     ██╔══██║██╔══██╗\033[0m"
  echo -e "\033[1;34m   ██║   ██║  ██║██║  ██║╚██████╗╚██████╗██║  ██║██║  ██║\033[0m"
  echo -e "\033[1;34m   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝╚═════╝╚═╝  ╚═╝ v4.0\033[0m"
  echo -e "\nInstalador Traccar otimizado 🚀"
  echo "Recomendado: servidor novo (limpo)."
  echo ""
}

### Coleta de informações do usuário ###
get_user_input() {
  read -p "Digite a versão do Traccar (ex: 6.6) ou deixe em branco para última: " TRACCAR_VERSION

  while [[ -z "$DB_TYPE" ]]; do
    read -p "Banco de dados (mysql/postgresql): " DB_TYPE
  done
  read -p "Nome do banco de dados: " DB_NAME
  read -p "Usuário do banco: " DB_USER
  read -sp "Senha do banco: " DB_PASS
  echo ""

  echo "Deseja configurar domínio + Nginx + SSL Let's Encrypt?"
  select OPT in "Sim" "Não (usar IP:8082)"; do
    case $OPT in
      "Sim") USE_DOMAIN=true; break;;
      "Não (usar IP:8082)") USE_DOMAIN=false; break;;
    esac
  done

  if [ "$USE_DOMAIN" = true ]; then
    read -p "Digite o domínio (ex: rastrear.meudominio.com): " DOMAIN
  fi

  TOTAL_MEMORY_MB=$(($(grep MemTotal /proc/meminfo | awk '{print $2}')/1024))
  echo "Memória total: ${TOTAL_MEMORY_MB}MB"
  read -p "Digite % de memória para Java (ex 60) ou deixe vazio para padrão: " MEMORY_PERCENT
}

### Detectar distro ###
detect_distro() {
  source /etc/os-release
  DISTRO=$ID
}

### Instalar dependências ###
install_dependencies() {
  if [[ "$DISTRO" =~ (ubuntu|debian) ]]; then
    apt update -y
    apt install -y unzip wget curl openjdk-17-jre nginx certbot python3-certbot-nginx
    [[ "$DB_TYPE" == "mysql" ]] && apt install -y mysql-server
    [[ "$DB_TYPE" == "postgresql" ]] && apt install -y postgresql postgresql-contrib
  elif [[ "$DISTRO" =~ (centos|almalinux|fedora) ]]; then
    dnf install -y unzip wget curl java-17-openjdk nginx certbot python3-certbot-nginx
    [[ "$DB_TYPE" == "mysql" ]] && dnf install -y mysql-server
    [[ "$DB_TYPE" == "postgresql" ]] && dnf install -y postgresql postgresql-server
  else
    echo "Distro não suportada: $DISTRO"
    exit 1
  fi
}

### Configurar banco ###
configure_database() {
  if [[ "$DB_TYPE" == "mysql" ]]; then
    mysql -uroot -e "CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
    mysql -uroot -e "CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';"
    mysql -uroot -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost'; FLUSH PRIVILEGES;"
  else
    sudo -u postgres psql -tc "SELECT 1 FROM pg_database WHERE datname = '$DB_NAME'" | grep -q 1 || sudo -u postgres createdb "$DB_NAME"
    sudo -u postgres psql -c "DO \$\$
    BEGIN
       IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '$DB_USER') THEN
          CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASS';
       END IF;
    END\$\$;"
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;"
  fi
}

### Baixar Traccar ###
download_traccar() {
  if [[ -z "$TRACCAR_VERSION" ]]; then
    TRACCAR_VERSION=$(curl -s https://api.github.com/repos/traccar/traccar/releases/latest | grep tag_name | cut -d '"' -f4)
  fi
  echo "Baixando Traccar $TRACCAR_VERSION..."
  wget -q https://github.com/traccar/traccar/releases/download/$TRACCAR_VERSION/traccar-linux-64-${TRACCAR_VERSION#v}.zip
  unzip -o traccar-linux-64-${TRACCAR_VERSION#v}.zip
  ./traccar.run
}

### Configurar Traccar ###
configure_traccar() {
  if [[ "$DB_TYPE" == "mysql" ]]; then
    DRIVER="com.mysql.cj.jdbc.Driver"
    URL="jdbc:mysql://localhost:3306/$DB_NAME?allowPublicKeyRetrieval=true&serverTimezone=UTC&useSSL=false"
  else
    DRIVER="org.postgresql.Driver"
    URL="jdbc:postgresql://localhost:5432/$DB_NAME"
  fi

  cat > /opt/traccar/conf/traccar.xml <<EOL
<?xml version="1.0" encoding="UTF-8"?>
<properties>
  <entry key='database.driver'>$DRIVER</entry>
  <entry key='database.url'>$URL</entry>
  <entry key='database.user'>$DB_USER</entry>
  <entry key='database.password'>$DB_PASS</entry>
  <entry key='web.url'>${USE_DOMAIN:+https://$DOMAIN}</entry>
</properties>
EOL
}

### Configurar Nginx + SSL ###
configure_nginx() {
  [ "$USE_DOMAIN" = false ] && return
  cat > /etc/nginx/sites-available/traccar <<EOL
server {
  listen 80;
  server_name $DOMAIN;
  location / {
    proxy_pass http://localhost:8082;
    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection 'upgrade';
    proxy_set_header Host \$host;
  }
}
EOL
  ln -sf /etc/nginx/sites-available/traccar /etc/nginx/sites-enabled/
  nginx -t && systemctl restart nginx
  certbot --nginx -d $DOMAIN --non-interactive --agree-tos --register-unsafely-without-email --redirect
}

### Configurar memória ###
configure_memory() {
  [ -z "$MEMORY_PERCENT" ] && return
  MAX_MEMORY_MB=$((TOTAL_MEMORY_MB * MEMORY_PERCENT / 100))
  JAVA_BIN=$(which java)
  sed -i "s|ExecStart=.*|ExecStart=$JAVA_BIN -Xmx${MAX_MEMORY_MB}m -jar tracker-server.jar conf/traccar.xml|" /etc/systemd/system/traccar.service
  systemctl daemon-reload
  systemctl restart traccar
}

### Comandos amigáveis ###
insert_shortcuts() {
  for CMD in start stop restart status; do
    echo "sudo systemctl $CMD traccar" > /usr/local/bin/traccar-$CMD
    chmod +x /usr/local/bin/traccar-$CMD
  done
  echo "tail -f /opt/traccar/logs/tracker-server.log" > /usr/local/bin/traccar-log
  chmod +x /usr/local/bin/traccar-log
  echo "grep -i \$1 /opt/traccar/logs/tracker-server.log" > /usr/local/bin/traccar-error
  chmod +x /usr/local/bin/traccar-error
}

### Finalização ###
finish_installation() {
  echo "✅ Traccar instalado com sucesso!"
  if [ "$USE_DOMAIN" = true ]; then
    echo "Acesse: https://$DOMAIN"
  else
    echo "Acesse: http://$(curl -s ifconfig.me):8082"
  fi
}

### Execução ###
banner
get_user_input
detect_distro
install_dependencies
configure_database
download_traccar
configure_traccar
configure_nginx
configure_memory
insert_shortcuts
finish_installation
