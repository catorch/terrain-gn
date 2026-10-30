export const APP_NAME = 'Terrain GN';

export interface ContactSummary {
  code: string;
  locality: string;
  prefecture: string;
  areaM2: number;
  priceGnf: number;
  verified: boolean;
  sellerPhone: string;
}

/** Builds the pre-filled WhatsApp message from server-controlled fields only (R5.1). */
export function whatsappHandoff(summary: ContactSummary, locale: 'fr' | 'en') {
  const numbers = new Intl.NumberFormat(locale === 'fr' ? 'fr-GN' : 'en-GN', { maximumFractionDigits: 0 });
  const price = `${numbers.format(summary.priceGnf)} GNF`;
  const area = `${numbers.format(Math.round(summary.areaM2))} m²`;
  const place = `${summary.locality}, ${summary.prefecture}`;
  // Plain labels, no emoji: wa.me's redirect turns 4-byte characters into U+FFFD before WhatsApp sees them.
  const lines =
    locale === 'fr'
      ? [`Bonjour, je suis intéressé(e) par le terrain ${summary.code} vu sur ${APP_NAME}.`, `Lieu : ${place}`, `Superficie : ${area}`, `Prix : ${price}`, ...(summary.verified ? ['Vérifié par un agent terrain'] : []), 'Est-il toujours disponible ?']
      : [`Hello, I'm interested in plot ${summary.code} on ${APP_NAME}.`, `Location: ${place}`, `Area: ${area}`, `Price: ${price}`, ...(summary.verified ? ['Verified by a field agent'] : []), 'Is it still available?'];
  const text = lines.join('\n');
  return { text, url: `https://wa.me/${summary.sellerPhone.replace(/\D/g, '')}?text=${encodeURIComponent(text)}` };
}
