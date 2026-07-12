// ============================================================
// PADELROOKIES — Sistema de motion (GSAP + ScrollTrigger)
// Inclúyelo AL FINAL del body, después de GSAP/ScrollTrigger/
// CustomEase (vía CDN):
//
//   <script src="https://cdn.jsdelivr.net/npm/gsap@3.12.5/dist/gsap.min.js"></script>
//   <script src="https://cdn.jsdelivr.net/npm/gsap@3.12.5/dist/ScrollTrigger.min.js"></script>
//   <script src="https://cdn.jsdelivr.net/npm/gsap@3.12.5/dist/CustomEase.min.js"></script>
//   ...
//   <script src="motion.js"></script>
//
// Utilidades reutilizables basadas en atributos data-*, pensadas
// para funcionar en CUALQUIER página sin JS específico:
//   data-reveal="up|down|left|right|scale"  → fade+translate al entrar en viewport
//   data-reveal-group                       → contenedor: aplica stagger a sus hijos con data-reveal
//   data-parallax="0.25"                    → desplaza el elemento a distinta velocidad al hacer scroll
//   data-magnetic                           → botón/enlace que "atrae" ligeramente hacia el cursor
//   data-spotlight                          → resplandor radial que sigue el cursor dentro del elemento
//   data-counter="1200"                     → cuenta desde 0 hasta el valor al entrar en viewport
//   data-reveal-lines                       → revela un titular línea a línea; cada línea visual
//                                             debe ir en su propio <span data-line>…</span>
//
// Si GSAP no está disponible (CDN bloqueado) o el usuario prefiere
// menos movimiento, este script no añade la clase `js-motion` y el
// CSS base (styles.css) deja todo el contenido visible por defecto.
// ============================================================

