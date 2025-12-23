// Smooth header background transition on scroll
window.addEventListener('scroll', function() {
    const header = document.querySelector('header');
    if (window.scrollY > 100) {
        header.style.background = 'linear-gradient(180deg, rgba(12, 26, 62, 0.95) 0%, rgba(12, 26, 62, 0.9) 100%)';
        header.style.backdropFilter = 'blur(10px)';
    } else {
        header.style.background = 'linear-gradient(180deg, rgba(0,0,0,0.4) 0%, transparent 100%)';
        header.style.backdropFilter = 'none';
    }
});

// Language switcher
document.querySelectorAll('.lang-switch a').forEach(link => {
    link.addEventListener('click', function(e) {
        e.preventDefault();
        document.querySelectorAll('.lang-switch a').forEach(l => l.classList.remove('active-lang'));
        this.classList.add('active-lang');
    });
});

// Smooth scrolling for navigation links
document.querySelectorAll('nav a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function (e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            target.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
        }
    });
});

// CTA button smooth scrolling
document.querySelector('.cta-btn').addEventListener('click', function (e) {
    e.preventDefault();
    const target = document.querySelector(this.getAttribute('href'));
    if (target) {
        target.scrollIntoView({
            behavior: 'smooth',
            block: 'start'
        });
    }
});