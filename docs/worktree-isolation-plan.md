# Plan: aislar cada change de antz en su propio git branch + worktree

## Contexto

Hoy `antz` corre todo el flujo `specifier -> coder -> verifier` dentro del
checkout activo del usuario. Si se corren dos flujos `/antz` a la vez (o en
paralelo desde distintas sesiones) sobre el mismo repo, se pisan: mismo
working tree, mismos archivos `spdd/`, mismo estado de git.

Investigamos dos proyectos de referencia por fuera de este repo:
- `gentle-ai`: nunca crea worktrees, solo los descubre/valida con un lease de
  identidad criptográfico y falla cerrado si el worktree fue tocado
  externamente. Nunca automatiza el merge final a `main`.
- `swarm-forge`: sí crea worktrees él mismo (`.worktrees/<nombre>` en la raíz
  del repo, ignorado vía exclude), uno persistente por rol, y nunca los
  borra automáticamente.

El usuario pidió que `antz`, antes de que el `specifier` escriba nada, cree
un branch + worktree nuevos para el change (usando el título que le iba a
asignar a la carpeta), y que todo el flujo corra ahí — así se pueden correr
varios flujos `antz` en paralelo sin interferencia. Ya confirmó cuatro
decisiones de diseño:
1. El worktree vive como lo hace `swarm-forge`: `.worktrees/<slug>` en la
   raíz del repo.
2. El único merge que sigue siendo 100% manual y fuera de `antz` es
   `antz/<slug> -> main`; el trabajo de cada rol ya queda commiteado
   directamente en el branch (un worktree checkout ES ese branch, no hace
   falta un merge intermedio).
3. Cada rol commitea lo que escribe **solo cuando recibe un working root**
   (es decir, solo dentro del flujo orquestado con worktree aislado) — la
   invocación manual/directa de un rol, sin working root, sigue exactamente
   igual que hoy (sin auto-commits).
4. Este es un cambio **major** (`2.0.0`): el propio usuario lo consideró
   ruptura del contrato del workflow (cómo se identifica y aísla un change),
   no solo un cambio de comportamiento de un rol.

## Diseño

### Convenciones nuevas
- **Branch**: `antz/<slug>`.
- **Worktree**: `<repo-root>/.worktrees/<slug>` (mismo patrón que
  swarm-forge). Se ignora localmente agregando `.worktrees/` a
  `.git/info/exclude` (si no está ya) — nunca se edita el `.gitignore`
  versionado del proyecto host, para no tocar contenido trackeado de un repo
   de terceros. `info/exclude` es compartido por todos los worktrees del
   repo — un solo write (hecho por el `orchestrator`, desde el checkout
   principal, antes de crear el worktree, p. ej. vía
   `git rev-parse --git-path info/exclude` en el checkout principal)
   cubre todo. Dos flujos paralelos
  pueden hacer read-modify-write de ese archivo sin lock; el peor caso es
  una línea duplicada, que es inofensiva y idempotente — no hace falta
  lockear.
- **Slug**: lo deriva el `orchestrator`, *antes* de delegar al `specifier`
  (invierte el mecanismo actual de "diffear `spdd/changes/` antes/después").
  Kebab-case corto derivado de la solicitud cruda del usuario, chequeado
  contra `spdd/changes/`, `spdd/archive/` y `git branch --list 'antz/*'`
  para evitar colisiones (sufijo `-2`, `-3`... si hace falta). Se le impone
  al `specifier` como instrucción explícita en el mensaje de delegación —
  reemplaza la lógica de "aprender el slug diffeando".

### Creación / adjunte del worktree (no destructivo)
- Repo sin ningún commit → `git worktree add ... HEAD` fallaría. El
  orchestrator detecta el caso (`git rev-parse HEAD` falla), para y le pide
  al humano hacer el commit inicial — `antz` nunca inicializa el repo host
  ni crea commits de scaffolding en el checkout principal.
- No existe branch ni worktree → `git worktree add -b antz/<slug> .worktrees/<slug> HEAD`.
  (HEAD = el commit actual del checkout principal; si el usuario tiene
  cambios sin commitear, el branch arranca desde el último commit —
  esperado y documentado, no un error.)
