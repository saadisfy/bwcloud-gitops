# Basepromoter Idea (Generated Values)

Ziel: Ein GitLab-Job erzeugt aus dev/int/prod die gemeinsamen Keys als
`base_values.yaml` und schreibt die reinen Diffs in `dev/int/prod`-Values.
Damit gibt es vier Value-Files, die spaeter per Kargo in die Deploy-Repo-Struktur
promoted werden.

## Zielbild

- **Input**: `apps/grafana/dev/values.yaml`, `int/values.yaml`, `prod/values.yaml`
- **Output (generated)**:
  - `base_values.yaml` (gemeinsame Keys)
  - `dev_values.yaml` (nur Diff)
  - `int_values.yaml` (nur Diff)
  - `prod_values.yaml` (nur Diff)

## GitLab Pipeline (Generator)

Trigger: `master`-Commits unter `apps/grafana/dev/**`.

Steps:
1. Script liest `dev/int/prod` Values.
2. Extrahiert gemeinsame Keys und erzeugt `base_values.yaml`.
3. Schreibt reduzierte `dev/int/prod` Values (nur Diff).
4. Commit in ein **separates Repo** oder **separaten Branch** (nicht `master`),
   damit Argo CD nicht direkt deployt.

## Kargo Integration

Warehouse subscribed auf das **generated Repo/Branch** (includePaths auf die
vier Files). Dadurch wird die Ausgabe des Jobs als Freight erkannt.

Promotion:
1. Kargo promoted von generated Repo/Branch in das **Deploy-Repo/Branch**.
2. Kargo schreibt die Files an die Zielpfade, z. B.:
   - `apps/grafana/base/values.generated.yaml` (aus `base_values.yaml`)
   - `apps/grafana/dev/values.yaml` (aus `dev_values.yaml`)
   - `apps/grafana/int/values.yaml` (aus `int_values.yaml`)
   - `apps/grafana/prod/values.yaml` (aus `prod_values.yaml`)

## Merge/Override-Regeln

- `base_values.yaml` wird **gemerged** mit `apps/grafana/base/values.yaml`
  (nicht ueberschreiben, weil dort weitere Werte liegen).
- `dev/int/prod` Values werden **ueberschrieben**, da sie nur die Diffs enthalten.

## Argo CD Trigger kontrollieren

Argo CD darf **nicht** auf den generator-Branch zeigen, damit kein automatisches
Deployment erfolgt. Erst die Kargo-Promotion in den Deploy-Branch soll den
Sync ausloesen.

## TODO

- Exakte Zielpfade und Namenskonventionen finalisieren.
- PromotionTask/Template definieren (copy/yaml-merge/yaml-update Reihenfolge).
