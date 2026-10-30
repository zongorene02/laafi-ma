import { useState } from "react";
import { NavLink, Outlet, useLocation } from "react-router-dom";
import { useAuth } from "../context/AuthContext";
import { navItemsFor, ROLE_LABELS } from "../lib/roles";

export default function Layout() {
  const { user, logout } = useAuth();
  const [menuOpen, setMenuOpen] = useState(false);
  const [lastPath, setLastPath] = useState<string | null>(null);
  const location = useLocation();
  const items = navItemsFor(user?.role);

  // Referme le menu mobile à chaque changement de page.
  if (location.pathname !== lastPath) {
    setLastPath(location.pathname);
    if (menuOpen) setMenuOpen(false);
  }

  const nav = (
    <nav aria-label="Navigation principale" className="mt-6 space-y-1">
      {items.map((item) => (
        <NavLink
          key={item.to}
          to={item.to}
          end={item.end}
          className={({ isActive }) =>
            `block rounded-lg px-3 py-2 text-sm font-medium transition ${
              isActive ? "bg-brand-50 text-brand-700" : "text-gray-600 hover:bg-gray-100"
            }`
          }
        >
          {item.label}
        </NavLink>
      ))}
      <a
        href="/public"
        target="_blank"
        rel="noreferrer"
        className="block rounded-lg px-3 py-2 text-sm font-medium text-gray-600 hover:bg-gray-100"
      >
        Statistiques publiques ↗
      </a>
    </nav>
  );

  const account = (
    <div className="border-t border-gray-100 pt-4">
      <p className="truncate text-sm font-medium text-gray-800">{user?.full_name || user?.email}</p>
      {user && <p className="text-xs text-gray-500">{ROLE_LABELS[user.role]}</p>}
      <button
        type="button"
        onClick={logout}
        className="mt-2 text-sm font-medium text-gray-500 transition hover:text-gray-800"
      >
        Se déconnecter
      </button>
    </div>
  );

  return (
    <div className="min-h-screen md:flex">
      {/* Barre supérieure mobile */}
      <header className="sticky top-0 z-20 flex items-center justify-between border-b border-gray-200 bg-white px-4 py-3 md:hidden">
        <div>
          <p className="font-bold text-gray-900">Laafi Ma</p>
          <p className="text-xs text-gray-500">Console</p>
        </div>
        <button
          type="button"
          onClick={() => setMenuOpen((open) => !open)}
          aria-expanded={menuOpen}
          aria-controls="mobile-menu"
          className="rounded-lg border border-gray-200 px-3 py-1.5 text-sm font-medium text-gray-700"
        >
          {menuOpen ? "Fermer" : "Menu"}
        </button>
      </header>
      {menuOpen && (
        <div id="mobile-menu" className="border-b border-gray-200 bg-white px-4 pb-4 md:hidden">
          {nav}
          <div className="mt-4">{account}</div>
        </div>
      )}

      <aside className="hidden w-64 shrink-0 flex-col justify-between border-r border-gray-200 bg-white p-6 md:sticky md:top-0 md:flex md:h-screen">
        <div className="overflow-y-auto">
          <p className="text-lg font-bold text-gray-900">Laafi Ma</p>
          <p className="text-xs text-gray-500">Console de gestion</p>
          {nav}
        </div>
        {account}
      </aside>

      <main className="min-w-0 flex-1 p-4 sm:p-6 lg:p-8">
        <Outlet />
      </main>
    </div>
  );
}
