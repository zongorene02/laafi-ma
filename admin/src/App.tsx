import { lazy, Suspense } from "react";
import { BrowserRouter, HashRouter, Navigate, Route, Routes } from "react-router-dom";
import ProtectedRoute, { HomeRedirect, RequirePermission } from "./components/ProtectedRoute";
import { AuthProvider } from "./context/AuthContext";
import CapsuleEditorPage from "./pages/CapsuleEditorPage";
import CapsulesPage from "./pages/CapsulesPage";
import DangerSignsPage from "./pages/DangerSignsPage";
import DistrictsPage from "./pages/DistrictsPage";
import HelpServicesPage from "./pages/HelpServicesPage";
import KbEditorPage from "./pages/KbEditorPage";
import KbListPage from "./pages/KbListPage";
import LoginPage from "./pages/LoginPage";
import ServicesHealthPage from "./pages/ServicesHealthPage";
import UnansweredPage from "./pages/UnansweredPage";
import UsersPage from "./pages/UsersPage";

// Pages avec graphiques (recharts) chargées à la demande : la page publique
// est souvent ouverte sur mobile, avec une connexion lente.
const DashboardPage = lazy(() => import("./pages/DashboardPage"));
const PublicStatsPage = lazy(() => import("./pages/PublicStatsPage"));

function PageFallback() {
  return (
    <p role="status" className="py-10 text-center text-sm text-gray-500">
      Chargement…
    </p>
  );
}

// Un hébergeur statique (GitHub Pages) ne sait pas renvoyer index.html pour
// /kb ou /public : on y passe par des URL en # (VITE_HASH_ROUTER=true).
const Router = import.meta.env.VITE_HASH_ROUTER === "true" ? HashRouter : BrowserRouter;

export default function App() {
  return (
    <Router>
      <AuthProvider>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route
            path="/public"
            element={
              <Suspense fallback={<PageFallback />}>
                <PublicStatsPage />
              </Suspense>
            }
          />
          <Route element={<ProtectedRoute />}>
            <Route
              path="/"
              element={
                <HomeRedirect>
                  <Suspense fallback={<PageFallback />}>
                    <DashboardPage />
                  </Suspense>
                </HomeRedirect>
              }
            />
            <Route path="/kb" element={<RequirePermission permission="content"><KbListPage /></RequirePermission>} />
            <Route path="/kb/new" element={<RequirePermission permission="content"><KbEditorPage /></RequirePermission>} />
            <Route path="/kb/:id" element={<RequirePermission permission="content"><KbEditorPage /></RequirePermission>} />
            <Route path="/danger-signs" element={<RequirePermission permission="content"><DangerSignsPage /></RequirePermission>} />
            <Route path="/unanswered" element={<RequirePermission permission="content"><UnansweredPage /></RequirePermission>} />
            <Route path="/capsules" element={<RequirePermission permission="content"><CapsulesPage /></RequirePermission>} />
            <Route path="/capsules/new" element={<RequirePermission permission="content"><CapsuleEditorPage /></RequirePermission>} />
            <Route path="/capsules/:id" element={<RequirePermission permission="content"><CapsuleEditorPage /></RequirePermission>} />
            <Route path="/help-services" element={<RequirePermission permission="help_services"><HelpServicesPage /></RequirePermission>} />
            <Route path="/districts" element={<RequirePermission permission="districts"><DistrictsPage /></RequirePermission>} />
            <Route path="/users" element={<RequirePermission permission="users"><UsersPage /></RequirePermission>} />
            <Route path="/services" element={<RequirePermission permission="health"><ServicesHealthPage /></RequirePermission>} />
            <Route path="*" element={<Navigate to="/" replace />} />
          </Route>
        </Routes>
      </AuthProvider>
    </Router>
  );
}
