# antz — Valoración: sustituir POSIX scripts por ejecutable Go / reducción de tokens

> Documento de trabajo. Generado el 2026-09-13 a partir del análisis del repo
> `/home/edezacas/Projects/edezacas/antz` (versión 4.7.1, branch `master`).
> Propósito: retomar la decisión más adelante sin depender del contexto de la conversación.
> Revisado contra 4.7.1 (incluye `hardening-installsh` 4.7.0 y `style-rewrite` 4.7.1).

---

## 0. Nota de handoff (si este documento lo recibe otra sesión de IA)

- **Lee primero `AGENTS.md` del repo** (ley del proyecto: política de versionado,
  ley de no-commits, convención de runtime, estructura SPDD, gotchas). Este
  documento lo resume, pero AGENTS.md es la autoridad: si hay discrepancia,
  mandan AGENTS.md y las specs de `spdd/specs/` sobre este documento.
- **Trabaja dentro del repo** `/home/edezacas/Projects/edezacas/antz`: necesitas
  leer los ficheros referenciados (`install.sh`, `agents/prompts/orchestrator.prompt`,
  `agents/prompts/*`, `scripts/orchestration/*.sh`, `spdd/specs/posixsh.md`,
  `spdd/specs/flow-branch.md`, `spdd/specs/receipts.md`, `tests/`).
- **Los números de tokens (§2 y §5) son estimaciones**, no mediciones: valen para
  ordenar decisiones, no para prometer ahorros exactos.
- **Los scripts NO cambian**: `antz-flow.sh`, `antz-probe.sh`, `antz-skills.sh`
  se instalan tal cual; "byte-idénticos" (§5) es un objetivo de diseño del cambio,
  no una descripción de algo ya hecho.
- **Las decisiones abiertas (§6) deben resolverse antes de implementar**: no las
  inventes ni las asumas; el workflow SPDD tiene el mecanismo `OPEN_QUESTIONS.md`
  para bloquear el trabajo hasta que el usuario las responda.
- **Vía recomendada de desarrollo**: el propio workflow antz (`/antz` en Claude
  Code u OpenCode, rol orchestrator), con el cambio `deembed-orchestration-scripts`
  propuesto en §6.2. Alternativa válida: planificar fuera del workflow, pero
  respetando la estructura SPDD (specs .feature con ids, receipts, etc.).
- **Nada de esto está implementado todavía**: todo §5 es propuesta pendiente de
  especificar, no estado actual.

---

## 1. Pregunta original y objetivos

**¿Es buena idea sustituir los POSIX scripts por un ejecutable en Go?**

Objetivos declarados:

1. Código más mantenible y estructurado, más fácil de evolucionar
2. Reducir los prompts de los agentes antz que actualmente embeben scripts POSIX
3. Mejorar la performance (búsqueda de ficheros, git, etc.)
4. Mejorar la eficiencia en detección de branch, skills, ficheros para el context
5. Mejor aprovechamiento de la caché de los agentes (Claude Code, OpenCode, Pi)
6. Instalar/actualizar/borrar antz fácilmente

**Restricciones añadidas después**: uso principal Linux/macOS (Windows no importa).
Objetivos prioritarios: **2 y 5** (reducción drástica de tokens por sesión de
orquestación) — valorados **sin salir de POSIX**.

---

## 2. Estado actual del repo (hechos medidos)

| Elemento | Valor |
|---|---|
| Shell total | **1037 líneas** — `install.sh` (702), `antz-flow.sh` (135), `antz-probe.sh` (116), `antz-skills.sh` (84). No incluye el script de `set-model` embebido en `install.sh` (155 líneas × 2 renders de cliente, ~310 líneas): no es un fichero independiente y por eso queda fuera de las 1037. |
| Prompts de agentes | **347 líneas** — orchestrator (145), coder (87), specifier (57), verifier (58) |
| Mecanismo de embed | `# antz-include:` markers en `orchestrator.prompt`, renderizados por `install.sh` (función `inject_includes`) en tiempo de instalación. El script de `set-model` no usa markers: se emite desde `emit_set_model_script()` y se interpola en los dos command files. |
| Tests | 34 ficheros, ~16.925 líneas de tests shell |
| Specs SPDD afectadas | `posixsh.md`, `flow-branch.md`, `receipts.md`, render (`orchestrator-fast-path/02-renderinject`) |
| Complejidad frágil de install.sh | Workarounds bash 3.2 de macOS (heredoc en `$(...)`), máquina de estados anti-`$1` (los clientes templatean el cuerpo), pin de byte-identidad con excepción manual (`  done` de antz-skills.sh) |
| Ciclo de vida | No hay uninstall; update = re-ejecutar install.sh; distribución `curl \| sh` (texto puro); solo Claude Code + OpenCode |

