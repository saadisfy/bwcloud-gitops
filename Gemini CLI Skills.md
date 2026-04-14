# Gemini CLI Skills â€“ Vollständiger Kompendium

**Version:** 2.0  
**Stand:** März 2026  
**Modelle:** Gemini 2.5 Pro, Gemini 3 Pro, Gemini 3 Flash  
**Sprache:** Deutsch  

---

## Inhaltsverzeichnis

1. [Übersicht & Kernkonzepte](#1-übersicht--kernkonzepte)
2. [Was sind Skills wirklich?](#2-was-sind-skills-wirklich)
3. [Die Architektur von Skills](#3-die-architektur-von-skills)
4. [Skill-Struktur und Komponenten](#4-skill-struktur-und-komponenten)
5. [Skill Discovery & Precedence](#5-skill-discovery--precedence)
6. [Wie Skills aktiviert werden](#6-wie-skills-aktiviert-werden)
7. [Skill Lifecycle](#7-skill-lifecycle)
8. [Eine Skill von Grund auf erstellen](#8-eine-skill-von-grund-auf-erstellen)
9. [Best Practices](#9-best-practices)
10. [Performance & Beispiele](#10-performance--beispiele)
11. [Häufig gestellte Fragen](#11-häufig-gestellte-fragen)

---

## 1. Übersicht & Kernkonzepte

### Problem: Das Kontextfenster-Dilemma

Bei normalen LLM-Agenten stößt man schnell auf ein Dilemma:

- **Kleine Kontexte:** Modelle "vergessen" Regeln und Best Practices, wenn der Kontext wächst
- **Große Kontexte:** Das gesamte Wissen muss immer geladen sein - Token-Verschwendung
- **Lazy-Agents:** Nach ~50K Tokens wird der Agent "träge" und folgt Anweisungen weniger präzise

**Beispiel:** Wenn du Gemini CLI 10 verschiedene Workflows (Kubernetes, Observability, GitOps, etc.) beibringst, beginnt der Agent nach dem 5. Workflow, Anweisungen zu ignorieren.

### Die Lösung: Skills

**Skills sind selbstständige Module mit spezialisiertem Wissen**, die der Agent **on-demand** aktiviert.

**Analogie:** Ein Arzt mit verschiedenen Fachbereichen
- Der Arzt (=Gemini Agent) ist die zentrale Intelligenz
- Jeder Fachbereich (=Skill) ist eine spezialisierte Expertise
- Der Arzt ruft den richtigen Fachbereich auf, wenn nötig
- Der Fachbereich bringt all sein Wissen mit sich

**Kerngedanke:** 
> "Nicht alles sofort laden. Nur das laden, was gerade relevant ist."

---

## 2. Was sind Skills wirklich?

### Formale Definition

Ein **Skill** (Agent Skill) ist:

> Ein **selbstständiges Verzeichnis** mit spezialisiertem Wissen, Workflows und Ressourcen, das der Gemini-Agent **automatisch entdeckt und bei Bedarf aktiviert**.

### Analogie: Skill vs. System Prompt vs. Memory

| Aspekt | System Prompt | Memory (GEMINI.md) | Skill |
|--------|---------------|-------------------|-------|
| **Persistenz** | Einmaliges Setup | Permanent im Kontext | Only when activated |
| **Umfang** | Allgemein (Agent-Persönlichkeit) | Breite Hintergrund-Infos | Spezialisiert |
| **Aktivierung** | Immer vorhanden | Immer vorhanden | Nur wenn relevant |
| **Token-Overhead** | Klein | Mittel-Groß | **Null, solange inaktiv** |
| **Best für** | Kernverhalten definieren | Allgemeines Kontext | Spezialisierte Aufgaben |

### Praktisches Beispiel

**Szenario:** Du bist ein DevOps-Engineer mit 3 Spezialgebieten.

```
Agent: "Saad, ich habe eine Anfrage"

Anfrage 1: "Debugge Kubernetes Pod-Crashes"
- Agent aktiviert: /skills/kubernetes-troubleshooting
- (Alle K8s-Befehle, Debugging-Workflows, Best Practices) geladen
- Beantwortet präzise mit K8s-Kontext

Anfrage 2: "Setup Grafana Mimir für 3 Cluster"
- Agent deaktiviert K8s-Skill
- Agent aktiviert: /skills/observability-setup
- (Mimir-Konfiguration, Richtlinien, Multi-Cluster-Patterns) geladen
- Beantwortet präzise mit Observability-Kontext

Anfrage 3: "Erstelle GitOps Pipeline"
- Agent deaktiviert Observability-Skill
- Agent aktiviert: /skills/gitops-workflows
- (ArgoCD, Kargo, Progressive Delivery) geladen
- Beantwortet präzise mit GitOps-Kontext
```

### Warum Skills besser als große System Prompts sind

**Ohne Skills:**
```
System Prompt (70KB):
- 15 Seiten Kubernetes Best Practices
- 15 Seiten Observability Konfiguration
- 15 Seiten GitOps Workflows
- 15 Seiten Security Richtlinien
- Total: 60KB Overhead **IMMER**
- Agent wird nach ~50K Tokens "lazy"
```

**Mit Skills:**
```
System Prompt: "Du bist ein DevOps Engineer" (500 bytes)
+ Skill-Metadaten: "Verfügbare Skills: kubernetes, observability, gitops"
- Total: ~2KB Overhead
- Agent aktiviert nur relevante Skill (z.B. 20KB für K8s)
- Bleibt konzentriert und präzise
```

---

## 3. Die Architektur von Skills

### Drei-Schichten Modell

```
â”Œ---------------------------------------------â”
|      AGENT (Gemini 2.5/3 Pro/Flash)         |
|  "Central Brain" - entscheidet & orchestriert|
â””--------------------------------------------â”|
                                             ||
    â”Œ--------------------------------------â” ||
    | SKILL DISCOVERY LAYER                | ||
    | (Progressive Disclosure)             | ||
    | - Nur Namen + Beschreibung geladen   | ||
    | - ~50 bytes pro Skill                | ||
    | - In System Prompt injiziert         | ||
    â””--------------------------------------â”˜ ||
              â†“                              ||
    â”Œ--------------------------------------â” ||
    | SKILL ACTIVATION DECISION            | ||
    | - Agent prüft: Passt diese Skill?    | ||
    | - Ja - Lade vollständige Instruktionen| ||
    | - Nein - Skill bleibt inaktiv        | ||
    â””--------------------------------------â”˜ ||
              â†“                              ||
    â”Œ--------------------------------------â” ||
    | ACTIVE SKILL CONTEXT                 | ||
    | - Volle SKILL.md geladen             | ||
    | - Assets (Scripts, Templates)        | ||
    | - Datei-Zugriff aktiviert            | ||
    | - ~20-50KB Overhead (nur wenn aktiv) | ||
    â””--------------------------------------â”˜ ||
              â†“                              ||
    â”Œ--------------------------------------â” ||
    | EXECUTION LAYER                      | ||
    | - Agent nutzt Skill-Anweisungen      | ||
    | - Kann Skill-Assets nutzen           | ||
    | - Folgt Workflow-Logik               | ||
    â””--------------------------------------â”˜ ||
â””--------------------------------------------â”˜|
â””---------------------------------------------â”˜
```

### Progressive Disclosure Konzept

Das Kern-Konzept ist **Progressive Disclosure**:

**Phase 1: Discovery (immer)**
```
Skill Name: "kubernetes-troubleshooting"
Skill Description: "Debug Kubernetes Cluster Issues"
Skill Metadata: 2 Tags, 1 Autor
- Total: ~50 bytes im System Prompt
```

**Phase 2: Activation (bei Bedarf)**
```
User fragt: "Warum crasht dieser Pod?"
-Agent erkennt: "Das ist ein Kubernetes-Problem"
-Agent aktiviert: kubernetes-troubleshooting Skill
-Volle SKILL.md (15KB) + Assets geladen
-Agent hat nun Zugriff auf:
  - kubectl Befehle
  - Debugging-Workflows
  - Common Issues & Lösungen
  - Helper-Scripts
```

**Phase 3: Context Loading (aktive Session)**
```
Während der Session bleibt die Skill aktiv
Agent kann:
- Auf alle Skill-Assets zugreifen
- Skill-Anweisungen prioritätsieren
- Weitere verwandte Befehle durchführen
-Neue Anfrage in anderer Domäne?
- Agent deaktiviert K8s-Skill
- Agent aktiviert relevante neue Skill
```

---

## 4. Skill-Struktur und Komponenten

### Verzeichnisstruktur

Eine minimale Skill:

```
my-skill/
â”œ-- SKILL.md                 # Kernbestandteil: Instruktionen
â””-- .skillrc.json            # Optional: Metadaten & Config
```

Eine umfassendere Skill:

```
my-skill/
â”œ-- SKILL.md                 # Instruktionen & Best Practices
â”œ-- .skillrc.json            # Metadaten
â”œ-- examples/                # Verwendungsbeispiele
|   â”œ-- example1.yaml        # Konkrete Konfiguration
|   â”œ-- example2.yaml        
|   â””-- README.md            # Erklärungen
â”œ-- templates/               # Wiederverwendbare Vorlagen
|   â”œ-- deployment.yaml      # Helm/K8s Template
|   â”œ-- config.example       # Konfigurationsvorlage
|   â””-- script-template.sh   # Shell-Script Template
â”œ-- helpers/                 # Hilfsskripte
|   â”œ-- troubleshoot.sh      # Debugging-Script
|   â”œ-- validate.sh          # Validierungsscript
|   â””-- deploy.sh            # Deployment-Helper
â””-- README.md                # Übersicht für Menschen
```

### Die SKILL.md â€“ Das Herzstück

Die `SKILL.md` Datei ist der **Kernel jeder Skill**. Sie entscheidet, ob die Skill gut oder schlecht funktioniert.

**Struktur einer SKILL.md:**

```markdown
# [SKILL NAME]
[Kurze 1-Zeile Beschreibung]

## Overview
[1-2 Absätze über die Domäne & den Nutzen]

## Skills & Capabilities
- Capability 1: [Was kann diese Skill?]
- Capability 2: [Konkreter Benefit]
- Capability 3: [Differenziation]

## When to Use This Skill
[Wann wird diese Skill aktiviert? Was sind Trigger-Phrasen?]

## Prerequisites
- [Abhängigkeiten & erforderliche Tools]
- [Notwendige Konfigurationen]

## Key Workflows
### Workflow 1: [Name]
1. [Schritt 1]
2. [Schritt 2]
3. [Schritt 3]
...

### Workflow 2: [Name]
1. [Schritt 1]
2. [Schritt 2]
...

## Configuration Examples
[Konkrete Beispiele mit Erklärung]

## Troubleshooting
Q: [Common Issue]
A: [Lösung]

## Best Practices
1. [Best Practice 1]
2. [Best Practice 2]
3. [Best Practice 3]

## Resources & Reference
- [Links zu Dokumentation]
- [Links zu Best-Practice Guides]
```

### Praktisches Beispiel: kubernetes-troubleshooting Skill

**SKILL.md Inhalt:**

```markdown
# Kubernetes Troubleshooting

Spezialisierte Skill für Debugging von Kubernetes Cluster-Problemen,
Pod-Crashes und Performance-Issues in Produktion.

## Overview

Diese Skill bietet strukturierte Debugging-Workflows für:
- Pod-Crashes und Restart Loops
- Resource-Contention & Node-Druck
- Networking-Probleme zwischen Pods
- Storage und PVC-Issues
- Service-Discovery Probleme

## Capabilities

- **Pod Analysis:** Schnelle Identifikation von Crash-Ursachen
- **Node Health Check:** Diagnose von Node-Problemen
- **Network Debugging:** Service-zu-Pod Kommunikation prüfen
- **Resource Analysis:** CPU/Memory Contention aufdecken
- **Log Analysis:** Strukturiertes Log-Parsing

## When to Use

Dieser Skill wird aktiviert bei Fragen wie:
- "Warum crasht der Pod immer wieder?"
- "Wie debugge ich ein Networking-Problem in K8s?"
- "Warum kann meine App keine Verbindung herstellen?"
- "Wie prüfe ich Ressourcen-Druck?"

## Prerequisites

- kubectl Zugriff auf Cluster
- KUBECONFIG konfiguriert
- Erlaubnis zum Abrufen von Pod-Logs

## Key Workflows

### Workflow 1: Pod Crash Analysis

1. **Prüfe Pod Status:**
   ```bash
   kubectl get pod <pod-name> -n <namespace> -o wide
   kubectl describe pod <pod-name> -n <namespace>
   ```

2. **Analysiere Restart Count & Events:**
   - Wenn Restart Count > 0: Pod crasht wiederholt
   - Prüfe Events auf "OOMKilled", "Evicted", etc.

3. **Hole relevante Logs:**
   ```bash
   kubectl logs <pod-name> -n <namespace> --all-containers=true --timestamps=true
   kubectl logs <pod-name> -n <namespace> --previous  # Previous crash logs
   ```

4. **Identifiziere Root Cause:**
   - OOMKilled - Memory Limit too low
   - CrashLoopBackOff - Application error
   - Pending - Resource constraints
   - ImagePullBackOff - Registry issue

### Workflow 2: Network Debugging

1. **Teste Pod-zu-Pod Kommunikation:**
   ```bash
   kubectl exec <source-pod> -n <namespace> -- curl <target-svc>:<port>
   kubectl exec <source-pod> -n <namespace> -- nslookup <target-svc>
   ```

2. **Prüfe NetworkPolicy:**
   ```bash
   kubectl get networkpolicies -n <namespace>
   kubectl describe networkpolicy <policy-name>
   ```

3. **Analysiere Service & Endpoints:**
   ```bash
   kubectl get svc <service-name> -n <namespace> -o wide
   kubectl get endpoints <service-name> -n <namespace>
   ```

## Configuration Examples

### Example 1: Quick Pod Health Check

```bash
#!/bin/bash
NS="${1:-default}"
for pod in $(kubectl get pods -n $NS -o name); do
    STATUS=$(kubectl get $pod -n $NS -o jsonpath='{.status.phase}')
    RESTARTS=$(kubectl get $pod -n $NS -o jsonpath='{.status.containerStatuses[0].restartCount}')
    echo "$pod: Status=$STATUS Restarts=$RESTARTS"
done
```

## Troubleshooting

**Q: `kubectl: command not found`**
A: kubectl ist nicht installiert oder PATH ist falsch. Installiere kubectl oder update PATH.

**Q: `Error: Unable to connect to the server`**
A: KUBECONFIG ist falsch oder Cluster ist nicht erreichbar.

**Q: Pod zeigt `Pending` statt `Running`**
A: Prüfe `kubectl describe node` â€“ wahrscheinlich nicht genug Ressourcen.

## Best Practices

1. **Immer den Pod beschreiben bevor man Logs prüft**
   - `kubectl describe pod` zeigt Events mit Timestamps
   - Events sind der schnellste Hinweis auf die Ursache

2. **Prüfe immer die Node-Ressourcen**
   - `kubectl top nodes` und `kubectl top pods`
   - Memory Pressure ist eine häufige K8s-Falle

3. **Logs in mehreren Blöcken abrufen**
   - `--tail=100` für große Log-Volumes
   - `--timestamps=true` für Timeline-Analyse

## Resources

- [Kubernetes Documentation: Troubleshoot Pods](https://kubernetes.io/docs/tasks/debug-application-cluster/debug-pod-replication-controller/)
- [Debugging Guide: Getting Help](https://kubernetes.io/docs/tasks/debug-application-cluster/debug-service/)
```

### Die .skillrc.json â€“ Metadaten

```json
{
  "name": "kubernetes-troubleshooting",
  "version": "1.0.0",
  "description": "Debug Kubernetes cluster issues and pod crashes",
  "author": "Saad Masood",
  "tags": ["kubernetes", "debugging", "operations"],
  "triggers": [
    "debug",
    "troubleshoot",
    "crash",
    "kubernetes",
    "pod",
    "cluster"
  ],
  "dependencies": [
    "kubectl",
    "kubeconfig"
  ],
  "minGeminiVersion": "2.5-pro",
  "enabled": true,
  "priority": 1,
  "assets": {
    "templates": "templates/",
    "helpers": "helpers/",
    "examples": "examples/"
  }
}
```

---

## 5. Skill Discovery & Precedence

### Die drei Discovery-Tiers

Gemini CLI sucht Skills in dieser Reihenfolge:

```
Tier 1: WORKSPACE SKILLS (Höchste Priorität)
â””- Standort: ./.agents/skills/
â””- Sichtbar: Nur für dieses Projekt
â””- Best für: Projekt-spezifische Skills
â””- Beispiel: ./payment-service-api/.agents/skills/

    -
Tier 2: USER SKILLS (Mittlere Priorität)
â””- Standort: ~/.gemini/skills/
â””- Sichtbar: Alle Projekte auf diesem Computer
â””- Best für: Persönliche / wiederkehrende Skills
â””- Beispiel: ~/.gemini/skills/kubernetes-troubleshooting

    -
Tier 3: EXTENSION SKILLS (Niedrigste Priorität)
â””- Standort: npm-Pakete mit Skills
â””- Sichtbar: Wenn Extension installiert
â””- Best für: Ã–ffentlich kuratierte Skills (Firebase, etc.)
â””- Beispiel: @google/firebase-skills
```

### Precedence Rules (Welche Skill gewinnt?)

Wenn die gleiche Skill in mehreren Tiers existiert:

```
REGEL 1: Höherer Tier gewinnt
â”œ- Workspace Skill "kubernetes" überschreibt User Skill "kubernetes"
â”œ- User Skill "kubernetes" überschreibt Extension Skill "kubernetes"
â””- Ermöglicht: "Meine Version ist spezifischer als die Standard-Version"

REGEL 2: Innerhalb eines Tiers: Erste Match gewinnt
â”œ- Name muss eindeutig sein
â”œ- .skillrc.json Priority kann beeinflussen
â””- Neueste Version gewinnt (via semantic versioning)
```

### Skill Discovery in der Praxis

Beim Starten von Gemini CLI:

```bash
$ gemini

[INFO] Discovering skills...
[INFO] Tier 1 (Workspace): 3 skills found
  â”œ- kubernetes-deploy
  â”œ- payment-api-debug
  â””- monitoring-setup
[INFO] Tier 2 (User): 8 skills found
  â”œ- kubernetes-troubleshooting
  â”œ- observability-setup
  â”œ- gitops-workflows
  â”œ- terraform-validation
  â”œ- aws-operations
  â”œ- gcp-platform
  â”œ- networking-debug
  â””- security-hardening
[INFO] Tier 3 (Extensions): 5 skills found
  â”œ- firebase-basics
  â”œ- firebase-hosting
  â”œ- vertex-ai-integration
  â”œ- vertex-ai-tuning
  â””- cloud-functions

[SUCCESS] Total 16 skills ready
[INFO] Available skills loaded into agent context
```

---

## 6. Wie Skills aktiviert werden

### Der Skill Activation Flow

```
USER INPUT
    |
    â””-- Gemini Agent liest System Prompt
        â”œ- Agent sieht: "Verfügbare Skills: [list]"
        â”œ- Agent liest: Skill-Beschreibungen (Discovery Phase)
        â””- Agent denkt: "Brauche ich eine Skill für diese Aufgabe?"
            |
            â”œ-- JA: Skill ist relevant
            |        |
            |        â””-- Agent nutzt MCP `activate_skill`
            |            â”œ- Volle SKILL.md geladen
            |            â”œ- Assets eingebunden
            |            â”œ- Datei-Zugriff aktiviert
            |            â””- Skill Context in History
            |
            â””-- NEIN: Skill ist nicht relevant
                      |
                      â””-- Agent antwortet ohne Skill
```

### Detaillierter Ablauf

**Beispiel: User fragt "Warum crasht mein Pod?"**

```
Step 1: USER INPUTS
$ gemini
> Warum crasht dieser Pod immer wieder?

Step 2: AGENT ANALYZES
Gemini Agent erhält System Prompt mit:
{
  "available_skills": [
    {
      "name": "kubernetes-troubleshooting",
      "description": "Debug Kubernetes cluster issues"
    },
    {
      "name": "observability-setup",
      "description": "Setup monitoring & observability"
    },
    ...
  ]
}

Step 3: AGENT REASONING
Agent denkt: "Der User fragt nach Pod-Crashes"
- Das passt zur "kubernetes-troubleshooting" Skill
- Ich sollte diese Skill aktivieren
- Dann kann ich präzise K8s-Debugging durchführen

Step 4: AGENT ACTIVATION REQUEST
Agent ruft internally: activate_skill("kubernetes-troubleshooting")

Step 5: SKILL LOADING
System lädt:
â”œ- ~/.gemini/skills/kubernetes-troubleshooting/SKILL.md (volle 15KB)
â”œ- ~/.gemini/skills/kubernetes-troubleshooting/helpers/*
â”œ- ~/.gemini/skills/kubernetes-troubleshooting/examples/*
â””- KUBECONFIG Zugriff für kubectl Befehle

Step 6: CONTEXT INJECTION
Agent kann jetzt auf folgendes zugreifen:
â”œ- Alle Workflows aus SKILL.md
â”œ- Helper-Scripts
â”œ- Beispiele
â”œ- kubectl Befehle
â””- Debugging Checklists

Step 7: RESPONSE
Agent antwortet mit voller Fachkompetenz
```

### Skill Deaktivierung

Eine Skill wird deaktiviert wenn:

1. **User wechselt Domäne**
2. **Session endet**
3. **Skill wird manuell disabled**

---

## 7. Skill Lifecycle

### Skill Zustände

```
DISCOVERED - ACTIVATING - ACTIVE - DEACTIVATING - INACTIVE
```

### Lifecycle Events

```
on_discover()    - Skill wird entdeckt
on_activate()    - SKILL.md vollständig geladen
on_active()      - Agent nutzt Skill Features
on_deactivate()  - Cleanup & Cache-Clear
on_error()       - Fehler beim Laden/Ausführen
```

---

## 8. Eine Skill von Grund auf erstellen

### Schritt 1: Verzeichnis-Struktur erstellen

```bash
mkdir -p ~/.gemini/skills/my-first-skill
cd ~/.gemini/skills/my-first-skill

touch SKILL.md
touch .skillrc.json

mkdir -p examples helpers templates
```

### Schritt 2: .skillrc.json schreiben

```json
{
  "name": "my-first-skill",
  "version": "1.0.0",
  "description": "My first test skill for learning",
  "author": "Your Name",
  "tags": ["learning", "test", "first-skill"],
  "triggers": ["my skill", "test skill", "first"],
  "minGeminiVersion": "2.5-pro",
  "enabled": true,
  "priority": 1
}
```

### Schritt 3: SKILL.md schreiben

Siehe Beispiel in Kapitel 4.

### Schritt 4: Testen

```bash
gemini

# Im CLI:
> List available skills
> Teach me about skills
> @my-first-skill
```

### Schritt 5: Erweitern mit Assets

```bash
# Helper-Script hinzufügen
cat > helpers/validate-skill.sh << 'EOF'
#!/bin/bash
echo "Validating skill structure..."
[ -f "SKILL.md" ] && echo "âœ“ SKILL.md exists"
[ -f ".skillrc.json" ] && echo "âœ“ .skillrc.json exists"
[ -d "examples" ] && echo "âœ“ Examples directory exists"
EOF

chmod +x helpers/validate-skill.sh
```

---

## 9. Best Practices

### DO's âœ…

1. **Keep Skills Focused**
   - One skill per domain
   - "kubernetes-troubleshooting" (spezifisch)

2. **Write Clear SKILL.md**
   - Konkrete Workflows
   - Echte Code-Beispiele
   - Troubleshooting Section

3. **Include Examples**
   - Arbeitsbeispiele
   - YAML/Config-Snippets
   - Shell-Befehle

4. **Version Your Skills**
   - Semantic Versioning (1.0.0)
   - Update Version in .skillrc.json

5. **Organize Assets**
   - /examples - Verwendungsbeispiele
   - /templates - Wiederverwendbare Vorlagen
   - /helpers - Utility-Scripts

### DON'Ts âŒ

1. **DON'T: Duplicate Workflows**
2. **DON'T: Create Mega-Skills** (>100KB SKILL.md)
3. **DON'T: Assume Prior Context** (Skills sind stateless)
4. **DON'T: Hard-code Credentials** (nutze ENV-Variablen)
5. **DON'T: Forget Dependencies** (dokumentiere erforderliche Tools)

---

## 10. Performance & Beispiele

### Performance Messungen (Gemini 2.5 Pro vs 3.1 Pro)

| Modell | Ohne Skill | Mit Skill | Verbesserung |
|--------|-----------|-----------|-------------|
| Gemini 2.5 Pro | ~28% | ~42% | +50% |
| Gemini 3.0 Pro | 6.8% | ~85% | +1150% |
| Gemini 3.1 Pro | 28% | **96%** | **+243%** |
| Gemini 3.1 Flash | ~87% | **99%** | +14% |

**Erkenntnisse:**
- Neue Modelle mit Reasoning: Skills sind ein **Game Changer**
- Gemini 3.1 Pro: Fast perfekt mit Skills (96%)

### Praktisches Beispiel: DevOps Workflow

**Mit Skills:**
```
System Prompt (2KB):
  - "DevOps Agent with access to 15 skills"

User: "Setup Mimir for 3 clusters"
Agent: "Ich erkenne das als Observability-Setup"
- Aktiviere: observability-setup Skill
- Context: Mimir + Grafana + Tenant-Setup
- Agent bleibt präzise & fokussiert

Result: ~95% Success Rate
```

---

## 11. Häufig gestellte Fragen

### F: Wie unterscheiden sich Skills von System Prompts?

**A:** 

| Aspekt | System Prompt | Skill |
|--------|---------------|-------|
| **Größe** | Immer geladen | Nur bei Bedarf |
| **Fokus** | Agent-Verhalten | Task-Expertise |
| **Umfang** | 1 Prompt | Komplettes Verzeichnis |
| **Speicher** | ~20KB (immer) | ~50B (Discovery) + 20KB (aktiv) |

### F: Können mehrere Skills gleichzeitig aktiv sein?

**A:** Ja, aber kontrolliert!

```
User: "Deploy service mit observability"
- Beide Skills koexistieren für diese Aufgabe
- Nach Aufgabe: Beide deaktivieren
```

### F: Wie groß sollte eine SKILL.md sein?

**A:** 
- **Minimal:** 500 Zeilen (5-10KB)
- **Ideal:** 1000-2000 Zeilen (15-30KB)
- **Maximum:** 5000 Zeilen (50-100KB)

### F: Was passiert, wenn eine Skill nicht aktiviert wird?

**A:** Agent arbeitet ohne diese Skill (generische Antwort).

### F: Kann ich Skills deaktivieren?

**A:** Ja:
```bash
gemini --disable kubernetes-troubleshooting
# Oder in .skillrc.json: "enabled": false
```

### F: Wie aktualisiere ich eine Skill?

**A:**
```bash
nano ~/.gemini/skills/kubernetes-troubleshooting/SKILL.md
# Update version in .skillrc.json
gemini
```

### F: Können Skills Dateien schreiben?

**A:** Ja, mit Einschränkungen:
- Erlaubt: /tmp, Project-Verzeichnis
- Nicht erlaubt: System-Dateien, Dateien außerhalb Workspace

---

## Zusammenfassung

### Die Kernidee nochmal zusammengefasst

```
PROBLEM:
Große System Prompts - Agent wird lazy

LÃ–SUNG:
Skills = Modulare, on-demand Expertise

MECHANIK:
1. Discovery: Agent sieht Skill-Namen
2. Activation: Agent erkennt Relevanz
3. Loading: Volle Skill-Infos geladen
4. Execution: Agent nutzt Skill
5. Deactivation: Skill wird entladen

ERGEBNIS:
- Schärfer fokussierte Agents
- Bessere Ergebnisse (80-95% Success Rate)
- Effizientere Token-Nutzung
- Wiederverwendbare Module
```

### Dein nächster Schritt

1. **Erstelle deine erste Skill** (15 Min)
2. **Teste die Aktivierung** (5 Min)
3. **Erweitere mit Assets** (30 Min)
4. **Integriere in Workflow** (Ongoing)

---

**Ende des Kompendiums**

Für Fragen: https://geminicli.com/docs/cli/skills/