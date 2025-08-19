#!/bin/bash
set -e

echo "=========================================="
echo "     INSTALADOR TRACCAR - UBUNTU          "
echo "=========================================="

# Atualiza sistema
echo "[1/6] Atualizando pacotes..."
sudo apt update -y && sudo apt upgrade -y

# Dependências
echo "[2/6] Instalando dependências..."
sudo apt install -y wget unzip ufw curl

# Backup de instalação antiga
if [ -d "/opt/traccar" ]; then
    echo "[INFO] Traccar já existe, criando backup..."
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    sudo mv /opt/traccar "/opt/traccar-backup-$TIMESTAMP"
fi

# Baixar Traccar
echo "[3/6] Baixando Traccar..."
wget -q https://github.com/traccar/traccar/releases/latest/download/traccar-linux-64-latest.zip -O /tmp/traccar.zip

# Instalar
echo "[4/6] Instalando Traccar..."
sudo unzip -o /tmp/traccar.zip -d /opt/
cd /opt/traccar
sudo ./traccar.run

# Configurar Firewall
echo "[5/6] Configurando firewall (UFW)..."
sudo ufw allow ssh
sudo ufw allow 8082/tcp
sudo ufw allow 5000:5150/tcp
sudo ufw allow 5000:5150/udp
echo "y" | sudo ufw enable
sudo ufw reload

# Iniciar serviço
echo "[6/6] Ativando serviço do Traccar..."
sudo systemctl enable traccar
sudo systemctl restart traccar

# Conferir porta
sleep 5
if sudo ss -tulpn | grep -q ":8082"; then
    echo "✅ Traccar está rodando na porta 8082"
else
    echo "⚠️ Algo deu errado: Traccar não está escutando na 8082"
fi

# Perguntar sobre HTTPS/Nginx
echo ""
echo "Deseja configurar domínio + HTTPS (Nginx + Certbot)?"
echo "1) Não, quero só pelo IP (http://SEU_IP:8082)"
echo "2) Sim, quero usar domínio com HTTPS"
read -p "Escolha (1 ou 2): " choice

if [ "$choice" == "2" ]; then
    read -p "Digite o domínio (ex: rastreamento.com.br): " DOMAIN

    echo "[NGINX] Instalando Nginx e Certbot..."
    sudo apt install -y nginx certbot python3-certbot-nginx

    sudo tee /etc/nginx/sites-available/traccar > /dev/null <<EOF
server {
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:8082/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

    sudo ln -s /etc/nginx/sites-available/traccar /etc/nginx/sites-enabled/
    sudo nginx -t && sudo systemctl restart nginx

    echo "[NGINX] Gerando certificado SSL..."
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m admin@$DOMAIN

    echo "✅ Acesse seu Traccar em: https://$DOMAIN"
else
    echo "✅ Acesse seu Traccar em: http://SEU_IP:8082"
fi

echo "=========================================="
echo "      INSTALAÇÃO FINALIZADA!              "
echo "=========================================="
