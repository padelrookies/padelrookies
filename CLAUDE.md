# PadelRookies

Sitio web estático (HTML/CSS/JS plano, sin framework ni build step) para una marca/comunidad amateur de pádel. Tagline: "Play. Improve. Share." Idioma del sitio y de los comentarios de código: español.

## Stack y despliegue

- **Frontend**: HTML/CSS/JS vanilla. Sin bundler, sin npm/package.json. Cada página es un `.html` suelto que carga `styles.css` y los `.js` compartidos directamente por `<script src="...">`.
- **Hosting**: GitHub Pages es el definitivo desde 2026-07-22 (`https://padelrookies.github.io/padelrookies/`, sirviendo desde `master` / raíz, sin Actions workflow ni `CNAME` — así que cada push a `master` se despliega automáticamente y gratis). Netlify (`https://padelrookies.netlify.app`, carpeta local `.netlify/` de proyecto enlazado vía CLI) queda **abandonado/desactualizado** — sigue técnicamente en pie y respondiendo, pero no es donde se sigue trabajando; no confiar en él para ver el estado actual del sitio.
- **Backend**: Supabase (Postgres + Auth + Storage). Patrón de seguridad estricto: **cero escrituras directas del cliente** a tablas; todo pasa por funciones RPC `SECURITY DEFINER` con `search_path` fijo, y `REVOKE`/`GRANT` explícitos por rol (`anon` / `authenticated`).
- Prueba local recomendada: servir con un servidor local (p. ej. `http://localhost:8080`) en vez de abrir los `.html` con doble clic — evita comportamientos raros de `file://` que no se dan en Netlify.

## Estructura

- `index.html`, `marca.html` (historia de marca), `shop.html` + `producto-{short,camiseta,gorra,calcetines,munequeras}.html` (todo "Agotado", solo lista de espera). Short y Camiseta se separaron de un "Conjunto" único el 2026-07-23. Cada producto tiene ahora su propio vídeo/foto en `assets/products/` generados con Higgsfield; en las páginas de producto (no en las tarjetas del grid) hay una mini-galería manual: vídeo + 1-2 fotos, con un botón "siguiente" (`.gallery-next`) que va rotando — ver el script al final de cada `producto-*.html`. `producto-conjunto.html` y `assets/products/conjunto.png` quedaron huérfanos de esa separación (nadie enlaza a ellos ya); pendiente decidir si se borran.
- `comunidad.html` — grid de highlights de la comunidad ("puntazos"/vídeos).
- `unete.html` — alta, explica numeración de socios fundadores (0001–0100) y progresión de nivel.
- `login.html`, `perfil.html` (perfil + editor de tarjeta, pestañas Fondo/Acento/Efectos/Avatar/Reverso — la página más grande), `carnet.html` (vista pública de tarjeta por `?m=<numero_socio>`; el reverso solo lo ve el propio dueño o follows mutuos).
- JS compartido (incluir siempre en este orden):
  1. CDN `@supabase/supabase-js@2`
  2. [auth.js](auth.js) — cliente Supabase + estado de sesión/login en el header. Expone `SUPABASE_URL`, `SUPABASE_KEY`, `sb`.
  3. [card.js](card.js) — lógica de la tarjeta personalizable (fondos, acentos, efectos, marcos de avatar) + wrappers RPC: `purchaseItem`, `saveCardConfig`, `toggleFollow`, `getPublicCard`.
- [motion.js](motion.js) — sistema de animaciones al hacer scroll (ver convenciones abajo).
- SQL de Supabase, **aplicar en este orden**: `supabase_setup.sql` (tabla `profiles`) → `supabase_card.sql` (tarjeta, créditos, social) → `supabase_hardening.sql` (endurecimiento, aplicado en producción 2026-07-07) → `supabase_community.sql` (posts de comunidad, RPCs `get_community_feed`/`delete_community_post` con rate limit de 24h).

## Convenciones de diseño / motion.js

- Reveal on scroll vía `data-reveal` + GSAP: estado inicial (`opacity:0`) ya definido en CSS para evitar FOUC — GSAP solo anima *desde* ese estado, nunca lo crea. Si GSAP no carga (CDN bloqueado), el contenido debe seguir siendo visible por defecto.
- La clase `js-motion` se añade a `<html>` antes de pintar contenido revelable, justo para evitar el "flash" de contenido visible que luego salta al animarse.
- Trigger típico: `start: 'top 85%'`, `once: true` (no se re-anima al volver a hacer scroll — evita sensación "gimmick"). Dirección por defecto `up` (`translateY 24px → 0`).
- Respeta `prefers-reduced-motion` (rama `no-preference` en motion.js).
- Uso del color lima (acento de marca) es **deliberadamente restringido**: evitar botones grandes de fondo lima sólido fuera del CTA principal, líneas decorativas lima repetidas sin significado, e iconografía lima genérica.

## Notas prácticas / seguridad

- Al exportar imágenes para `assets/`, guardar explícitamente como JPEG cuando el original es una captura/PNG pesado sin transparencia real — evita duplicar peso (ej.: un PNG de 3.4MB sin necesidad).
- Supabase Auth, antes de abrir el registro a mucho tráfico: activar CAPTCHA (Cloudflare Turnstile) en Attack Protection, activar "Leaked password protection" en Passwords, mantener la confirmación por email activada.

## Estado de features

> Snapshot de una sesión anterior (2026-07-13) — verificar contra el código/UI actual antes de asumir que sigue vigente.

**Hecho**: alta/login/logout con confirmación de email, tarjeta de socio personalizable (6 fondos, 6 acentos, 3 efectos, 4 marcos de avatar), sistema de créditos con validación server-side (`purchase_item` RPC), subida de avatar a Supabase Storage, sistema de follow con desbloqueo de reverso de tarjeta por follow mutuo, badge de fundador automático para número de socio ≤100.

**Pendiente / marcado "Próximamente" en la UI**: checkout de la tienda (la lista de espera es solo client-side, no persiste en BD), subida de contenido de comunidad, progresión de nivel (Rookie → Advanced Rookie → Rookie Pro — está en el copy y sugerido en el esquema pero sin UI/lógica), calendario de eventos/torneos (solo copy de marketing), enlace de YouTube en el footer es un `#` muerto.
