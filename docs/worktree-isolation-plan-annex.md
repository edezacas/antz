# Anexo al plan: scriptear el flujo git (agilidad, tokens, determinismo)

Anexo a `docs/worktree-isolation-plan.md`, que queda intacto. Misma decisión
major (`2.0.0`), mismo alcance de archivos: este anexo solo cambia la
*implementación dentro de los prompts*, no el contrato del workflow (branch,
worktree, access model, commits por rol — todo igual).

## Contexto

El plan base deja toda la lógica git como prosa procedural que el modelo
interpreta y ejecuta paso a paso: matriz de 4 casos de worktree, discovery
dual con parseo de `git worktree list --porcelain`, chequeo prunable,
guardia repo-sin-commits, exclude idempotente, remove gateado, reglas de
commit por rol. El repo ya tiene la convención exacta para mecanizar eso:
el probe embebido de `orchestrator.prompt` (script POSIX guardado a temp
file y corrido con `sh`, misma convención que `/antz-set-model`). El plan
base lo aplica a la sonda y a nada más.

Principio rector (el mismo que ya fija el AGENTS.md para la sonda): los
scripts calculan **hechos derivables de disco**; el prompt decide el
enrutamiento sobre esos hechos. Nada de codificar el juicio (derivar el
slug del lenguaje natural, resolver ambigüedades, descubrir el comando de
test del host) en shell.

## Diseño

### Script 1: `antz-flow.sh` embebido en `orchestrator.prompt`

Un fence con subcomandos (`discover`/`ensure`/`release`), corrido con la
misma instrucción save-a-temp-y-`sh` de la sonda. Reemplaza la prosa de las
secciones "Creación / adjunte", "Resume / descubrimiento", "Worktree
movido/borrado" y "Limpieza" del plan base.

Dos fences, dos pasos separados: `antz-flow.sh` cubre solo la mecánica git
nueva. La sonda de OPEN_QUESTIONS/REJECTED/scenario-ids sigue siendo el
fence independiente que ya existe, sin tocar ni una línea ni su
indentación — el orchestrator corre DOS scripts embebidos por invocación
(uno más que hoy): `antz-flow.sh` primero, y después la sonda tal como hoy,
solo que con `CHANGE_DIR="<worktree>/spdd/changes/<slug>"` (absoluta).

**Constraint del fence**: el extractor de
`tests/orchestrator-status-probe_test.sh` matchea *todas* las líneas
exactas `   ```sh` / `   ``` ` (tres espacios de indentación) del prompt y
concatena todo lo que capture; un segundo fence con el mismo marcador haría
que el test extraiga los dos scripts pegados (y `cmd=$1` rompería bajo
`set -eu` al correrlo sin argumentos). El fence de `antz-flow.sh` debe
escribirse con marcadores que ese patrón ignore (p. ej. a columna 0, sin
indentar), dejando el de la sonda como único fence `   ```sh` del prompt.

```sh
#!/bin/sh
# usage: sh <tempfile> <command> [args]
set -eu

cmd=$1

case "$cmd" in
discover)
  # Candidatos: una linea por branch antz/*, cruzando worktree list +
  # branch list + el tree de cada branch.
  #   candidate=ready    slug=<s> path=<abs> change=<in-changes|archived|none>
  #   candidate=orphan   slug=<s>             change=<in-changes|archived|none>
  #   candidate=missing  slug=<s> path=<abs> change=<...>  (registrado pero
  #                      ruta ausente o prunable -> fail-closed)
  #   candidate=conflict slug=<s> path=<abs>               (directorio
  #                      plano no registrado como worktree -> fail-closed)
  # `change=` sale de `git cat-file -e antz/<s>:spdd/changes/<s>` y
  # `spdd/archive/<s>` sobre el tree del branch (sin tocar worktrees).
  # Exit 0 siempre; output vacio = sin candidatos.
  ;;
