# LoRaWAN Gateway RAK7371 com Supabase

Projeto completo para rodar um gateway LoRaWAN **RAK7371** em Linux (Zorin/Ubuntu/Debian), com **ChirpStack** como Network Server e integração automática dos dados no **Supabase**.

---

## Estrutura do Projeto

```
lorawan-rak7371-supabase/
├── docker-compose.yml              # ChirpStack + PostgreSQL + Redis + Mosquitto
├── .env.example                    # Template de variáveis (copie para .env)
├── .gitignore
├── README.md
├── packet-forwarder/
│   └── docker-compose.yml          # Packet Forwarder do RAK7371
├── chirpstack/
│   └── configuration/chirpstack/
│       └── chirpstack.toml         # Configuração AU915 (Brasil)
└── bridge/
    ├── bridge.py                   # Script Python: MQTT → Supabase
    └── requirements.txt
```

---

## Quick Start

### 1. Clone o repositório

```bash
git clone https://github.com/SEU_USUARIO/lorawan-rak7371-supabase.git
cd lorawan-rak7371-supabase
```

### 2. Rode o setup interativo (recomendado)

```bash
./setup.sh
```

> O script detecta automaticamente o EUI do RAK7371, gera o secret do ChirpStack e configura tudo interativamente.

**Ou manualmente:**

```bash
cp .env.example .env
nano .env
```

Preencha **obrigatoriamente**:

| Variável | Onde encontrar |
|----------|---------------|
| `GATEWAY_EUI` | Execute: `docker compose -f packet-forwarder/docker-compose.yml run --rm udp-packet-forwarder find_concentrator` |
| `SUPABASE_URL` | Dashboard do Supabase → Project Settings → API → URL |
| `SUPABASE_KEY` | Dashboard do Supabase → Project Settings → API → `service_role` key |

> **ATENÇÃO:** Use a `service_role key`, não a `anon key`. Nunca exponha esta chave no frontend.

### 3. Crie a tabela no Supabase

No SQL Editor do Supabase, execute o conteúdo de `bridge/supabase_schema.sql` ou cole manualmente:

```sql
CREATE TABLE lorawan_data (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    device_eui TEXT NOT NULL,
    device_name TEXT,
    device_profile TEXT,
    data JSONB,
    raw_payload TEXT,
    received_at TIMESTAMPTZ,
    rssi INTEGER,
    snr NUMERIC,
    gateway_id TEXT,
    frequency BIGINT,
    data_rate INTEGER,
    location JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_lorawan_device_eui ON lorawan_data(device_eui);
CREATE INDEX idx_lorawan_received_at ON lorawan_data(received_at);
```

### 4. Suba o ChirpStack

```bash
docker compose up -d
```

Aguarde ~30 segundos e acesse: **http://localhost:8080**  
Login padrão: `admin` / `admin`

### 5. Suba o Packet Forwarder (conecte o RAK7371 via USB)

```bash
cd packet-forwarder
docker compose up -d
cd ..
```

### 6. Cadastre o Gateway no ChirpStack

1. Acesse **Tenants → ChirpStack → Gateways → Add gateway**
2. **Gateway ID (EUI):** cole o valor do `GATEWAY_EUI` do seu `.env`
3. **Name:** `RAK7371`
4. **Gateway Profile:** selecione o perfil da região AU915
5. Salve — o status deve ficar **"Online"**

### 7. Configure seu dispositivo (sensor)

1. **Device Profiles → Add device profile**
   - Name: `AU915-OTAA`
   - Region: `AU915`
   - MAC Version: `1.0.3` (ou conforme seu sensor)
   - OTAA: habilitado

2. **Applications → Add application**
   - Name: `Sensores`

3. Dentro da aplicação: **Add device**
   - Informe o **Device EUI**, **App Key** e selecione o perfil criado

### 8. Rode o Bridge (em outro terminal)

```bash
cd bridge
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
python bridge.py
```

A partir de agora, todo uplink do seu sensor será inserido automaticamente no Supabase

---

## Comandos úteis

| Ação | Comando |
|------|---------|
| Ver logs do gateway | `docker compose -f packet-forwarder/docker-compose.yml logs -f` |
| Ver logs do ChirpStack | `docker compose logs -f chirpstack` |
| Parar tudo | `docker compose down` |
| Parar packet forwarder | `docker compose -f packet-forwarder/docker-compose.yml down` |
| Descobrir EUI do gateway | `docker compose -f packet-forwarder/docker-compose.yml run --rm udp-packet-forwarder find_concentrator` |

---

## Solução de Problemas

### Gateway aparece "Offline"
- Verifique se o packet forwarder está rodando: `docker ps`
- Confirme se o EUI no ChirpStack é **exatamente igual** ao do `.env`
- Verifique os logs: `docker compose -f packet-forwarder/docker-compose.yml logs`

### Erro `sx1261` nos logs do packet forwarder
O RAK7371 **não possui** o rádio SX1261. Desative no `global_conf.json` do container ou ignore o warning se o concentrador iniciar normalmente.

### Dados não chegam no Supabase
- Verifique se o bridge está rodando e conectado ao MQTT
- Confirme se a `SUPABASE_KEY` é a `service_role key`
- Verifique se a tabela `lorawan_data` foi criada corretamente

### Payload chega em base64
Configure um **Codec** no Device Profile do ChirpStack (JavaScript ou Cayenne LPP) para decodificar o payload binário em JSON.

---

## Notas

- **Região:** Este projeto está configurado para **AU915** (Brasil/ANATEL). Se você estiver em outro país, edite o `chirpstack.toml` e o packet forwarder para a região correta.
- **Segurança:** O arquivo `.env` está no `.gitignore` e nunca deve ser commitado. Sempre use `.env.example` como template.
- **ChirpStack Secret:** Se deixar `CHIRPSTACK_SECRET` em branco no `.env`, o Docker Compose gera um automaticamente na primeira execução.

---

