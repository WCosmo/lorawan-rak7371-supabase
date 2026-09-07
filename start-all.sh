#!/bin/bash
# =============================================================================
# start-all.sh - Inicia TODOS os serviços LoRaWAN de uma vez
# RAK7371 + ChirpStack + Bridge → Supabase
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# =============================================================================
# Funções utilitárias
# =============================================================================
print_header() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════════╗"
    echo "║           🚀  Iniciando Rede LoRaWAN Completa                       ║"
    echo "║           RAK7371 + ChirpStack + Supabase Bridge                     ║"
    echo "╚══════════════════════════════════════════════════════════════════════╝"
    echo ""
}

print_ok()   { echo -e "${GREEN}✓${NC} $1"; }
print_info() { echo -e "${BLUE}ℹ${NC} $1"; }
print_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error(){ echo -e "${RED}✗${NC} $1"; }

service_status() {
    local name=$1
    local container=$2
    if docker ps --format "{{.Names}}" | grep -q "^${container}$"; then
        echo -e "  ${GREEN}●${NC} $name (${CYAN}rodando${NC})"
        return 0
    else
        echo -e "  ${RED}●${NC} $name (${RED}parado${NC})"
        return 1
    fi
}

# =============================================================================
# Verifica .env
# =============================================================================
if [ ! -f ".env" ]; then
    print_error "Arquivo .env não encontrado!"
    echo ""
    echo "Execute primeiro o setup:"
    echo "  ./setup.sh"
    echo ""
    exit 1
fi

# Carrega variáveis do .env
set -a
source .env
set +a

print_header

# =============================================================================
# PASSO 1: ChirpStack (PostgreSQL + Redis + Mosquitto + ChirpStack)
# =============================================================================
print_info "[1/4] Verificando ChirpStack..."

if docker ps --format "{{.Names}}" | grep -q "^chirpstack$"; then
    print_ok "ChirpStack já está rodando."
else
    print_info "Subindo ChirpStack..."
    docker compose up -d
    print_ok "ChirpStack iniciado."
    echo "  → http://localhost:8080 (admin / admin)"
    echo "  → Aguardando serviços inicializarem..."
    sleep 5
fi

# =============================================================================
# PASSO 2: Packet Forwarder (RAK7371)
# =============================================================================
print_info "[2/4] Verificando Packet Forwarder (RAK7371)..."

cd packet-forwarder
if docker ps --format "{{.Names}}" | grep -q "^rak7371-gateway$"; then
    print_ok "Packet Forwarder já está rodando."
else
    print_info "Subindo Packet Forwarder..."
    docker compose up -d
    print_ok "Packet Forwarder iniciado."
    echo "  → Gateway EUI: ${GATEWAY_EUI:-AUTO}"
fi
cd "$SCRIPT_DIR"

# =============================================================================
# PASSO 3: Bridge Python (MQTT → Supabase)
# =============================================================================
print_info "[3/4] Verificando Bridge Python..."

cd bridge

# Verifica se o venv existe
if [ ! -d "venv" ]; then
    print_info "Criando ambiente virtual Python..."
    python3 -m venv venv
    print_ok "venv criado."
fi

# Ativa venv
source venv/bin/activate

# Verifica dependências
if ! python -c "import paho.mqtt, supabase, dotenv" 2>/dev/null; then
    print_info "Instalando dependências..."
    pip install -q -r requirements.txt
    print_ok "Dependências instaladas."
fi

# Verifica se o bridge já está rodando
BRIDGE_PID=$(pgrep -f "python bridge.py" || true)
if [ -n "$BRIDGE_PID" ]; then
    print_ok "Bridge Python já está rodando (PID: $BRIDGE_PID)."
else
    print_info "Iniciando Bridge Python em background..."
    nohup python bridge.py > bridge.log 2>&1 &
    sleep 2
    BRIDGE_PID=$(pgrep -f "python bridge.py" || true)
    if [ -n "$BRIDGE_PID" ]; then
        print_ok "Bridge Python iniciado (PID: $BRIDGE_PID)."
        echo "  → Logs: bridge/bridge.log"
    else
        print_error "Falha ao iniciar o Bridge. Verifique: bridge/bridge.log"
    fi
fi

cd "$SCRIPT_DIR"

# =============================================================================
# PASSO 4: Status final
# =============================================================================
print_info "[4/4] Resumo dos serviços:"
echo ""
echo "────────────────────────────────────────────────────────────────────────"
service_status "ChirpStack (API)"     "chirpstack"
service_status "PostgreSQL"           "chirpstack-postgres"
service_status "Redis"                "chirpstack-redis"
service_status "Mosquitto (MQTT)"     "chirpstack-mosquitto"
service_status "Gateway Bridge"       "chirpstack-gateway-bridge"
service_status "Packet Forwarder"     "rak7371-gateway"

# Bridge Python (processo local, não Docker)
if [ -n "$BRIDGE_PID" ]; then
    echo -e "  ${GREEN}●${NC} Bridge Python (${CYAN}rodando${NC}) PID: $BRIDGE_PID"
else
    echo -e "  ${RED}●${NC} Bridge Python (${RED}parado${NC})"
fi

echo "────────────────────────────────────────────────────────────────────────"
echo ""

# URLs e dicas
print_ok "Tudo pronto! Acesse:"
echo ""
echo "  🌐 ChirpStack UI:    http://localhost:8080"
echo "  📡 Gateway EUI:      ${GATEWAY_EUI:-(configurar no .env)}"
echo "  🗄️  Supabase URL:     ${SUPABASE_URL:-(configurar no .env)}"
echo ""
echo "  📋 Logs do Bridge:    tail -f bridge/bridge.log"
echo "  📋 Logs do Gateway:   docker compose -f packet-forwarder/docker-compose.yml logs -f"
echo ""

# Verifica se o gateway está cadastrado no ChirpStack (API interna)
if command -v curl &> /dev/null && [ -n "$GATEWAY_EUI" ] && [ "$GATEWAY_EUI" != "YOUR_GATEWAY_EUI_HERE" ]; then
    GATEWAY_STATUS=$(curl -s -o /dev/null -w "%{http_code}"         -H "Grpc-Metadata-Authorization: Bearer $(curl -s -X POST 'http://localhost:8080/api/internal/login'         -H 'Content-Type: application/json' -d '{"email":"admin","password":"admin"}' 2>/dev/null | grep -oP '"jwt":"\K[^"]+' || echo "")"         "http://localhost:8080/api/gateways/${GATEWAY_EUI}" 2>/dev/null || echo "000")

    if [ "$GATEWAY_STATUS" = "200" ]; then
        echo -e "  ${GREEN}✓${NC} Gateway ${GATEWAY_EUI} cadastrado no ChirpStack."
    elif [ "$GATEWAY_STATUS" = "404" ]; then
        print_warn "Gateway ${GATEWAY_EUI} ainda NÃO está cadastrado no ChirpStack."
        echo "     → http://localhost:8080 → Tenants → Gateways → Add gateway"
    fi
fi

echo ""
echo "Para parar todos os serviços, execute: ./stop-all.sh"
echo ""
