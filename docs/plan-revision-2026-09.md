# Plan de respuesta a la revisión — antz 4.3.0

**Fecha:** 2026-09-11 · **Fuente:** revisión externa completa (4 prompts, install.sh, 3 scripts de `scripts/orchestration/`, docs, specs archivadas; tests 20/20 en verde) · **Verificación:** cada afirmación cotejada contra los archivos por opencode.

## 1. Verificación de la revisión

### Confirmadas — corregir

| # | Afirmación | Evidencia |
|---|---|---|
| 1.1 | El orquestador nunca delega al specifier; `change_dir=missing` mata el camino feliz de un cambio nuevo | `orchestrator.prompt:68` ordena stop/ask; `delegated-specifier` está en el vocabulario (`:120`) pero ningún paso lo produce |
| 1.2 | El guard de dedup prohíbe el reintento del verifier que el paso 4 ordena | `orchestrator.prompt:114` (único carve-out: relay al coder) vs `:86` ("delegate the whole change to verifier once more") |
| 1.3 | El paso 5 detecta la aprobación por conversación, violando la regla rectora | `orchestrator.prompt:89` vs `:127` |
| 1.4 | El coder se contradice sobre `spdd/specs/` | `coder.prompt:4` vs `:10` ("Never touch ... except as read-only context") |
| 1.5 | `waiting-user` está en el vocabulario pero ningún paso lo produce ni define | `orchestrator.prompt:120`; pineado por `tests/closingblock_test.sh:246` |
| 1.6 | `git mv` sobre archivos untracked falla siempre (nada se commitea) | `verifier.prompt:30` |
| 1.7 | `test_command=` "indescubrible" sin sentinel definido; el orquestador ejecutaría basura | `coder.prompt:55,64`; `antz-probe.sh:61-64` acepta cualquier valor no vacío; `orchestrator.prompt:79` |
| 2.x | Todos los huecos de precisión (índice, "code present", búsqueda de ids, umbral de plan, naming de dominio `spdd/specs/`, nombre de la e2e suite, ubicación de relevant-files, slug sin validación mecánica, regex de la sonda tolera guiones que el specifier prohíbe) | `specifier.prompt:17,23-26,41-42,44`; `coder.prompt:20-21`; `verifier.prompt:11,29`; `antz-flow.sh` sin validación de slug; `antz-probe.sh:106` |
| 3.1 | `ensure` conmuta de rama con el árbol sucio y arrastra trabajo ajeno | `antz-flow.sh:68` — **la deficiencia más importante del diseño no-commit** |
| 3.2 | `curl \| sh` desde master sin pin | `install.sh:31` |
| 3.3 | Detección del marker por `grep -q` de contenido: un archivo ajeno que mencione `antz:generated` se sobrescribe sin backup | `install.sh:549` |
| 3.5 | Descripción embebida sin quoting YAML | `install.sh:200,209` |
| 3.6 | Menores: mktemp sin trap, `.bak` acumulados, cabecera sin orchestrator/commands | `install.sh:2-3,383` |
| 4 | Estilo: cláusula espejo ~10 veces, frases de 100-130 palabras, viñeta huérfana `coder.prompt:43-45`, triple negación `specifier.prompt:41-42`, terminología inconsistente | verificado en los 4 prompts |
| 5 | Docs: "not present yet" falso (`spdd/specs/` y `spdd/archive/` existen con contenido); AGENTS.md/CLAUDE.md ~95% idénticas | `AGENTS.md:13`, `CLAUDE.md:13` |

## 2. Decisiones tomadas

- **Proceso:** cada cambio se ejecuta por el flujo SPDD del propio repo (`/antz`: specifier → coder → verifier, sin commits, bump de `VERSION` + `CHANGELOG.md` + tag `vX.Y.Z`, tests actualizados en el mismo cambio).
- **Guard de árbol (3.1):** `ensure` rechaza con estado nuevo `state=tree_dirty` **solo al arrancar un flujo** (cuando `spdd/changes/<slug>/` aún no existe): exige `git status --porcelain` vacío. Una vez el change dir existe (resume), el guard no aplica — el trabajo de implementación del flujo vive legítimamente fuera de `spdd/` (en este repo `agents/`, `scripts/`, `tests/`; en un proyecto anfitrión, el código de la app), así que un chequeo de suciedad fuera de `spdd/` en el resume dead-lockearía cada reanudación a mitad de implementación.

## 3. Cambios planificados

