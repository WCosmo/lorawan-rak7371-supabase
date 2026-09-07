#!/usr/bin/env python3
"""
Bridge LoRaWAN (ChirpStack MQTT) → Supabase
Escuta uplinks do ChirpStack e insere no Supabase.
"""

import json
import os
import sys
from datetime import datetime

import paho.mqtt.client as mqtt
from dotenv import load_dotenv
from supabase import create_client

# Carrega variáveis do .env
load_dotenv()

# =============================================================================
# CONFIGURAÇÕES
# =============================================================================
SUPABASE_URL = os.getenv("SUPABASE_URL", "").strip()
SUPABASE_KEY = os.getenv("SUPABASE_KEY", "").strip()
MQTT_BROKER = os.getenv("MQTT_BROKER", "127.0.0.1").strip()
MQTT_PORT = int(os.getenv("MQTT_PORT", "1883"))
MQTT_TOPIC = os.getenv("MQTT_TOPIC", "application/+/device/+/event/up")

# Validações
if not SUPABASE_URL or not SUPABASE_KEY:
    print("[ERRO] SUPABASE_URL e SUPABASE_KEY são obrigatórios no .env")
    sys.exit(1)

# =============================================================================
# CLIENTE SUPABASE
# =============================================================================
supabase = create_client(SUPABASE_URL, SUPABASE_KEY)

# =============================================================================
# CALLBACKS MQTT
# =============================================================================
def on_connect(client, userdata, flags, rc):
    if rc == 0:
        print(f"[MQTT] Conectado em {MQTT_BROKER}:{MQTT_PORT}")
        client.subscribe(MQTT_TOPIC)
        print(f"[MQTT] Inscrito em: {MQTT_TOPIC}")
    else:
        print(f"[MQTT] Falha na conexão, código: {rc}")


def on_message(client, userdata, msg):
    try:
        payload = json.loads(msg.payload.decode())

        # Extrai informações do dispositivo
        device_info = payload.get("deviceInfo", {})
        device_eui = device_info.get("devEui", "unknown")
        device_name = device_info.get("deviceName", "Desconhecido")
        device_profile = device_info.get("deviceProfileName", "")

        # Dados decodificados (object) ou raw
        data = payload.get("object", {})
        raw_payload = payload.get("data", "")

        # Timestamp
        timestamp = payload.get("time", datetime.utcnow().isoformat())

        # Metadados do RX (primeiro gateway que recebeu)
        rx_info_list = payload.get("rxInfo", [])
        rx_info = rx_info_list[0] if rx_info_list else {}
        rssi = rx_info.get("rssi")
        snr = rx_info.get("snr")
        gateway_id = rx_info.get("gatewayId", "")
        location = rx_info.get("location", {})

        # TX info
        tx_info = payload.get("txInfo", {})
        frequency = tx_info.get("frequency")
        dr = tx_info.get("dr")

        # Monta o registro
        record = {
            "device_eui": device_eui,
            "device_name": device_name,
            "device_profile": device_profile,
            "data": data,
            "raw_payload": raw_payload,
            "received_at": timestamp,
            "rssi": rssi,
            "snr": snr,
            "gateway_id": gateway_id,
            "frequency": frequency,
            "data_rate": dr,
            "location": location,
        }

        # Remove campos None para manter o JSON limpo
        record = {k: v for k, v in record.items() if v is not None}

        # Insere no Supabase
        result = supabase.table("lorawan_data").insert(record).execute()
        print(f"[Supabase] ✓ {device_name} ({device_eui}) | {json.dumps(data, ensure_ascii=False)}")

    except Exception as e:
        print(f"[ERRO] Falha ao processar mensagem: {e}")


def on_disconnect(client, userdata, rc):
    if rc != 0:
        print(f"[MQTT] Desconectado inesperadamente (código {rc}). Tentando reconectar...")


# =============================================================================
# MAIN
# =============================================================================
if __name__ == "__main__":
    print("=" * 60)
    print(" Bridge LoRaWAN → Supabase")
    print("=" * 60)
    print(f" MQTT Broker:  {MQTT_BROKER}:{MQTT_PORT}")
    print(f" MQTT Tópico:  {MQTT_TOPIC}")
    print(f" Supabase URL: {SUPABASE_URL}")
    print("=" * 60)

    client = mqtt.Client()
    client.on_connect = on_connect
    client.on_message = on_message
    client.on_disconnect = on_disconnect

    try:
        client.connect(MQTT_BROKER, MQTT_PORT, 60)
        client.loop_forever()
    except KeyboardInterrupt:
        print("
[Bridge] Encerrado pelo usuário.")
        client.disconnect()
    except Exception as e:
        print(f"[ERRO] {e}")
        sys.exit(1)
