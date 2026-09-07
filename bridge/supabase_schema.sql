-- =============================================================================
-- Schema da tabela lorawan_data para Supabase
-- Cole isto no SQL Editor do seu projeto Supabase
-- =============================================================================

CREATE TABLE IF NOT EXISTS lorawan_data (
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

-- Índices para buscas rápidas
CREATE INDEX IF NOT EXISTS idx_lorawan_device_eui ON lorawan_data(device_eui);
CREATE INDEX IF NOT EXISTS idx_lorawan_received_at ON lorawan_data(received_at);
CREATE INDEX IF NOT EXISTS idx_lorawan_gateway_id ON lorawan_data(gateway_id);

-- Comentários para documentação no Supabase
COMMENT ON TABLE lorawan_data IS 'Dados recebidos de dispositivos LoRaWAN via ChirpStack';
COMMENT ON COLUMN lorawan_data.device_eui IS 'Identificador único do dispositivo (64 bits hex)';
COMMENT ON COLUMN lorawan_data.data IS 'Payload decodificado em JSON (via Codec do ChirpStack)';
COMMENT ON COLUMN lorawan_data.raw_payload IS 'Payload original em base64';
COMMENT ON COLUMN lorawan_data.rssi IS 'Received Signal Strength Indicator (dBm)';
COMMENT ON COLUMN lorawan_data.snr IS 'Signal-to-Noise Ratio (dB)';