### Cambio A — `fix-orchestrator-flow` (minor 4.4.0): ítems 1.1–1.7

- **1.1:** tras `ensure`, si no existe `spdd/changes/<slug>/` ni `spdd/archive/<slug>/` (el flujo nunca fue especificado — cubre tanto `state=created` como el candidato branch-only `state=reused` que nunca escribió nada) → delegar al specifier (crea el dir) → re-sondear. `change_dir=missing` cuando el dir sí existía en `discover` (candidato on-disk) → borrado mid-sesión: stop y preguntar. Tras una delegación al verifier, `change_dir=missing` no aplica esta regla — enruta a 1.3. `delegated-specifier` gana su paso productor.
- **1.2:** el guard de dedup enumera exactamente dos excepciones: el relay al coder (paso 4) y el reintento único del verifier (paso 4, bounded por `REJECTED.md`).
- **1.3:** el paso 5 re-sondea disco: dir ausente en `spdd/changes/` + `release` en verde = aprobado (approved-with-warnings incluido — su archive move es idéntico en disco); entrada nueva en `REJECTED.md` → paso 6; cualquier otra cosa (dir presente sin rechazo nuevo) → stop fail-closed. El gate de `release` disambigua el `change_dir=missing` post-verifier: archive presente = aprobado; `gate=refused reason=archive-missing` = estado anómalo → stop.
- **1.4:** viñeta del coder reescrita por **superficie de escritura**, no de lectura: "lee `spdd/changes/` y `spdd/specs/` (contexto de solo lectura, nunca lo escribas); escribe el código y tests que el sub-spec pida donde corresponda en el proyecto, más su receipt en `spdd/changes/<slug>/`; nunca toques `spdd/archive/`". (Corrección propia tras 2ª revisión: la redacción anterior "escribe solo dentro de `spdd/changes/<slug>/`" prohibiría implementar — el coder escribe fuera de `spdd/` por definición.)
- **1.5:** **definir** `waiting-user` como variante de parada que entrega una decisión al usuario (open questions, ambigüedad de slug, duda de receipt) frente a `stopped` (parada dura de estado). El latch aplica idénticamente a ambas — `waiting-user` cambia el `status=` del cierre, no el comportamiento de parada. Reconciliar el wording del latch (`orchestrator.prompt:115`) y el vocabulario en tests/docs. Definir —no eliminar— mantiene `closingblock_test.sh` y los docs válidos.
- **1.6:** `mv` a secas como única instrucción, con la razón en el propio prompt. (Matiz de la 2ª revisión: `verifier.prompt:30` ya ofrece el `mv` llano, así que hoy es una trampa evitable, no un bloqueo duro; ningún test fija `git mv`.)
- **1.7:** sentinel literal `test_command=none` cuando no hay suite descubrible. La sonda lo acepta como valor bien formado (`complete` puede ser `yes`); el orquestador nunca lo ejecuta — con `none` y receipt dudoso, clasifica desde las líneas `id=` o pregunta al usuario una vez. (Matiz de la 2ª revisión: el "ejecutaría basura" solo ocurre con receipt dudoso *y* `test_command=` basura no vacío — el camino común, `complete=yes`, nunca ejecuta; el sentinel sigue siendo necesario para cerrar el hueco.)
- **Impacto en tests existentes (2ª revisión):** `tests/antz-flow_test.sh` fija prosa del orquestador que 1.1/1.3 tocan — `test_orchestrator_01_state_meanings` (`:591`), `test_orchestrator_05_unchanged_surface` (`:696`, que exige "numbered steps still end at 6" y exactamente 14 fences) — así que la delegación al specifier debe plegarse dentro de los pasos 1–2 existentes sin renumerar ni añadir fences nuevos; `tests/orchestrator-sessionguards_test.sh:271` exige `change_dir=missing` (la tabla de 1.1 lo conserva como salida de la sonda, cambia solo el routing); `tests/receipts_test.sh` fija el wording de `test_command=` que 1.7 reescribe. Además, actualizar `docs/orchestrator.md:29` (describe el diff before/after del specifier con el flujo viejo) — docs, no requiere bump.

### Cambio B — `flow-script-guards` (minor): prioridad 2 de la revisión

