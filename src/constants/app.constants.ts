export const APP_CONFIG = {
  NAME: "Ahmet Egemen'in Köşesi",
  DESCRIPTION: 'Çocuklara özel güvenli aile medya platformu',
  MAX_PIN_ATTEMPTS: 5,
  PIN_LOCKOUT_MS: 900000, // 15 minutes (database authoritative policy)
} as const;
