#!/bin/bash
# Instalador Automático do Traccar (by Emerson & ChatGPT)
# Compatível com Ubuntu 20.04 / 22.04 / 24.04

# -------- VARIÁVEIS --------
TRACCAR_URL="https://github.com/traccar/traccar/releases/download/v5.12/traccar-linux-64-5.12.zip"
INSTALL_DIR="/opt/traccar"

# -------- FUNÇÕES --------
function instalar_dependencias() {
    echo "📦 Instalando dependências..."
    apt update -y
    apt upgrade -y
    apt install -y wget unzip openjdk-17-jre ufw
}

function baixar_traccar() {
    echo "⬇️ Baixando Traccar..."
    cd /tmp
    wget -O traccar.zip $TRACCAR_URL
    rm -rf $INSTALL_DIR
    unzip traccar.zip -d /opt/
    mv /opt/traccar-* $INSTALL_DIR
}

function configurar_systemd() {
    echo "⚙️ Configurando systemd..."
    cat > /etc/systemd/system/traccar.service <<EOL
[Unit]
Description=Traccar GPS Tracking Server
After=network.target

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/jre/bin/java -jar tracker-server.jar conf/tracker-server.xml
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOL

    systemctl daemon-reexec
    systemctl enable traccar
    systemctl restart traccar
}

function configurar_firewall() {
    echo "🔥 Configurando firewall UFW..."
    ufw allow ssh
    ufw allow 8082/tcp
    ufw allow 5000:5150/tcp
    ufw allow 5000:5150/udp
    ufw --force enable
    ufw reload
}

function verificar_status() {
    echo "✅ Verificando status do Traccar..."
    sleep 3
    systemctl status traccar --no-pager
    echo
    echo "🌍 Acesse seu Traccar pelo navegador:"
    echo "👉 http://$(hostname -I | awk '{print $1}'):8082"
}

# -------- EXECUÇÃO --------
clear
echo "🚀 Instalador Automático do Traccar"
echo "==================================="

instalar_dependencias
baixar_traccar
configurar_systemd
configurar_firewall
verificar_status
