import React, { useEffect, useState } from "react";

// In-cluster: nginx (this container) reverse-proxies /api/* to the backend
// Service, so the browser only ever talks to this same origin. No CORS,
// no hardcoded backend host.
function App() {
  const [tasks, setTasks] = useState([]);
  const [title, setTitle] = useState("");
  const [error, setError] = useState(null);

  const load = () => {
    fetch("/api/tasks")
      .then((r) => {
        if (!r.ok) throw new Error(`backend returned ${r.status}`);
        return r.json();
      })
      .then(setTasks)
      .catch((e) => setError(e.message));
  };

  useEffect(load, []);

  const addTask = () => {
    fetch("/api/tasks", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ title, done: false }),
    })
      .then((r) => r.json())
      .then(() => {
        setTitle("");
        load();
      })
      .catch((e) => setError(e.message));
  };

  return (
    <div style={{ fontFamily: "sans-serif", maxWidth: 480, margin: "40px auto" }}>
      <h1>Demolabs Task App</h1>
      {error && <p style={{ color: "red" }}>Error talking to backend: {error}</p>}
      <input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="New task" />
      <button onClick={addTask}>Add</button>
      <ul>
        {tasks.map((t) => (
          <li key={t.id}>{t.title} {t.done ? "✅" : ""}</li>
        ))}
      </ul>
    </div>
  );
}

export default App;