### Dónde se van hoy los tokens de una sesión de orquestación

1. **System prompt del orquestador (~7.3K tokens estimados)**: 145 líneas de prose
   + ~335 líneas de scripts embebidos. Cachea bien *dentro* de la sesión — no es
   la fuga principal.
2. **Re-materialización (la fuga real)**: el prompt ordena "save the script below
   to a temp file and run `sh <tempfile>`". El agente **re-emite las ~335 líneas
   como argumento de su tool Write en cada sesión** — y también en cada resume
   ("Run this in full on every invocation"). ≈ 4K tokens de salida (estimación)
   por sesión, del tipo más caro (output ≈ 5× el input cacheado), + 3 tool-calls.
3. **Turnos**: discover → ensure → probe → clasificar → delegar → re-probe →
   release ≈ 6-10 turnos de orquestación pura; cada turno re-envía el prefijo.

---

## 3. Análisis Go objetivo por objetivo

| Objetivo | Veredicto |
|---|---|
| 1. Mantenibilidad / evolución | ✅ Real y fuerte. install.sh ya desbordó el presupuesto de complejidad de shell. En Go: parser de receipts como struct testeable, errores tipados, tests table-driven. |
| 2. Reducir prompts con scripts embebidos | ✅ Real, pero la causa raíz es la *decisión de embeber*, no shell. Arreglable sin Go (ver §5). |
| 3. Performance wall-clock | ⚠️ Mayormente ilusoria. Los scripts tardan decenas de ms; el workflow lo dominan los turnos del LLM. Excepciones menores: `git status --porcelain` en monorepos, fork-storm de antz-skills.sh (muchos awk por SKILL.md). |
| 4. Eficiencia de detección | ⚠️ Modesta pero real (consolidar forks en un proceso). No mueve la aguja. |
| 5. Caché de agentes | ✅ Argumento técnico sólido pero matizado: el texto embebido **ya cachea** como system prompt. La fuga real: (a) tokens de salida re-materializando, (b) bump de VERSION invalida todo el prompt, (c) salidas largas degradan el cacheo incremental. Un binario reduce el prompt (~145 → ~70 líneas) y hace salidas de una línea. Añadir Pi como cliente: caro en shell, trivial en Go. |
| 6. Instalar/actualizar/borrar | ✅ Real y probablemente el mayor beneficio de usuario. Hoy: sin uninstall, Windows imposible, sin releases binarios. |

### Pros de Go

1. Elimina la clase de bugs de quoting/escaping/templating ya sufridos (posixsh-01, corrupción de awk por `$ARGUMENTS`).
2. Reducción drástica de tokens por sesión de orquestación (objetivos 2+5).
3. Ciclo de vida completo: install/update/uninstall/check, Windows nativo, tercer cliente (Pi) barato.
4. Tests Go table-driven en vez de ~16.9k líneas de fixtures shell.
5. Gramática de receipts implementada una vez, compartida.

### Contras de Go

1. Coste de reescritura alto: re-especificar (specs SPDD), re-implementar, re-testear (~16.9k líneas de tests), cambio **major** por política de versionado.
2. Cambio de identidad: AGENTS.md registra la ley "no CLI/hook/plugin, nada instalado". Un binario en PATH la contradice.
3. Pérdida de transparencia: hoy usuario y agente pueden `cat` el script; un binario es opaco (mitigable: open source, checksums, `antz explain`).
4. Ingeniería de releases: matriz de plataformas, firmado, goreleaser. El repo pasa de texto puro a artefactos binarios.
5. Version skew: prompt y binario pasan a ser dos artefactos que pueden divergir (necesita handshake de versión).
6. La ganancia de performance (objetivo 3) no se materializa: si fuera la motivación principal, la respuesta sería "no".

### Juicio Go (resumen)

**Sí es buena idea — pero por las razones correctas, y es un cambio de contrato, no un refactor.** Justifican: objetivos 1, 2, 5, 6 (el coste oculto mayor es de **tokens y turnos**, no de CPU). No justifican: 3 y 4. El precio real no es escribir Go: es rehacer el contrato (ley AGENTS.md, specs, tests, versionado major, release engineering). Recomendación original: A (Go completo) incremental, con des-embed como primer paso.

---

## 4. Alternativas evaluadas