- El branch existe pero no tiene worktree adjunto (se borró el directorio a
  mano, el branch sobrevivió) → `git worktree add .worktrees/<slug> antz/<slug>`
  (sin `-B`, sin `--force` — nunca resetea un branch existente).
- `.worktrees/<slug>` existe como directorio plano que git NO conoce como
  worktree registrado (sobrante de una corrida muerta a mitad de
  `git worktree add`, o una copia manual) → `git worktree add -b` fallaría
  porque el target no está vacío. Fail-closed, igual que el caso
  "worktree borrado externamente": el orchestrator para, reporta la ruta
  en conflicto y nunca la borra/sobreescribe por su cuenta.
- Ambos existen y coinciden → se reusa tal cual (camino normal de resume).

### Working Root: cómo specifier/coder/verifier operan dentro del worktree
No hay parámetro de `cwd` en Read/Write/Edit (rutas absolutas) ni una forma
estable de fijarle directorio de trabajo a un subagente delegado en ninguno
de los dos clientes. El mecanismo es a nivel de prompt, igual en Claude Code
y OpenCode: el orchestrator pasa la ruta absoluta del worktree como texto
literal en cada delegación, y cada uno de los tres prompts gana una sección
nueva:

```
## Working Root
- If the delegating orchestrator (or caller) gives an absolute working root, run `cd '<root>'` as your first Bash action of this session, and treat every `spdd/...` path in this prompt as relative to it. Otherwise operate relative to the current working directory, unchanged from before.
- If you must run the host project's own test suite and its dependencies are not installed in this working root yet (fresh worktree), install them first, then run the suite.
```

Backward-compatible ideal: invocación manual/directa de un rol (sin working
root) se comporta exactamente igual que hoy. **Caveat**: hay una
suposición crítica en este mecanismo — que el shell del Bash tool es
persistente entre llamadas dentro de la sesión (cierto en Claude Code).
Antes de apostar el diseño a `cd`, verificar el comportamiento de la
sesión del Bash tool en OpenCode: si OpenCode resetea el cwd entre llamadas,
la convención muere silenciosamente a mitad de sesión y hay que buscar otro
mecanismo (p. ej. repetir el root en cada comando, o un prefix exportado).

**Invocaciones manuales dentro de un flujo aislado**: el único pase
manual que el orchestrator stop-y-reporta hoy es el de un blocker
no-atribuible (`rejected_count=1`). La
resolución de `OPEN_QUESTIONS.md` es responsabilidad del `specifier`
(resuelve cada pregunta con el usuario y remueve el archivo; el
orchestrator, al encontrar el archivo, hace stop y reporta sin resolver
nada) — pero el reporte del stop debe
incluir explícitamente el Working Root (ruta absoluta del worktree) que el
humano tiene que pasarle al rol que invoque. Sin ese dato, un verifier
invocado a mano leería `spdd/` del checkout principal, donde el change no
existe: verificaría contra nada y podría archivar el árbol equivocado.

**Dependencias del proyecto host**: el worktree recién creado no tiene
instalado nada del proyecto (`node_modules`, `.venv`, etc.). La instrucción
"si la suite lo pide, instala las dependencias del proyecto host antes de
correrla" va en el bloque Working Root de cada delegación — no
exclusivamente como nota del orchestrator, porque `coder` y `verifier`
corren la suite en sus propias sesiones frescas y la nota del orchestrator
se pierde en la traducción.

### Commits (gateados por working root, `git add` siempre acotado — nunca `-A`)
- `specifier`: `git add spdd/changes/<slug>` + commit tras escribir/resolver
  `OPEN_QUESTIONS.md`.
- `coder`: commit acotado a los archivos de implementación + tests que tocó
  para ese sub-spec (uno por sesión, ya que corre un sub-spec por sesión).
  Si en vez de implementar el coder escribe un stub `BLOCKED: <why>` y
  para (skip/pending, o rechazo del sub-spec entero a nivel planning), el
  stub **también se commitea** en ese mismo commit acotado: es estado
  cross-role (la evidencia de por qué no se avanzó) que el governing rule
  exige que sobreviva en disco — y en este diseño el "disco de estado" es
  el branch `antz/<slug>`; un stub sin commitear moriría con el worktree
  removido y rompería el resume y el contador de reintentos.
