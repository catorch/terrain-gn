import { describe, expect, it } from 'vitest';
import { whatsappHandoff } from './whatsapp.js';

const summary = { code: 'TGN-000042', locality: 'Kipé', prefecture: 'Ratoma', areaM2: 499.6, priceGnf: 150_000_000, verified: true, sellerPhone: '+224620123456' };

describe('whatsappHandoff', () => {
  it('builds a French wa.me link with the plot summary', () => {
    const { url, text } = whatsappHandoff(summary, 'fr');
    expect(url.startsWith('https://wa.me/224620123456?text=')).toBe(true);
    expect(decodeURIComponent(url.split('text=')[1]!)).toBe(text);
    expect(text).toContain('TGN-000042');
    expect(text).toContain('Kipé, Ratoma');
    expect(text.replace(/\s/g, ' ')).toContain('150 000 000 GNF');
    expect(text).toContain('500 m²');
    expect(text).toContain('Vérifié par un agent terrain');
    expect(text).not.toMatch(/[\u{1F000}-\u{1FFFF}\u{2600}-\u{27BF}]/u); // wa.me mangles emoji
  });

  it('builds an English message and omits the badge line for unverified plots', () => {
    const { text } = whatsappHandoff({ ...summary, verified: false }, 'en');
    expect(text).toContain("I'm interested in plot TGN-000042");
    expect(text).toContain('150,000,000 GNF');
    expect(text).not.toContain('Verified');
  });
});
