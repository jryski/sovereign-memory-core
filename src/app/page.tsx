const surfaces = [
  "Wiki pages",
  "Search",
  "Memories",
  "Hot topics",
  "Review queue",
  "Model chatroom",
];

export default function HomePage() {
  return (
    <main className="shell">
      <header className="hero">
        <p className="eyebrow">Personal knowledge layer</p>
        <h1>Personal Memory Wiki</h1>
        <p className="lede">
          A private, Wikipedia-style interface for the existing Supabase knowledge
          system. Supabase remains the source of truth.
        </p>
      </header>

      <section aria-labelledby="status-heading" className="panel">
        <h2 id="status-heading">Version 1 scope</h2>
        <ul>
          {surfaces.map((surface) => (
            <li key={surface}>{surface}</li>
          ))}
        </ul>
      </section>

      <section aria-labelledby="boundaries-heading" className="panel">
        <h2 id="boundaries-heading">Safety boundaries</h2>
        <p>
          Read-only by default, authenticated, RLS-preserving, and safe Markdown
          rendering. The model chatroom stays separate from ordinary wiki content.
        </p>
      </section>
    </main>
  );
}
