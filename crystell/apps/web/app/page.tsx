const services = [
  { name: "Web", port: 3000 },
  { name: "API", port: 3001 },
  { name: "AI", port: 8000 },
];

export default function HomePage() {
  return (
    <main className="shell">
      <section className="card">
        <p className="eyebrow">CRYSTELL · PHASE 0</p>
        <h1>البنية الأساسية تعمل.</h1>
        <p className="muted">
          هذه شاشة تأسيسية مؤقتة للتحقق من تشغيل خدمات المنصة قبل بدء تصميم المنتج الفعلي.
        </p>
        <div className="grid">
          {services.map((service) => (
            <div className="service" key={service.name}>
              <strong>{service.name}</strong>
              <span>localhost:{service.port}</span>
            </div>
          ))}
        </div>
      </section>
    </main>
  );
}
