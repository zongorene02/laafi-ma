// Exécuté par `npm test` (node --test, suppression de types native de Node ≥ 22.18).
import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { can, canAccessConsole, consoleAccessDeniedMessage, homePathFor, navItemsFor } from "../src/lib/roles.ts";

describe("rôles", () => {
  it("seuls admin et validator accèdent à la console", () => {
    assert.equal(canAccessConsole("admin"), true);
    assert.equal(canAccessConsole("validator"), true);
    assert.equal(canAccessConsole("agent"), false);
    assert.equal(canAccessConsole("woman"), false);
    assert.equal(canAccessConsole(null), false);
  });

  it("le validateur gère et valide le contenu, sans pages d'administration", () => {
    assert.equal(can("validator", "content"), true);
    assert.equal(can("validator", "validate"), true);
    for (const p of ["dashboard", "help_services", "districts", "users", "health"] as const) {
      assert.equal(can("validator", p), false, p);
    }
  });

  it("l'admin a tout", () => {
    for (const p of ["dashboard", "content", "validate", "help_services", "districts", "users", "health"] as const) {
      assert.equal(can("admin", p), true, p);
    }
  });

  it("navigation filtrée par rôle", () => {
    assert.deepEqual(
      navItemsFor("validator").map((i) => i.to),
      ["/kb", "/danger-signs", "/unanswered", "/capsules"],
    );
    assert.equal(navItemsFor("admin").length, 9);
    assert.deepEqual(navItemsFor("agent"), []);
  });

  it("page d'accueil selon le rôle", () => {
    assert.equal(homePathFor("admin"), "/");
    assert.equal(homePathFor("validator"), "/kb");
    assert.equal(homePathFor("agent"), "/login");
  });

  it("message clair pour un agent", () => {
    assert.match(consoleAccessDeniedMessage("agent"), /Accès réservé/);
  });
});