- **A — Go completo**: binario hace todo (probe/flow/skills + installer). Maximiza los 6 objetivos. Apuesta estratégica.
- **B — Go solo para orquestación**, install.sh sigue en shell: mitad del beneficio, dos lenguajes. No recomendable como estado final.
- **C — Sin Go (des-embed)**: instalar los scripts como ficheros y que el orquestador los invoque por ruta. Resuelve objetivos 2 y 5 con ~10% del esfuerzo. **Es la vía elegida para ahora** (ver §5).
- **Anti-patrón a evitar**: extraer los scripts del propio agent file con sed/awk — acopla el prompt a los fences, frágil entre clientes, un modelo que parafrasea corrompe el script.

---

## 5. DECISIÓN ACTUAL — Des-embed en POSIX puro (objetivos 2 y 5)

Alcance confirmado: **Linux/macOS, sin Go por ahora, objetivos 2 y 5 prioritarios.**

### El cambio propuesto (100% POSIX)

1. `install.sh` instala los **3 scripts de orquestación** (`antz-flow.sh`,
   `antz-probe.sh`, `antz-skills.sh`) como ficheros en ruta fija compartida:
   `${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts/`, con el mismo marker
   `antz:generated version=...` (backup/`--check`/política de versiones aplican igual).
   Se invocan con `sh <ruta>` — no hace falta `+x`. El script de `set-model`
   (cuarto artefacto, ver punto 5) se instala en la misma ruta.
   Nota de diseño: XDG reserva `.config` para configuración editable y
   `.local/share` para datos generados; se eligió `.config` (decidido
   el 2026-09-13) para agrupar todo antz bajo un mismo root visible, a
   sabiendas de que los scripts son artefactos generados. Por eso la ruta
   respeta `XDG_CONFIG_HOME` y nunca hardcodea `$HOME/.config`.
2. `orchestrator.prompt` sustituye cada fence embebido por una línea de invocación.
   La ruta se resuelve **una sola vez en `install.sh`** (`${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts/`)
   y se interpola en la línea ya resuelta al renderizar, de modo que el prompt
   invoque una ruta concreta y no dependa de `XDG_CONFIG_HOME` en runtime:
   ```
   sh "/home/<user>/.config/antz/scripts/antz-flow.sh" discover
   ```
   (la `$HOME` del usuario que instala aparece expandida; sin hardcodear
   `$HOME/.config` cuando `XDG_CONFIG_HOME` está definido).
3. El vocabulario de machine lines (`state=...`, `subspec=...`, `receipt=...`)
   queda **byte-idéntico**: el prose de routing y las specs SPDD no cambian de
   contrato, solo las líneas de invocación.
4. `install.sh` **elimina `inject_includes()`** — se van su loop con riesgo
   bash-3.2 y la excepción de byte-identidad del `  done` de antz-skills.sh
   (la parte más frágil del renderer). Simplificación gratuita.
5. Igual tratamiento para `/antz-set-model`: el script embebido (~155 líneas × 2
   clientes, con toda la parafernalia anti-`$1`) se instala como fichero y el
   command body lo invoca por ruta. El command file baja de ~300 a ~80 líneas.
   Al des-embeberlo desaparecen también los workarounds bash 3.2 de
   `emit_set_model_script()`/`set_model_flow_head` (heredoc dentro de `$(...)`),
   hoy en `install.sh:299-305` y `567-571`: otro tramo frágil que se retira.
6. `--check` de install.sh extiende su reporte a los scripts instalados.

### Ahorro estimado (por sesión de orquestación)

| Concepto | Hoy | Des-embed |
|---|---|---|
| System prompt | ~7.3K tok (prose+scripts) | ~2.5-3K tok (−55-60%) |
| Tokens de salida re-materializando scripts | ~4K (est.) | **0** |
| Tool-calls de setup | 3 Writes + N runs | N runs (una línea cada uno) |
| Vocabulario de salida | idéntico | idéntico |

El overhead de orquestación baja **~70-80%**. Honestidad sobre la magnitud: en el
coste total de un cambio (sesiones specifier/coder/verifier leyendo/escribiendo
código), la orquestación es una fracción pequeña — el ahorro es drástico sobre el
overhead, no sobre el coste total del workflow. Matices de caché: la invalidación
por bump de VERSION sigue igual (el marker del frontmatter cambia siempre); el
cacheo cross-sesión depende del TTL del provider.

Opcional (segundo paso, cambio separado): subcombinación `ensure` + `state` en un
solo subcomando para resumes (ahorra 1 turno por resume). No es imprescindible.