ensure)
  # usage: ensure <slug>
  # 1. Agrega `.worktrees/` a `$(git rev-parse --git-path info/exclude)`
  #    si no esta (idempotente, sin lock).
  # 2. `git rev-parse HEAD` falla -> `result=no_commits`, exit 1.
  # 3. Worktree registrado para el slug:
  #    a. ruta existe y coherente -> `result=reused path=<abs>`.
  #    b. ruta ausente o prunable -> `result=missing path=<abs>`, exit 1,
  #       imprimiendo el restore de dos pasos (verificado: el add solo
  #       falla con "missing but already registered worktree", exit 128):
  #         git worktree prune && git worktree add .worktrees/<slug> antz/<slug>
  # 4. Branch existe sin registro de worktree:
  #    a. ruta existe como directorio plano no registrado
  #       -> `result=conflict path=<abs>`, exit 1.
  #    b. ruta ausente -> `git worktree add <path> antz/<slug>`
  #       -> `result=attached path=<abs>`.
  # 5. Ninguno existe -> `git worktree add -b antz/<slug> <path> HEAD`
  #    -> `result=created path=<abs>`.
  # Nunca -B, nunca --force, nunca resetea un branch existente; nunca
  # ejecuta el restore del caso 3b por su cuenta (el orchestrator lo
  # imprime y para, fail-closed).
  ;;
release)
  # usage: release <slug> <path>
  # Gate mecanico (hecho de disco, no conversacional):
  #   [ -d <path>/spdd/archive/<slug> ] && [ ! -d <path>/spdd/changes/<slug> ]
  # No cumple -> `gate=refused reason=<archive-missing|change-still-present>`,
  # exit 1. Cumple -> `git worktree remove <path>` (sin --force); si el
  # remove falla, se reporta y exit 1. Exito -> `released path=<abs>`.
  ;;