(function () {
  if (typeof gsap === 'undefined') return;

  gsap.registerPlugin(ScrollTrigger);
  if (typeof CustomEase !== 'undefined') {
    CustomEase.create('pr-ease', '0.65, 0, 0.35, 1');
  }
  const EASE = typeof CustomEase !== 'undefined' ? 'pr-ease' : 'power3.out';

  const mm = gsap.matchMedia();

  mm.add('(prefers-reduced-motion: no-preference)', () => {
    document.documentElement.classList.add('js-motion');
    initLineReveals();
    initReveals();
    initParallax();
    initMagnetic();
    initSpotlight();
    initCounters();
    initHero();
  });

  // Con reduced-motion no se añade `js-motion`: styles.css deja
  // [data-reveal] visible por defecto, así que no hace falta tocar nada aquí.

  function initLineReveals() {
    document.querySelectorAll('[data-reveal-lines]').forEach((block) => {
      const lines = block.querySelectorAll('[data-line]');
      if (!lines.length) return;

      // Envuelve el contenido de cada línea en un span interno animable
      const inners = [];
      lines.forEach((line) => {
        const inner = document.createElement('span');
        inner.className = 'line-inner';
        while (line.firstChild) inner.appendChild(line.firstChild);
        line.appendChild(inner);
        inners.push(inner);
      });

      const tween = gsap.fromTo(inners,
        { yPercent: 110, opacity: 0 },
        { yPercent: 0, opacity: 1, duration: 0.9, ease: EASE, stagger: 0.12, paused: true }
      );

      // Above the fold (hero): reproduce al cargar; si no, al entrar en viewport
      if (block.getBoundingClientRect().top < window.innerHeight * 0.9) {
        tween.delay(0.15).play();
      } else {
        ScrollTrigger.create({
          trigger: block,
          start: 'top 85%',
          once: true,
          onEnter: () => tween.play()
        });
      }
    });
  }

  function initReveals() {
    const handled = new Set();

    document.querySelectorAll('[data-reveal-group]').forEach((group) => {
      const items = Array.from(group.children).filter((el) => el.hasAttribute('data-reveal'));
      if (!items.length) return;
      items.forEach((el) => handled.add(el));
      ScrollTrigger.batch(items, {
        start: 'top 85%',
        once: true,
        onEnter: (batch) => {
          gsap.to(batch, {
            opacity: 1,
            x: 0,
            y: 0,
            scale: 1,
            duration: 0.7,
            ease: EASE,
            stagger: 0.12
          });
        }
      });
    });

    // Elementos [data-reveal] sueltos, sin data-reveal-group como padre directo
    document.querySelectorAll('[data-reveal]').forEach((el) => {
      if (handled.has(el)) return;
      ScrollTrigger.create({
        trigger: el,
        start: 'top 85%',
        once: true,
        onEnter: () => {
          gsap.to(el, { opacity: 1, x: 0, y: 0, scale: 1, duration: 0.7, ease: EASE });
        }
      });
    });
  }

  function initParallax() {
    document.querySelectorAll('[data-parallax]').forEach((el) => {
      const speed = parseFloat(el.dataset.parallax) || 0.15;
      gsap.to(el, {
        yPercent: speed * 100,
        ease: 'none',
        scrollTrigger: {
          trigger: el.closest('section, header, .hero') || el,
          start: 'top bottom',
          end: 'bottom top',
          scrub: true
        }
      });
    });
  }

  function initMagnetic() {
    document.querySelectorAll('[data-magnetic]').forEach((el) => {
      const xTo = gsap.quickTo(el, 'x', { duration: 0.4, ease: 'power3.out' });
      const yTo = gsap.quickTo(el, 'y', { duration: 0.4, ease: 'power3.out' });

      el.addEventListener('mousemove', (e) => {
        const rect = el.getBoundingClientRect();
        const relX = e.clientX - (rect.left + rect.width / 2);
        const relY = e.clientY - (rect.top + rect.height / 2);
        xTo(relX * 0.35);
        yTo(relY * 0.35);
      });
      el.addEventListener('mouseleave', () => {
        xTo(0);
        yTo(0);
      });
    });
  }

  function initSpotlight() {
    document.querySelectorAll('[data-spotlight]').forEach((el) => {
      el.addEventListener('mousemove', (e) => {
        const rect = el.getBoundingClientRect();
        el.style.setProperty('--mx', `${e.clientX - rect.left}px`);
        el.style.setProperty('--my', `${e.clientY - rect.top}px`);
      });
    });
  }

  function initCounters() {
    document.querySelectorAll('[data-counter]').forEach((el) => {
      const target = parseFloat(el.dataset.counter) || 0;
      const suffix = el.dataset.counterSuffix || '';
      const obj = { val: 0 };
      ScrollTrigger.create({
        trigger: el,
        start: 'top 90%',
        once: true,
        onEnter: () => {
          gsap.to(obj, {
            val: target,
            duration: 1.4,
            ease: EASE,
            onUpdate: () => {
              el.textContent = Math.round(obj.val) + suffix;
            }
          });
        }
      });
    });
  }

  function initHero() {
    const mesh = document.querySelector('.net-mesh');
    if (!mesh) return;

    // Dibujo progresivo de las líneas del net-mesh al cargar
    const lines = Array.from(mesh.querySelectorAll('.net-line line'));
    const limeLines = lines.filter((l) => l.closest('.net-line.lime'));
    const baseLines = lines.filter((l) => !l.closest('.net-line.lime'));
    const ordered = baseLines.concat(limeLines);

    ordered.forEach((line) => {
      const length = line.getTotalLength();
      line.style.strokeDasharray = length;
      line.style.strokeDashoffset = length;
    });

    gsap.to(ordered, {
      strokeDashoffset: 0,
      duration: 1.4,
      ease: 'power2.inOut',
      stagger: 0.03
    });

    // Parallax de ratón sobre el net-mesh, solo en el hero
    const heroEl = mesh.closest('.hero');
    if (heroEl && window.matchMedia('(pointer: fine)').matches) {
      const meshX = gsap.quickTo(mesh, 'x', { duration: 0.6, ease: 'power3.out' });
      const meshY = gsap.quickTo(mesh, 'y', { duration: 0.6, ease: 'power3.out' });

      heroEl.addEventListener('mousemove', (e) => {
        const rect = heroEl.getBoundingClientRect();
        const relX = (e.clientX - rect.left) / rect.width - 0.5;
        const relY = (e.clientY - rect.top) / rect.height - 0.5;
        meshX(relX * 14);
        meshY(relY * 14);
      });
      heroEl.addEventListener('mouseleave', () => {
        meshX(0);
        meshY(0);
      });
    }
  }
})();
