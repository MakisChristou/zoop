import { useState, type ReactNode } from "react";
import Layout from "@theme/Layout";
import Link from "@docusaurus/Link";
import useBaseUrl from "@docusaurus/useBaseUrl";

const views = [
  {
    name: "Today",
    file: "today",
    caption: "Sleep, recovery and activity, together.",
    alt: "Zoop Today dashboard with sleep, recovery and load rings, weight history and daily steps. Synthetic sample data.",
  },
  {
    name: "Activity",
    file: "activity",
    caption: "A history of the work you put in.",
    alt: "Zoop Activity dashboard with a daily training heatmap, sport totals and recent workouts. Synthetic sample data.",
  },
  {
    name: "Goals",
    file: "goals",
    caption: "Follow your progress, week by week.",
    alt: "Zoop Goals dashboard with weight progress, a target and daily steps. Synthetic sample data.",
  },
];

function ProductPreview() {
  const [selected, setSelected] = useState(0);
  const view = views[selected];
  const desktop = useBaseUrl(`/img/${view.file}-1440.png`);
  const mobile = useBaseUrl(`/img/${view.file}-390.png`);
  return (
    <section className="product-preview" id="product" aria-label="Explore Zoop">
      <div className="preview-controls" aria-label="Dashboard previews">
        {views.map((item, i) => (
          <button
            type="button"
            key={item.file}
            aria-pressed={selected === i}
            aria-controls="product-image"
            onClick={() => setSelected(i)}
          >
            {item.name}
          </button>
        ))}
      </div>
      <figure>
        <div className="product-window" id="product-image">
          <picture>
            <source media="(max-width: 600px)" srcSet={mobile} />
            <img
              src={desktop}
              width="1440"
              height="1020"
              alt={view.alt}
              fetchPriority="high"
            />
          </picture>
        </div>
        <figcaption>
          <span aria-live="polite">{view.caption}</span>
          <span>Sample data</span>
        </figcaption>
      </figure>
    </section>
  );
}

export default function Home(): ReactNode {
  return (
    <Layout
      title="Your WHOOP. Your data."
      description="Collect recordings from your WHOOP, explore sleep, recovery, activity and weight, and keep your history on your own server."
    >
      <main className="home" id="main-content">
        <section className="home-hero">
          <h1>
            Your WHOOP.
            <br />
            <span>Your data.</span>
          </h1>
          <p className="hero-description">
            Understand your sleep, activity and progress.
            <br className="desktop-break" /> Keep the recordings behind every
            number.
          </p>
          <div className="hero-actions">
            <Link
              className="site-button site-button-primary"
              to="/docs/get-started"
            >
              Get started
            </Link>
            <a className="site-button site-button-secondary" href="#product">
              Explore the app
            </a>
          </div>
        </section>

        <ProductPreview />

        <section
          className="ownership section-wrap"
          aria-labelledby="ownership-title"
        >
          <div className="section-intro">
            <h2 id="ownership-title">Keep your history.</h2>
          </div>
          <div className="feature-grid">
            <article>
              <h3>See the pattern</h3>
              <p>
                Explore sleep, recovery, workouts and weight across days, weeks
                and months.
              </p>
            </article>
            <article>
              <h3>Keep the original</h3>
              <p>
                Store raw recordings on your server. Revisit them as Zoop’s
                analysis improves.
              </p>
            </article>
            <article>
              <h3>Choose what to share</h3>
              <p>
                Keep accounts private. Share selected charts through links you
                can revoke.
              </p>
            </article>
          </div>
        </section>

        <section
          className="getting-started section-wrap"
          aria-labelledby="start-title"
        >
          <div className="section-intro">
            <h2 id="start-title">Run it on your own server.</h2>
            <p>
              The iPhone collects your recordings. Your server stores and
              analyses them. Open the same data on your phone or in a browser.
            </p>
            <Link className="text-link" to="/docs/get-started">
              Follow the setup guide
            </Link>
          </div>
          <div className="requirements">
            <h3>What you’ll need</h3>
            <dl>
              <div>
                <dt>Band</dt>
                <dd>WHOOP 5.0 or MG</dd>
              </div>
              <div>
                <dt>Phone</dt>
                <dd>iPhone · iOS 26 or later</dd>
              </div>
              <div>
                <dt>Server</dt>
                <dd>Docker Compose</dd>
              </div>
            </dl>
            <p>
              The iPhone app is awaiting App Store approval.{" "}
              <Link to="/docs/iphone">iPhone setup.</Link>
            </p>
          </div>
        </section>
      </main>
    </Layout>
  );
}