- `verifier`: un commit al aprobar (merge a `spdd/specs/` + `git mv` a
  `spdd/archive/`), uno al rechazar (`REJECTED.md`).

`git add -A` queda explícitamente prohibido en los tres prompts — importante
incluso sin worktree aislado, para no barrer cambios sueltos ajenos al rol
si algún día se relaja el gateo.

Nota de coherencia con el access model: que `specifier`/`verifier`
(readonly, sin Edit/Write) hagan commits no rompe el contrato — el
renderizado ya les otorga Bash (`install.sh`: `readonly` → `Read, Grep,
Glob, Bash`) y hoy ya autorean archivos vía Bash (documentado en
`spdd/specs/specifier-role.md`). El boundary real sigue siendo
prompt-level (igual que la asimetría aceptada de Claude Code), reforzado
por la prohibición de `git add -A`.

### Resume / descubrimiento en una invocación fresca
El paso 1 del orchestrator ("Find the change") se reescribe: además de
escanear `spdd/changes/` del checkout principal (que en flujos aislados
ya no contiene este change — vive commiteado en el branch),
corre `git worktree list --porcelain` y `git branch --list 'antz/*'`, y
junta como candidatos los branches `antz/*` de ambas fuentes. Escanear los
branches es indispensable: si el humano borró `.worktrees/<slug>` a mano,
el branch (y todo su trabajo commiteado) existe pero no aparece en
`git worktree list`, y el change quedaría invisible. En
`worktree list --porcelain`, la marca `prunable` requiere git ≥ 2.36; en
git viejas la keyword no aparece y el chequeo se degrada a "existe la
ruta" — aceptable. Mismo manejo de ambigüedad que hoy (si hay más de un
candidato, preguntar).

**Estado cross-role y la sonda embebida**: el governing rule es que todo
estado vive en disco — en este diseño, bajo el worktree, no bajo el
checkout principal. Esto obliga a reescribir también el paso 2 de
`orchestrator.prompt`: la sonda se corre con
`CHANGE_DIR="<worktree>/spdd/changes/<slug>"` (ruta absoluta) o tras
`cd '<worktree>'`, y los pasos 4-5 ("read REJECTED.md from disk") la
leen desde la misma working root. No hacerlo rompe silenciosamente el
contador de reintentos acotados (`rejected_count` siempre 0 desde el
checkout principal) y el hard stop de `OPEN_QUESTIONS.md`. La sonda en sí
no cambia; `tests/orchestrator-status-probe_test.sh` puede seguir sin
modificación siempre que se preserve el fence embebido exacto — cambian
solo el valor de `CHANGE_DIR` con que el orchestrator la invoca y las
rutas que usa en sus delegaciones.

### Worktree movido/borrado externamente
Antes de confiar en un candidato descubierto, se verifica que su ruta
listada exista y no esté marcada `prunable`. Si no: el orchestrator para,
reporta el branch y la ruta esperada, y da el comando exacto para
restaurarlo (`git worktree add .worktrees/<slug> antz/<slug>`) — nunca lo
recrea por su cuenta (evita divergencias silenciosas). Proporcional al
patrón fail-closed de `gentle-ai`, sin el lease criptográfico (desproporcionado
para este alcance).

### Limpieza
Un punto de limpieza automatizado y el resto 100% manual.

**Automática (única, gateada): removal del worktree.** Cuando el `verifier`
aprueba y su `Merge & Archive` (mover a `spdd/archive/` + commit) tuvo
éxito, el orchestrator ejecuta inmediatamente
`git worktree remove .worktrees/<slug>` — sin `--force`; si el remove
falla (cambios sin commitear, etc.), lo reporta y no lo fuerza. El branch
`antz/<slug>` con todos los commits queda intacto. Nunca
especulativo: este único remove solo ocurre exitosamente después de un
`Merge & Archive` exitoso — nunca en rechazo, nunca a mitad de flujo,
nunca por su cuenta fuera de ese punto.

**Manuales (impresos, nunca ejecutados):** merge a la branch de
integración y borrado de branch, con el nombre real de la branch de
integración del usuario (no hardcodeado; el human sabe cuál es):
```
git checkout <integration-branch> && git merge --no-ff antz/<slug>
git branch -d antz/<slug>
```
Se agrega a "What you don't do": `git worktree remove` solo puede correr
desde el orchestrator y solo en el único punto gateado arriba — nunca
especulativo, nunca en rechazo o interrumpido, sin `--force`; nunca
mergear `antz/<slug>` a ningún lado; nunca forzar recreación/reset de un
worktree o branch existente.

