#!/bin/bash
# Instalador Traccar Completo - EmersonMDS

set -e

echo "======================================="
echo " 🚀 Instalador do Traccar GPS Tracking "
echo "======================================="

INSTALL_DIR="/opt/traccar"
SERVICE_FILE="/etc/systemd/system/traccar.service"

# Atualizar sistema
echo "🔄 Atualizando sistema..."
sudo apt update && sudo apt upgrade -y

# Perguntar versão do Traccar
read -p "👉 Informe a versão do Traccar (ex: 5.12) ou deixe vazio para baixar a última: " TRACCAR_VERSION

if [[ -z "$TRACCAR_VERSION" ]]; then
  echo "📡 Buscando última versão..."
  TRACCAR_VERSION=$(curl -s https://api.github.com/repos/traccar/traccar/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")' | sed 's/v//')
  echo "✅ Última versão encontrada: $TRACCAR_VERSION"
else
  echo "📌 Você escolheu a versão: $TRACCAR_VERSION"
fi

# Perguntar se vai usar DNS + Nginx
read -p "👉 Deseja configurar com DNS + Nginx? (s/n): " USE_DNS

if [[ "$USE_DNS" =~ ^[Ss]$ ]]; then
  read -p "Informe o domínio (ex: rastrear.seusite.com): " DOMAIN
  sudo apt install -y nginx certbot python3-certbot-nginx
fi

# Perguntar qual Banco de Dados
echo ""
echo "📦 Escolha o Banco de Dados:"
echo "1) H2 (padrão, interno)"
echo "2) MariaDB/MySQL"
read -p "Opção [1/2]: " DB_OPTION

DB_NAME="traccar"
DB_USER="traccar"
DB_PASS=""

if [[ "$DB_OPTION" == "2" ]]; then
  echo "🔧 Instalando MariaDB/MySQL..."
  sudo apt install -y mariadb-server

  read -p "👉 Nome do banco de dados [traccar]: " DB_NAME_INPUT
  DB_NAME=${DB_NAME_INPUT:-traccar}

  read -p "👉 Usuário do banco [traccar]: " DB_USER_INPUT
  DB_USER=${DB_USER_INPUT:-traccar}

  read -sp "👉 Senha do usuário do banco: " DB_PASS_INPUT
  echo ""
  DB_PASS=${DB_PASS_INPUT:-$(openssl rand -hex 12)}

  sudo mysql -u root -e "CREATE DATABASE IF NOT EXISTS ${DB_NAME} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
  sudo mysql -u root -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';"
  sudo mysql -u root -e "GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'localhost'; FLUSH PRIVILEGES;"

  echo "✅ Banco de dados ${DB_NAME} e usuário ${DB_USER} criados com sucesso."
  echo "📌 Senha: ${DB_PASS}"
fi

# Instalar dependências
echo "📥 Instalando dependências..."
sudo apt install -y wget unzip openjdk-17-jre ufw curl

# Baixar Traccar
echo "📦 Baixando Traccar ${TRACCAR_VERSION}..."
wget -O /tmp/traccar.zip "https://github.com/traccar/traccar/releases/download/v${TRACCAR_VERSION}/traccar-other-${TRACCAR_VERSION}.zip"

# Instalar Traccar
echo "📂 Instalando Traccar..."
sudo rm -rf $INSTALL_DIR
sudo unzip /tmp/traccar.zip -d /opt/
sudo mv /opt/traccar-* $INSTALL_DIR
rm -f /tmp/traccar.zip

# Configurar banco de dados se for MariaDB/MySQL
if [[ "$DB_OPTION" == "2" ]]; then
  echo "⚙️ Configurando banco no traccar.xml..."
  sudo sed -i '/<entry key="database.driver">/c\    <entry key="database.driver">com.mysql.cj.jdbc.Driver</entry>' $INSTALL_DIR/conf/traccar.xml
  sudo sed -i "/<entry key=\"database.url\">/c\    <entry key=\"database.url\">jdbc:mysql://localhost:3306/${DB_NAME}?serverTimezone=UTC&amp;useSSL=false</entry>" $INSTALL_DIR/conf/traccar.xml
  sudo sed -i "/<entry key=\"database.user\">/c\    <entry key=\"database.user\">${DB_USER}</entry>" $INSTALL_DIR/conf/traccar.xml
  sudo sed -i "/<entry key=\"database.password\">/c\    <entry key=\"database.password\">${DB_PASS}</entry>" $INSTALL_DIR/conf/traccar.xml
fi

# Criar serviço systemd
echo "⚙️ Criando serviço systemd..."
sudo bash -c "cat > $SERVICE_FILE" <<EOL
[Unit]
Description=Traccar GPS Tracking Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/java -jar $INSTALL_DIR/tracker-server.jar conf/traccar.xml
Restart=always
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOL

# Ativar serviço
sudo systemctl daemon-reload
sudo systemctl enable traccar
sudo systemctl start traccar

# Configurar firewall
echo "🔥 Configurando firewall..."
sudo ufw allow 8082/tcp
sudo ufw allow 5000:5150/tcp
sudo ufw allow 5000:5150/udp
sudo ufw --force enable

if [[ "$USE_DNS" =~ ^[Ss]$ ]]; then
  echo "🌐 Configurando Nginx..."
  sudo bash -c "cat > /etc/nginx/sites-available/traccar" <<NGINX
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8082/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
NGINX

  sudo ln -sf /etc/nginx/sites-available/traccar /etc/nginx/sites-enabled/
  sudo nginx -t && sudo systemctl restart nginx
  sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN
fi

echo "======================================="
echo "✅ Instalação concluída!"
echo "🌍 Acesse: http://<IP_DO_SERVIDOR>:8082"
if [[ "$USE_DNS" =~ ^[Ss]$ ]]; then
  echo "🌍 Ou: https://$DOMAIN"
fi
echo "======================================="