- Validación mecánica de slug en `antz-flow.sh`: `case $slug in ''|*[!a-z0-9-]*|-*|*-|*--*) reject` (charset, sin hyphen inicial/final, sin dobles) + largo máximo (p. ej. 40).
- Guard de árbol: `state=tree_dirty` al arrancar un flujo nuevo (sin change dir) si `git status --porcelain` no está vacío; se omite en resume (diseño decidido arriba). Ojo: `--porcelain` incluye untracked no ignorados — en un proyecto anfitrión con artefactos de build sin `.gitignore` el arranque queda bloqueado; es fail-closed a propósito (el usuario limpia o ignora).
- **Cablear los estados nuevos en `orchestrator.prompt`** (2ª revisión): la tabla de `ensure` (`orchestrator.prompt:28`) y la lista de stops del latch (`:115`) solo conocen `created/reused/checkout_refused/no_branch/no_commits` — sin esto, el orquestador no sabría enrutar `state=tree_dirty` ni el rechazo por slug inválido.
- Mitigación opcional del riesgo residual de resume (2ª revisión): `ensure` puede emitir `dirty=yes` junto a `state=reused` (línea máquina, sin cambio de comportamiento) para que el orquestador avise que el resume acarrea suciedad preexistente al commit del humano.
- Tests: reescribir los existentes que consagran el comportamiento viejo — `tests/antz-flow_test.sh` `ensure-02` (`:244-259`, árbol sucio espera `state=created`) y `ensure-05` (`:304-330`, árbol sucio espera `checkout_refused`) — además de añadir los casos nuevos (slug inválido, `tree_dirty`, resume sin guard).

### Cambio C — precision gaps (minor)

- `<index>` = dos dígitos cero-rellenos, secuencial desde 01 (`specifier.prompt:17`).
- "code present" = criterio mecánico: los ids de escenario del sub-spec aparecen en los archivos de tests del proyecto (grep literal del id) o su receipt existe.
- Búsqueda de ids: grep del id literal en los archivos de tests del proyecto.
- Umbral de plan: >8 pasos de implementación o >1 contrato compartido que cambiar → marcar split (N fijado tras 2ª revisión — el plan no puede dejar un hueco de precisión abierto).
- Dominio: un archivo por dominio `spdd/specs/<domain>.md` (kebab-case); el specifier declara el dominio destino de cada sub-spec en el `README.md` (sección por sub-spec, junto a los relevant-files); el verifier crea el archivo si el dominio es nuevo.
- e2e QA suite: nombre fijo `e2e-qa.feature` **uno por change dir** (la práctica archivada), no "one per feature" — reconciliar el wording de `specifier.prompt:23-24` (2ª revisión: con sub-specs multi-capa, un archivo por feature no encaja con un nombre fijo único).
- Relevant-files: en `README.md`, una sección por sub-spec.
- Slug: límite de longitud + colisión sin continuidad semántica → preguntar al usuario (no solo sufijo `-2`).
- Regex de la sonda alineada con la convención del specifier (sin guiones en `<feature>`), para que detecte violaciones en vez de tolerarlas. Toca la extracción de ids (`antz-probe.sh:106`) que fijan `tests/orchestrator-status-probe_test.sh` y `spdd/specs/receipts.md` — actualizar ambos en este cambio (2ª revisión).

### Cambio D — style rewrite (patch; semántica intacta)

- Cláusula espejo ("mirror only / receipt is the authority") una sola vez por prompt.
- Frases de 100-130 palabras → listas cortas (closing block del coder, fila `rejected_count=1`, guard de dedup, entrada de `REJECTED.md`).
- Viñeta huérfana `coder.prompt:43-45` plegada en `## Receipt`.
- Triple negación `specifier.prompt:41-42` → reescritura de 2 líneas (la propuesta en la revisión).
- Terminología unificada: sub-spec, slug, client, working root.
- Tests que pinean strings exactos (`closingblock`, `receipts`, `orchestrator-sessionguards`, `orchestrator-status-probe`, `skills-activation*`) actualizados en el mismo cambio.
- Documentar la regla de edición: `## Working Root` está duplicada verbatim en 3 prompts a propósito (autonomía por prompt); toda edición futura toca los tres sitios.

### Cambio E — hardening install.sh + docs (minor por detection logic; docs solos no requieren bump)

