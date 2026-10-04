/// <reference types="jest" />
import { urlEmail, urlTelefone, urlWhatsapp } from '../contactos';

test('ligações dos contactos', () => {
  expect(urlTelefone('+244 923 000 000')).toBe('tel:+244923000000');
  expect(urlWhatsapp('923 111 222')).toBe('https://wa.me/244923111222');
  expect(urlWhatsapp('+244923111222')).toBe('https://wa.me/244923111222');
  expect(urlEmail(' ola@mandabue.ao ')).toBe('mailto:ola@mandabue.ao');
});
