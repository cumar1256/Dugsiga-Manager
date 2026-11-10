(() => {
  const adminNav = document.querySelector('.topbar');
  const teacherSidebar = document.querySelector('.teacher-sidebar');
  const teacherMobileNav = document.querySelector('.teacher-menu-toggle');
  const navs = [adminNav, teacherSidebar, teacherMobileNav].filter(Boolean);
  if (!navs.length) return;

  let previousY = window.scrollY;
  let direction = 0;
  let distance = 0;

  const reveal = () => navs.forEach(nav => nav.classList.remove('nav-hidden'));
  const hide = () => navs.forEach(nav => {
    if ((nav === teacherSidebar || nav === teacherMobileNav) && teacherSidebar?.classList.contains('open')) return;
    nav.classList.add('nav-hidden');
  });
  const onScroll = () => {
    const y = Math.max(0, window.scrollY);
    const delta = y - previousY;
    previousY = y;

    if (y <= 12) {
      direction = 0;
      distance = 0;
      reveal();
    } else if (Math.abs(delta) >= 2) {
      const nextDirection = Math.sign(delta);
      distance = nextDirection === direction ? distance + Math.abs(delta) : Math.abs(delta);
      direction = nextDirection;
      if (distance >= 12) {
        if (direction > 0) hide();
        else reveal();
        distance = 0;
      }
    }
  };

  window.addEventListener('scroll', onScroll, { passive: true });
  window.addEventListener('pageshow', () => {
    previousY = window.scrollY;
    if (previousY <= 12) reveal();
  });
  window.addEventListener('keydown', e => {
    if (e.key === 'Home') reveal();
  });
})();