### Costes y riesgos

- **Version skew**: dos artefactos versionados (agent file + scripts). Mitigación: install.sh escribe todo en una pasada; `--check` reporta también los scripts. Nota: el des-embed **no elimina** el version skew que §3 reprocha a Go — prompt y scripts siguen siendo artefactos separados con marker `version=`; solo lo hace menos visible (mismo problema, sin binario). El prompt no verifica la versión de los scripts en runtime.
- **Ruta compartida entre clientes**: con Claude Code y OpenCode instalados, el libdir es uno solo; dos `install.sh` de versiones distintas pueden mezclar escrituras (last-write-wins). Ver pregunta 1 de §6: ruta compartida vs subdirectorio por cliente.
- **Ley de AGENTS.md a revisar**: "saved to a temp file and run via sh, rather than installed anywhere" → "instalados en ruta de librería fija, invocados por ruta, sin CLI en PATH, sin hooks/plugins". Se conserva el espíritu, cambia la letra.
- **Superficies a tocar**: `install.sh`, `orchestrator.prompt`, los 2 command files, AGENTS.md; specs: `posixsh.md` y la spec del render (`orchestrator-fast-path/02-renderinject`, que gobierna el mecanismo `antz-include` que se retira). Tests que asertan `# antz-include:` y que habrá que reescribir (no solo "los de render"): `tests/renderinject_test.sh`, `tests/orchestrator-sessionguards_test.sh`, `tests/orchestrator-skills-block_test.sh`, `tests/orchestrator-status-probe_test.sh`, `tests/antz-flow_test.sh`. **Los tests de los scripts NO cambian** (scripts byte-idénticos).
- **Graduación de versión**: propuesta **minor** (contrato de salida y workflow contract intactos; cambia mecánica de instalación y cuerpos renderizados), aunque la cláusula de "install locations" del policy lo hace discutible — documentarlo explícito en el CHANGELOG.

### Juicio resumen (des-embed)

**Sí, viable y recomendable.** El win viene de instalar los scripts como ficheros
y que el orquestador los invoque por ruta. Cambio contenido y de bajo riesgo
(salidas idénticas, tests de scripts intactos), que además retira la parte más
frágil de install.sh. Lo que queda fuera — uninstall, Windows, complejidad
remanente de install.sh — es lo que justificaría Go más adelante; esta migración
no lo estorba: si algún día se quiere el binario, el contrato de invocación por
ruta ya está en su sitio.

---

## 6. Para retomar más adelante

### Decisiones abiertas (OPEN_QUESTIONS candidates)

1. **Resuelta (2026-09-13)**: ruta `${XDG_CONFIG_HOME:-$HOME/.config}/antz/scripts/`, compartida entre clientes (riesgo de mezcla cubierto por `--check`); se descarta subdirectorio por cliente.
2. ¿`/antz-set-model` entra en la misma change o en otra?
3. Graduación minor vs major (cláusula "install locations").
4. ¿Añadir el subcomando combinado ensure+state en esta change o diferirlo?
5. ¿Actualizar también los ejemplos de temp-file en AGENTS.md Gotchas y docs/orchestrator.md en la misma pasada?
6. ¿Handshake de versión prompt↔scripts en runtime, o basta con `install.sh --check` offline? (El des-embed no elimina el version skew de §3.)
7. **Resuelta (2026-09-13)**: `install.sh` resuelve `XDG_CONFIG_HOME` (fallback `$HOME/.config`) y escribe la ruta concreta en el prompt renderizado; nada se resuelve en runtime.

### Siguiente paso propuesto

Crear el cambio SPDD `spdd/changes/deembed-orchestration-scripts/` vía el propio
workflow (`/antz`), con sub-specs aproximadas:

- `01-install-scripts-to-libdir.feature` — install.sh instala los 3 scripts de orquestación + el de set-model (4 artefactos) con marker/backup/check y resuelve la ruta XDG
- `02-orchestrator-invocations.feature` — orchestrator.prompt invoca por ruta; retirar `# antz-include:` y `inject_includes()`
- `03-set-model-deembed.feature` — command files invocan el script instalado (client como argumento o un fichero por cliente)
- `04-docs-law.feature` — revisión de la ley de runtime en AGENTS.md + specs posixsh.md / renderinject + CHANGELOG (graduación)
- `05-tests-render.feature` — adaptar los 5 tests que asertan `# antz-include:` (renderinject, sessionguards, skills-block, status-probe, flow)