## Archivos a modificar

- **`agents/prompts/orchestrator.prompt`** — paso 1 reescrito (derivar slug,
  crear/adjuntar worktree no destructivo, descubrimiento vía
  `git worktree list --porcelain` **y** `git branch --list 'antz/*'`,
  chequeo fail-closed, guardia de repo-sin-commits), **paso 2 reescrito en
  su invocación** (la sonda corre con `CHANGE_DIR` absoluta apuntando al
  worktree, y los pasos 4-5 leen `REJECTED.md` desde la misma working
  root), bloque reusable de "Working Root" para cada delegación (incluye la
  instrucción de dependencias, que así llega también a coder/verifier), el
  paso 5 gana la remoción automática del worktree post-`Merge & Archive`
  (gateada, sin `--force`, falla se reporta) más las instrucciones de
  merge/borrado de branch manuales impresas, y "What you don't do" gana
  las reglas de no-destructivo (restringiendo `git worktree remove` a su
  único punto gateado).
- **`agents/prompts/specifier.prompt`** — sección `## Working Root`, usar el
  slug impuesto verbalmente en vez de elegir uno propio (cuando lo hay),
  instrucción de commit gateada.
- **`agents/prompts/coder.prompt`** — sección `## Working Root` (con las
  dependencias: el worktree no las tiene instaladas), instrucción
  de commit gateada.
- **`agents/prompts/verifier.prompt`** — sección `## Working Root` (dependencias
  incluidas: corre la suite e2e en el worktree), `git mv`
  + commit en Merge & Archive, commit en On Rejection (ambos gateados).
- **`CHANGELOG.md`** + **`VERSION`** — bump a `2.0.0` (major, confirmado por
  el usuario), entrada nueva bajo `## [2.0.0]` describiendo el aislamiento
  por branch+worktree, el nuevo mecanismo de slug, Working Root, ownership
  de commits, y el descubrimiento vía `git worktree list`.
- **`CLAUDE.md`** y **`AGENTS.md`** — Gotchas nuevos documentando la
  convención de branch/worktree, Working Root, y el ownership de commits por
  rol. Mismo contenido en ambos (ya son "casi gemelos"), sin tocar sus
  secciones `## Versioning` (deben seguir siendo byte-idénticas entre sí,
  verificado por `tests/versioning-rule_test.sh`).
- **`tests/orchestrator-status-probe_test.sh`** — sin cambios necesarios
  siempre que el fence del script embebido y su indentación se preserven
  exactamente tal cual están hoy.
- **Sin cambios**: `agents/meta/*.yaml` (ningún rol gana Edit/Write nuevo —
  Bash ya está en los cuatro), `install.sh` (solo renderiza prompt+meta tal
  cual, agnóstico al contenido), `docs/orchestrator.md` (se deja intacto:
  es explícitamente un registro histórico congelado del diseño `1.0.0`, no
  se mantiene sincronizado con cambios futuros).

## Verificación
- Correr `tests/versioning-rule_test.sh` y `tests/orchestrator-status-probe_test.sh`
  después de los cambios — deben seguir pasando sin modificación.
- Revisar manualmente que `orchestrator.prompt` escriba solo git plumbing
  (branch/worktree/exclude/lectura): nunca contenido nuevo bajo `spdd/`
  directamente (puede leer `spdd/` del worktree como resto del estado en
  disco; lo que no hace es editar archivos de spec).
- **Antes de implementar**: verificar en una sesión OpenCode si el cwd de la
  sesión del Bash tool persiste entre llamadas (una llamada `cd <tmp>`, y
  la siguiente `pwd`). Es la suposición en la que descansa todo el
  mecanismo Working Root.
- No hay app corriendo para probar en vivo: esto es edición de prompts de
  texto plano, sin build. La validación real (instalar y correr un flujo
  `antz` de punta a punta contra un repo de prueba) queda fuera del alcance
  de esta sesión salvo que el usuario lo pida explícitamente.