- Marker anclado a cabecera: `grep -q '^# antz:generated '` en `install_file` (`install.sh:549`), en `installed_version_of` (`:558-564`) y en el script embebido de set-model (`:360`) — los tres matchean en cualquier parte del archivo (2ª revisión).
- Quoting YAML de `description` en `render_claude`/`render_opencode` (`install.sh:200,209`) **y en `render_set_model_command`** (`:512-513`, `short_desc` — tercer sitio sin comillas que el plan omitía). Clasificado tras 2ª revisión como endurecimiento latente, no bug vivo: las descripciones actuales no rompen YAML.
- Pin por tag efectivo (2ª revisión): documentar la URL por tag **no basta** — `install.sh:31` fija `RAW_BASE` a `master` y `fetch_file` baja VERSION/CHANGELOG/prompts/meta de ahí; instalar desde un tag seguiría leyendo contenido de `master`. El script debe derivar el ref de su propia procedencia (p. ej. variable de entorno `ANTZ_REF` o parámetro que la URL por tag pasa al script) y usarlo en `RAW_BASE`.
- Trap de limpieza para el `mktemp` del script embebido; política para `.bak.<ts>`; cabecera de `install.sh` mencionando orchestrator y commands.
- `AGENTS.md:13` / `CLAUDE.md:13`: "not present yet" → describir el estado real. Evaluar fuente única para las porciones byte-identical (decisión aparte).

## 4. Pendiente

- **Alcance de arranque:** solo Cambio A / A+B / A+B+C / secuencia completa A–E (sin decidir aún).

## 5. Cómo ejecutar el plan con antz

Orden recomendado: **A → B → C → E → D** (A arregla el flujo que B–E usan; D va al final porque reescribe los prompts que A y C editan; E es independiente).

**Por cada cambio, el ciclo es:**

1. **Arrancar el flujo** en tu sesión (Claude Code u OpenCode) con una petición que cite este plan y el cambio concreto, p. ej.:
   ```
   /antz implementa el Cambio A (fix-orchestrator-flow) del plan
   docs/plan-revision-2026-09.md, sección 3
   ```
   El orquestador deriva el slug, crea/posiciona la rama `antz/<slug>` y delega specifier → coder → verifier.
   **Ojo con el Cambio A (chicken-and-egg):** el orquestador que corre es la copia instalada *anterior al fix* — el propio bug 1.1 detendrá el flujo en `change_dir=missing` preguntándote por el slug. Respóndele delegando el cambio al specifier (eso es exactamente lo que el Cambio A viene a arreglar); de ahí en adelante el ciclo ya es automático. Lo mismo aplica a la validación mecánica de slug/árbol: no existirá hasta que B aterrice y reinstales.
2. **Si el flujo se detiene** (open questions, ambigüedad de slug, bloqueo): resuelve lo que pida y re-invoca `/antz` con la misma referencia al plan — el estado vive en disco (`spdd/changes/<slug>/` + la rama), el resume es automático.
3. **Al terminar (`released`):** quedas situado en `antz/<slug>` con todo el trabajo sin commitear. Tus follow-ups, en tu propia sesión:
   ```
   git status && git add -p && git commit    # revisa y commitea como prefieras
   git tag vX.Y.Z                            # contra el commit del bump, antes del merge (regla de versionado)
   git switch <integración> && git merge antz/<slug>
   git branch -d antz/<slug>                 # opcional
   ```
   El número de versión exacto lo fija el propio cambio, en secuencia: A=4.4.0, B=4.5.0, C=4.6.0, E=4.7.0, D=4.7.1.
4. **Reinstalar antes del siguiente cambio:** `./install.sh --all` — los agentes instalados incrustan los prompts y scripts renderizados; sin este paso, el siguiente cambio usaría el orquestador viejo (relevante sobre todo tras A y B, que tocan `orchestrator.prompt` y `antz-flow.sh`). Funciona con el trabajo sin commitear porque lee del checkout local.
5. **Opcional entre cambios:** `for t in tests/*.sh; do sh "$t"; done` para ver la suite completa en verde antes de arrancar el siguiente.

**Notas:**

- Nada se commitea durante el flujo: el commit es siempre tu follow-up (paso 3). Al arrancar cada cambio nuevo el árbol debe estar del todo limpio (`git status` vacío) — si no, `ensure` lo rechazará con `state=tree_dirty` una vez aterrizado el Cambio B; en resume el guard no aplica.
- Los tags no se pushean solos; hazlo cuando quieras (`git push origin vX.Y.Z`).
- Si prefieres no usar `/antz` para algún cambio concreto, la alternativa es invocar los roles directamente (specifier/coder/verifier a mano) — pero el flujo orquestado es el camino recomendado y, de paso, dogfoodea cada arreglo en vivo.

