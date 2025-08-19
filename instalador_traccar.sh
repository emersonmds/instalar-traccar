#!/bin/bash
# Instalador Universal do Traccar
# By Emerson + ChatGPT 🚀

set -e

VERSAO="5.12"
INSTALL_DIR="/opt/traccar"
SERVICE_FILE="/etc/systemd/system/traccar.service"

echo "=========================================="
echo " 🚀 Instalador do Traccar v$VERSAO"
echo "=========================================="
echo ""
echo "Escolha o modo de instalação:"
echo "1) Instalação Padrão (IP direto, sem DNS)"
echo "2) Instalação Avançada (DNS + Nginx + HTTPS)"
read -p "Opção [1 ou 2]: " opcao

# --- Instala pacotes necessários ---
echo "📦 Instalando dependências..."
sudo apt update -y
sudo apt install -y wget unzip ufw nginx certbot python3-certbot-nginx default-jre

# --- Baixa e instala o Traccar ---
echo "📥 Baixando Traccar..."
cd /opt
sudo rm -rf traccar
sudo wget -q https://github.com/traccar/traccar/releases/download/v$VERSAO/traccar-other-$VERSAO.zip
sudo unzip -q traccar-other-$VERSAO.zip -d traccar
sudo rm traccar-other-$VERSAO.zip

# --- Configura permissões ---
sudo chmod +x $INSTALL_DIR/jre/bin/java || true

# --- Cria serviço systemd ---
echo "🛠️ Configurando serviço do Traccar..."
sudo bash -c "cat > $SERVICE_FILE" <<EOF
[Unit]
Description=Traccar GPS Tracking Server
After=network.target

[Service]
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/jre/bin/java -jar tracker-server.jar conf/tracker-server.xml
SuccessExitStatus=143
User=root
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable traccar
sudo systemctl restart traccar

# --- Libera firewall ---
echo "🔥 Configurando firewall..."
sudo ufw allow ssh
sudo ufw allow 8082/tcp
sudo ufw allow 5000:5150/tcp
sudo ufw allow 5000:5150/udp
sudo ufw --force enable

# --- Testa se o Traccar rodou ---
sleep 5
if ! pgrep -f "tracker-server.jar" > /dev/null; then
    echo "❌ O Traccar não iniciou. Tentando corrigir..."
    sudo chmod +x $INSTALL_DIR/jre/bin/java
    sudo systemctl restart traccar
fi

# --- Instalação Avançada (DNS + Nginx) ---
if [ "$opcao" == "2" ]; then
    read -p "👉 Digite seu domínio (ex: rastreio.seudominio.com): " DOMINIO

    echo "🌐 Configurando Nginx + SSL para $DOMINIO..."
    sudo bash -c "cat > /etc/nginx/sites-available/traccar.conf" <<EOF
server {
    listen 80;
    server_name $DOMINIO;

    location / {
        proxy_pass http://127.0.0.1:8082/;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

    sudo ln -sf /etc/nginx/sites-available/traccar.conf /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl restart nginx

    echo "🔒 Obtendo certificado SSL..."
    sudo certbot --nginx -d $DOMINIO --non-interactive --agree-tos -m seuemail@dominio.com

    echo "✅ Instalação concluída!"
    echo "🌍 Acesse: https://$DOMINIO"
else
    echo "✅ Instalação concluída!"
    IP=$(hostname -I | awk '{print $1}')
    echo "🌍 Acesse: http://$IP:8082"
fi

echo "📊 Para verificar status: sudo systemctl status traccar"

