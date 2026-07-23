// ============================================================
// PADELROOKIES — Shop showroom (GSAP + ScrollTrigger)
// Solo para shop.html. Inclúyelo DESPUÉS de motion.js.
//
// Convierte cada .showroom-scene en una escena con scroll-scrub:
// según se hace scroll dentro de la escena, la foto del producto
// hace zoom hacia el punto de la marca (data-focus="x% y%") con un
// leve giro 3D, simulando una cámara que se acerca al logo desde
// distintas perspectivas. Un pie de foto cruza de "Vista completa"
// a "Detalle · Logo PR" a mitad de recorrido.
//
// Solo corre en escritorio (>900px) y con
// prefers-reduced-motion: no-preference; si no, el CSS deja las
// escenas visibles de forma estática (ver .showroom-sticky en
// styles.css @media max-width:900px).
// ============================================================

(function () {
  if (typeof gsap === 'undefined') return;

  gsap.registerPlugin(ScrollTrigger);

  const scenes = document.querySelectorAll('.showroom-scene');
  if (!scenes.length) return;

  const mm = gsap.matchMedia();

  mm.add(
    {
      isDesktop: '(min-width: 901px) and (prefers-reduced-motion: no-preference)'
    },
    (context) => {
      if (!context.conditions.isDesktop) return;

      scenes.forEach((scene) => {
        const img = scene.querySelector('.showroom-img');
        const vignette = scene.querySelector('.showroom-vignette');
        const captionA = scene.querySelector('[data-caption-a]');
        const captionB = scene.querySelector('[data-caption-b]');
        const copyItems = scene.querySelectorAll('.showroom-copy > *');
        if (!img) return;

        const [fx, fy] = (scene.dataset.focus || '50% 50%').split(' ');
        scene.style.setProperty('--focus-x', fx);
        scene.style.setProperty('--focus-y', fy);

        gsap.set(copyItems, { opacity: 0, y: 24 });

        const tl = gsap.timeline({
          scrollTrigger: {
            trigger: scene,
            start: 'top top',
            end: 'bottom bottom',
            scrub: 0.6
          }
        });

        tl.fromTo(
          img,
          { scale: 1, rotateY: -9, rotateX: 3, filter: 'saturate(0.9) brightness(0.95)' },
          { scale: 1.22, rotateY: -3, rotateX: 1, filter: 'saturate(0.95) brightness(1)', duration: 0.32, ease: 'none' },
          0
        )
          .to(img, { scale: 1.75, rotateY: 4, rotateX: -1, filter: 'saturate(1.05) brightness(1.02)', duration: 0.36, ease: 'none' }, 0.32)
          .to(img, { scale: 2.6, rotateY: 0, rotateX: 0, filter: 'saturate(1.1) brightness(1.05)', duration: 0.32, ease: 'none' }, 0.68)
          .to(copyItems, { opacity: 1, y: 0, stagger: 0.08, duration: 0.24, ease: 'none' }, 0.04)
          .to(vignette, { opacity: 0.85, duration: 0.5, ease: 'none' }, 0.4);

        if (captionA && captionB) {
          tl.to(captionA, { opacity: 0, duration: 0.12, ease: 'none' }, 0.56).to(
            captionB,
            { opacity: 1, duration: 0.12, ease: 'none' },
            0.56
          );
        }
      });

      return () => {
        // gsap.matchMedia limpia los ScrollTriggers de este contexto automáticamente
      };
    }
  );
})();
