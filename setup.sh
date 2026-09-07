#!/bin/bash
# =============================================================================
# Setup Interativo - LoRaWAN RAK7371 + ChirpStack + Supabase
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║           🌐  LoRaWAN RAK7371 + ChirpStack + Supabase               ║"
    echo "║                    Setup Interativo v1.0                             ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""
}

print_step() {
    echo -e "${BLUE}[PASSO $1/7]${NC} $2"
}

print_ok() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# =============================================================================
# PASSO 1: Verificar pré-requisitos
# =============================================================================
print_step 1 "Verificando pré-requisitos do sistema..."

MISSING=()

if ! command -v docker &> /dev/null; then
    MISSING+=("docker")
fi

if ! docker compose version &> /dev/null && ! docker-compose --version &> /dev/null; then
    MISSING+=("docker-compose-plugin")
fi

if ! command -v python3 &> /dev/null; then
    MISSING+=("python3")
fi

if ! command -v pip3 &> /dev/null && ! python3 -m pip --version &> /dev/null; then
    MISSING+=("python3-pip")
fi

if [ ${#MISSING[@]} -ne 0 ]; then
    print_error "Faltam os seguintes pacotes: ${MISSING[*]}"
    echo ""
    echo "Instale com:"
    echo "  sudo apt update"
    echo "  sudo apt install -y docker.io docker-compose-plugin python3 python3-pip python3-venv"
    echo "  sudo usermod -aG docker \$USER"
    echo "  newgrp docker"
    echo ""
    echo "Depois execute este script novamente."
    exit 1
fi

print_ok "Todos os pré-requisitos estão instalados."

# =============================================================================
# PASSO 2: Criar .env a partir do .env.example
# =============================================================================
print_step 2 "Configurando variáveis de ambiente..."

if [ -f ".env" ]; then
    echo ""
    read -p "O arquivo .env já existe. Deseja sobrescrever? (s/N): " overwrite
    if [[ ! "$overwrite" =~ ^[Ss]$ ]]; then
        print_warn "Mantendo .env existente. Pulando configuração."
    else
        cp .env.example .env
        print_ok ".env recriado do template."
    fi
else
    cp .env.example .env
    print_ok ".env criado a partir do template."
fi

# =============================================================================
# PASSO 3: Descobrir EUI do Gateway (RAK7371)
# =============================================================================
print_step 3 "Descobrindo EUI do gateway RAK7371..."

echo ""
echo "Conecte o RAK7371 via USB agora e pressione ENTER..."
read -r

echo "Escaneando concentrador..."
EUI=$(docker compose -f packet-forwarder/docker-compose.yml run --rm udp-packet-forwarder find_concentrator 2>/dev/null | grep -oE 'EUI: [0-9A-Fa-f]{16}' | head -1 | sed 's/EUI: //')

if [ -z "$EUI" ]; then
    print_warn "Não foi possível detectar o EUI automaticamente."
    echo "Possíveis causas:"
    echo "  • O RAK7371 não está conectado na USB"
    echo "  • Permissões insuficientes (tente: sudo usermod -aG docker \$USER)"
    echo ""
    read -p "Digite o Gateway EUI manualmente (16 caracteres hex): " EUI
else
    print_ok "Gateway EUI detectado: $EUI"
    read -p "Confirma este EUI? (S/n): " confirm_eui
    if [[ "$confirm_eui" =~ ^[Nn]$ ]]; then
        read -p "Digite o Gateway EUI correto (16 caracteres hex): " EUI
    fi
fi

# Normaliza EUI para maiúsculas
EUI=$(echo "$EUI" | tr '[:lower:]' '[:upper:]')
sed -i "s/GATEWAY_EUI=.*/GATEWAY_EUI=$EUI/" .env
print_ok "GATEWAY_EUI=$EUI salvo no .env"

# =============================================================================
# PASSO 4: Configurar Supabase
# =============================================================================
print_step 4 "Configurando Supabase..."

echo ""
echo "Abra o dashboard do Supabase e vá em:"
echo "  Project Settings → API"
echo ""

read -p "Cole a SUPABASE_URL (ex: https://abc123.supabase.co): " SUPABASE_URL
if [ -n "$SUPABASE_URL" ]; then
    sed -i "s|SUPABASE_URL=.*|SUPABASE_URL=$SUPABASE_URL|" .env
    print_ok "SUPABASE_URL configurada."
fi

echo ""
echo "Atenção: use a SERVICE ROLE KEY (não a anon key)!"
read -s -p "Cole a SUPABASE_KEY (service_role): " SUPABASE_KEY
echo ""
if [ -n "$SUPABASE_KEY" ]; then
    sed -i "s|SUPABASE_KEY=.*|SUPABASE_KEY=$SUPABASE_KEY|" .env
    print_ok "SUPABASE_KEY configurada."
fi

# =============================================================================
# PASSO 5: Gerar secret do ChirpStack
# =============================================================================
print_step 5 "Gerando secret do ChirpStack..."

if command -v openssl &> /dev/null; then
    SECRET=$(openssl rand -base64 32)
    sed -i "s|CHIRPSTACK_SECRET=.*|CHIRPSTACK_SECRET=$SECRET|" .env
    print_ok "CHIRPSTACK_SECRET gerado automaticamente."
else
    print_warn "OpenSSL não encontrado. Deixe o CHIRPSTACK_SECRET em branco — o Docker Compose gerará um na primeira execução."
fi

# =============================================================================
# PASSO 6: Subir os serviços
# =============================================================================
print_step 6 "Subindo ChirpStack (PostgreSQL + Redis + Mosquitto + ChirpStack)..."

docker compose up -d

print_ok "ChirpStack iniciado!"
print_ok "Acesse: http://localhost:8080 (login: admin / admin)"

# =============================================================================
# PASSO 7: Instruções finais
# =============================================================================
print_step 7 "Setup concluído!"

echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo "  ✅ CONFIGURAÇÃO FINALIZADA"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo -e "${GREEN}Próximos passos:${NC}"
echo ""
echo "  1. Cadastre o gateway no ChirpStack:"
echo "     http://localhost:8080 → Tenants → Gateways → Add"
echo "     Gateway EUI: $EUI"
echo ""
echo "  2. Crie a tabela no Supabase (SQL Editor):"
echo "     → Cole o conteúdo de bridge/supabase_schema.sql"
echo ""
echo "  3. Suba o Packet Forwarder:"
echo "     cd packet-forwarder && docker compose up -d"
echo ""
echo "  4. Rode o bridge Python (em outro terminal):"
echo "     cd bridge"
echo "     python3 -m venv venv && source venv/bin/activate"
echo "     pip install -r requirements.txt"
echo "     python bridge.py"
echo ""
echo "  5. Cadastre seu sensor em:"
echo "     http://localhost:8080 → Applications → Add device"
echo ""
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

read -p "Deseja abrir o ChirpStack no navegador agora? (S/n): " open_browser
if [[ ! "$open_browser" =~ ^[Nn]$ ]]; then
    if command -v xdg-open &> /dev/null; then
        xdg-open http://localhost:8080 &
    elif command -v open &> /dev/null; then
        open http://localhost:8080 &
    else
        print_warn "Não foi possível abrir o navegador automaticamente."
    fi
fi

echo ""
echo "Boa sorte com sua rede LoRaWAN! 🚀"