esac
```

| Output | Significado / acción del orchestrator |
|---|---|
| `candidate=ready ...` | Candidato válido para resume; si hay más de uno, preguntar al usuario (igual que hoy). |
| `candidate=orphan ...` | Branch viva sin registro de worktree. Imprimir el restore (verificado: funciona directo, sin prune): `git worktree add .worktrees/<slug> antz/<slug>`. Nunca recrear por su cuenta. |
| `candidate=missing ...` | Fail-closed: parar, reportar branch + ruta. El restore impreso requiere dos pasos (verificado: sin `prune` el `add` falla con exit 128, "missing but already registered worktree"): `git worktree prune && git worktree add .worktrees/<slug> antz/<slug>`. Nunca ejecutarlo por su cuenta. |
| `candidate=conflict` / `result=conflict` | Fail-closed: parar, reportar la ruta en conflicto, nunca borrar/sobreescribir/remover. |
| `result=no_commits` | Repo sin commits: parar y pedir el commit inicial al humano. |
| `result=created/attached/reused path=<abs>` | Working root resuelto; esa ruta va en cada delegación. |
| `gate=refused` | No remover: el archive no consta en disco; reportar y parar. |
| `released path=<abs>` | Worktree removido post-aprobación; imprimir los comandos manuales de merge/borrado de branch. |

Ganancias:

- **Determinismo**: la matriz de casos, el chequeo prunable y los sufijos
  de colisión dejan de depender del parseo manual de `--porcelain` (formato
  fácil de malinterpretar: `prunable`, `locked`, `bare`) y de ejecutar los
  casos sin saltear ninguno. El script falla cerrado por construcción.
- **Tokens**: `worktree list --porcelain` trae todos los worktrees del repo;
  el script emite solo líneas `antz/*`. La prosa procedural del plan base
  (~100 líneas nuevas en orchestrator.prompt) se contrae a ~50 líneas de
  script + la tabla de arriba.
- **Corrige una fuga del governing rule del plan base**: el remove gateado
  decía "cuando el verifier aprobó y su Merge & Archive tuvo éxito" — estado
  conversacional, prohibido por el governing rule. Pero es derivable de
  disco: el verifier hace `git mv` a `spdd/archive/` + commit al aprobar,
  así que `spdd/archive/<slug>` en el worktree ES la prueba. `release` la
  exige mecánicamente: el gate deja de ser memoria del orchestrator y pasa
  a ser un invariante de disco (mismo nivel de confianza que la sonda).
- **Sobre sufijos `-2`/`-3`**: si el slug está ocupado, el script reporta
  (`slug_taken` vía los campos `change=` de discover) y para; el
  orchestrator elige el sufijo. El auto-sufijo solo sería correcto si la
  solicitud NO continuara el change existente — y ese juicio es semántico,
  no mecánico.

### Script 2: `antz-commit.sh`, fence compartido por los tres roles

Reemplaza la sección "Commits" del plan base (reglas en prosa) por
estructura. Idéntico en specifier/coder/verifier prompts, corriendo
invocación por invocación:

```sh
#!/bin/sh
# usage: WORKING_ROOT='<abs>' sh <tempfile> "<msg>" <path>...
set -eu
msg=$1; shift
[ -n "${WORKING_ROOT:-}" ] || { echo "no working root: commit gated off"; exit 1; }
cd "$WORKING_ROOT"
for p in "$@"; do git add -- "$p"; done
git diff --cached --quiet && { echo "nothing staged"; exit 1; }
git commit -m "$msg"
```

- `git add -A` prohibido **estructuralmente**: el script solo agrega los
  paths explícitos que el rol pasa; no existe la forma de barrer más.
- El gate "commit solo con working root" queda mecanizado: invocación
  manual sin `WORKING_ROOT` → exit 1, sin auto-commit (comportamiento que
  el plan base pide en prosa, aquí garantizado). El `cd` corre *dentro* del
  script, así que el mecanismo de commit no depende en absoluto de que el
  cwd del Bash tool persista entre llamadas.
- `git diff --cached --quiet` bloquea commits vacíos (rol que cree haber
  escrito algo y no escribió nada).
- specifier/verifier son `readonly` pero ya tienen Bash; el mecanismo
  funciona igual para los tres. El prompt de cada rol se reduce a:
  "commitea vía este script pasando los paths exactos que tocaste (los
  stubs `BLOCKED:` incluidos)".

### Working Root: prefijo por comando, no `cd` persistente

Mejora sobre el mecanismo del plan base: en vez de un `cd '<root>'` inicial
que se espera persista entre llamadas del Bash tool, cada comando suelto de
Bash en las delegaciones lleva el prefijo explícito `cd '<root>' && ...`,
incrustado por el orchestrator en el texto de cada delegación — los roles
no tienen que recordarlo. Los scripts ya anclan lo que importa sin depender
del cwd: `antz-commit.sh` hace el `cd` dentro de sí (vía `WORKING_ROOT`),
la sonda toma `CHANGE_DIR` absoluta, y `antz-flow.sh` corre el plumbing de
git desde el checkout principal (el cwd por defecto de la sesión del
orchestrator, nunca dentro del worktree); los paths de Read/Write/Edit son
absolutos por diseño en ambos clientes.

Consecuencia: la verificación previa en OpenCode (¿persiste el cwd del Bash
tool entre llamadas?) **deja de ser requisito** — era el prerrequisito del
plan base porque su convención descansaba en el `cd` persistente; con el
prefijo por comando el comportamiento es idéntico en ambos clientes y
determinista de entrada. Queda un riesgo residual, honesto pero acotado:
un comando suelto al que se le escape el prefijo corre en el checkout
principal en silencio (p. ej. la suite del host probaría el código
equivocado). Lo mitiga el prefijo incrustado en cada delegación y que el
commit y la sonda — los dos pasos con poder de corromper estado — van
scripteados y son inmunes.

### Qué no se scriptea (frontera intacta)

- Derivar el slug kebab-case desde la solicitud cruda — juicio de
  lenguaje; es el *input* del script, no parte de él.
- Ambigüedad de múltiples candidatos / pregunta al usuario — el script
  lista, el prompt pregunta.
- Descubrir el comando de test del proyecto host — juicio por proyecto,
  deliberadamente fuera del shell.
- Merge a la branch de integración y `git branch -d` — permanecen 100%
  manuales e impresos (decisión #2 del plan base). El script no tiene
  subcomando para eso, ni para `branch -d`, merge, `-B`, `--force` o reset.

## Archivos a modificar (sobre la lista del plan base)

- **`agents/prompts/orchestrator.prompt`** — además de todo lo que el plan
  base ya le asigna, el fence `antz-flow.sh` (con marcadores que el
  extractor del test de la sonda ignora, p. ej. a columna 0) + la tabla de
  outputs; las secciones de prosa git se reducen a "corre el script, enruta
  sobre su output" (mismo patrón del paso 2 actual). El orchestrator pasa a
  correr dos scripts embebidos: `antz-flow.sh` y la sonda intacta, esta
  última con `CHANGE_DIR` absoluta apuntando al worktree.
- **`agents/prompts/{specifier,coder,verifier}.prompt`** — además de la
  sección `## Working Root` que el plan base ya asigna, el fence
  `antz-commit.sh` (idéntico en los tres) + la instrucción de commit vía
  script (paths exactos, stubs incluidos).
- **`tests/antz-flow_test.sh`** y **`tests/antz-commit_test.sh`** (nuevos,
  opcionales pero recomendados) — fijan los fences contra drift, análogo a
  `orchestrator-status-probe_test.sh`; el de flow debe asertar también el
  constraint del marcador (que el fence de `antz-flow.sh` NO matchee el
  patrón `   ```sh` / `   ``` ` a tres espacios que usa el extractor de la
  sonda). Los cambios en `tests/` no requieren bump.
- **`tests/orchestrator-status-probe_test.sh`** — sin cambios: el fence de
  la sonda no se toca, y el extractor sigue capturando solo la sonda
  porque el fence de `antz-flow.sh` no matchea su patrón.
- **`CHANGELOG.md` + `VERSION`** — mismo bump `2.0.0` del plan base, en la
  misma entrada; este anexo no agrega gradación (los scripts viven dentro
  de los prompts que el plan base ya trackea).
- **`CLAUDE.md` y `AGENTS.md`** — los gotchas del plan base ganan una nota:
  "los hechos git (discovery/ensure/release) y los commits acotados se
  computan vía scripts embebidos, no por interpretación de prosa".
- **Sin cambios**: `agents/meta/*.yaml` e `install.sh` — igual que en el
  plan base; los scripts viajan dentro de los prompts (convención
  save-a-temp-y-`sh`), no como archivos instalados.

## Verificación

- `tests/versioning-rule_test.sh` y `tests/orchestrator-status-probe_test.sh`
  deben seguir pasando sin modificación.
- Verificar que el extractor del test de la sonda captura *solo* la sonda
  del orchestrator.prompt modificado (el fence de `antz-flow.sh` no
  matchea el patrón de tres espacios).
- Los tests nuevos de los fences (si se agregan) fijan el contenido exacto
  de `antz-flow.sh` y `antz-commit.sh`.
- Revisión manual: `antz-flow.sh` escribe solo plumbing (exclude, worktree
  add/remove sin flags destructivas) y solo lee `spdd/` — nunca contenido
  nuevo bajo `spdd/`.
- `antz-commit.sh`: probar el gate (sin `WORKING_ROOT` → exit 1), el
  bloqueo de commit vacío y el `add` acotado a paths explícitos.
- Reproducir (y documentar en el PR) el comportamiento verificado de este
  anexo: registrado-prunable → `add` falla con exit 128, restore con
  `prune` primero funciona y preserva el branch; orphan → `add` directo
  funciona.
- La verificación OpenCode del cwd persistente ya no es requisito: el
  prefijo `cd '<root>' && ...` por comando elimina la dependencia que la
  hacía necesaria (era el prerrequisito del plan base; este anexo lo deja
  sin efecto).
