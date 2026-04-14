# Mimir Cardinality Analyse – Prompt für Agent (Tenant: anonymous)

## Ziel
Ermittle in Mimir die Labels/Label-Values mit der höchsten Time-Series-Cardinality, damit wir entscheiden können, welche Labels reduziert oder entfernt werden sollten.

## Wichtiger Kontext
- Mimir Tenant Header: `X-Scope-OrgID: anonymous`
- Mimir Basis-URL (Port-Forward): `http://127.0.0.1:8080/prometheus`
- Ergebnis soll in YAML gespeichert werden: `docs/cardinality-analysis.yaml`

## Copy/Paste Prompt für morgen

Du bist ein technischer Analyse-Agent. Führe eine kurze Cardinality-Analyse gegen Mimir durch und speichere das Ergebnis in `docs/cardinality-analysis.yaml`.

Rahmenbedingungen:
- Tenant Header ist zwingend: `X-Scope-OrgID: anonymous`
- Nutze die Mimir-HTTP-API über `http://127.0.0.1:8080/prometheus`
- Falls ein Endpoint nicht verfügbar ist (z. B. 404), nutze automatisch die nächstpassende Alternative und dokumentiere das unter `notes`.

Arbeitsablauf:
1. Prüfe API-Erreichbarkeit über `/api/v1/labels`.
2. Ermittle Top Label Names nach Series-Cardinality (bevorzugt Cardinality-Endpoint).
3. Ermittle für die Top-Kandidaten die Top Label Values nach Cardinality.
4. Ergänze 3–8 konkrete Empfehlungen (`drop`, `keep`, `review`) mit kurzer Begründung.
5. Speichere alles in YAML-Datei `docs/cardinality-analysis.yaml` gemäß Struktur unten.

YAML-Zielstruktur:
```yaml
analysis:
  generated_at: "<ISO-8601>"
  tenant: "anonymous"
  base_url: "http://127.0.0.1:8080/prometheus"
  source:
    cardinality_endpoint_available: true
    endpoints_used:
      - "/api/v1/labels"
      - "/api/v1/cardinality/label_names"
      - "/api/v1/cardinality/label_values"
  top_label_names:
    - label: "path"
      series_count: 0
    - label: "uri"
      series_count: 0
  top_label_values_by_label:
    path:
      - value: "/api/..."
        series_count: 0
    pod:
      - value: "example-pod-123"
        series_count: 0
  recommendations:
    - action: "drop"
      label: "path"
      reason: "Hohe Kardinalität durch ungebundene Werte"
    - action: "review"
      label: "pod"
      reason: "Churn-bedingte Kardinalität, abhängig vom Use Case"
  notes:
    - "Falls Endpoint X nicht verfügbar, Alternative Y verwendet"
```

Akzeptanzkriterien:
- YAML ist valide.
- `tenant` ist `anonymous`.
- `top_label_names` und mindestens ein Block in `top_label_values_by_label` sind befüllt.
- Empfehlungen sind konkret und umsetzbar.

## Optional: Schnellstart lokal
1. Port-Forward starten:
   - `kubectl -n mimir port-forward svc/mimir-gateway 8080:80`
2. Dann den Agent mit obigem Prompt ausführen.
