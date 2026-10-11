# ARX Upgrade Failure — Debug Flow

ARX-specific methodology for diagnosing upgrade failures. Covers where to look, in what order, and how to interpret what you find.

**Code baseline** — the mechanism descriptions below were checked against these commits. Before relying on one, fetch and run `git -C <repo> log --oneline <commit>..origin/develop -- <files>`; any output means re-check the dependent section against the code.

| Repo @ commit (date) | Files | Sections that depend on them |
|---|---|---|
| arx-platform-core @ 1c45668e (2026-10-10) | `internal/services/upgrade/upgrade.go`, `pkg/deployment/deployer.go`, `pkg/deployment/shared_client.go`, `pkg/deployment/resource.go`, `internal/server/server.go`, `internal/lifecycle/lifecycle.go` | §3 diagram; §4 target triage, Sources of state, Git-already-at-target caveat; §6 Physically complete, Zombie upgrade-state |
| arx-go-flux @ v1.0.5 (version core pins in `go.mod`) | `pkg/flux/sync.go`, `pkg/flux/flux.go` (which Kustomizations `resumeFlux` clears) | §4 Git-already-at-target caveat; §6 Pre-flight scan |
| arx-platform-api @ b9c37eac (2026-10-10) | `internal/handler/v1/routes.go`, `internal/handler/v1/maintenance.go` | §6 Re-triggering via API |
| arx-platform-web @ 3064ebb3 (2026-10-10) | `nginx/templates/default.conf.template`, `charts/arx-platform-web/values.yaml` | §6 Re-triggering via API |
| arx-manifest-sources @ 6bcc4e6 (2026-10-11) | `deployments/traefik/values.yaml` | §6 Re-triggering via API |

## Trigger conditions

Load this reference when either path is present:

- **Path A — configmap error**: `upgrade-state` configmap shows `state: failed`, `error_code` non-empty, or `progress` stuck
- **Path B — API error**: any error response from an upgrade-related API call (any status code, any message)

Both paths can appear simultaneously. Path B may also appear alone if the upgrade controller failed before writing to the configmap.

---

## 1. Observe — always do both, before forming any hypothesis

Regardless of which path triggered the investigation:

1. **Read the configmap** in full:
   ```bash
   kubectl -n arx-system get configmap upgrade-state -o yaml
   ```
   Capture: `state`, `error_code`, `progress` (percentage → stage), `message`, `action`, `target`, `manifest_version`.

2. **Read the full API response** the user provided — error code, message, and any detail fields. Do not truncate.

Only after both are in hand, decide whether the API error is root cause or a downstream symptom of the configmap state.

**If a known-good peer machine exists**, list the diff first (same upgrade target, one works one doesn't). Common deltas worth checking before digging deeper:

- Is the broken one an upgrade-over-time machine vs a fresh install? Stale state from previous attempts accumulates only on the former.
- `kubectl get kustomization -A` SUSPEND column — anything suspended on the broken side but not on the peer?
- `helm history <release>` — any old failed revisions on the broken side?

Diff-first focuses the search; do not run this for issues with no comparable peer.

---

## 2. Call chain

```
web → arx-platform-api → core → [optional] manager (host service via systemd)
```

- `core` is the upgrade controller; it writes `upgrade-state`
- `manager` is a host service, called only when the upgrade requires OS-level work (e.g. OS version upgrade) — do not assume it is always involved

---

## 3. Collect — layer stack, top to bottom

Check in order. Do not skip layers. **The Flux GitOps layer is critical and easy to miss** — `core` commits manifest changes through a git-server → flux pipeline; if anything in that pipeline stops moving, every downstream layer looks healthy while the upgrade silently never advances.

```
[core / ARX upgrade controller]     <- writes upgrade-state configmap
        │
        ▼ (commits + pushes; its clone is re-synced to the server every session)
[Flux GitOps layer]                 <- GitRepository revision,
        │                              Kustomization suspend? lag?
        ▼
        ├── [Flux HelmReleases]     <- cluster workload upgrades
        │          │
        │      [Kubernetes Pods → logs / events]
        │
        ├── [SUC Plans / Jobs]      <- host service upgrades (k8s side)
        │
        └── [manager (host service)]    <- only if OS-level upgrade
                   │
               [systemd / journalctl]
```

| Layer | Tools |
|-------|-------|
| Flux GitOps | `kubectl get gitrepository,kustomization -A -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,SUSPEND:.spec.suspend,APPLIED:.status.lastAppliedRevision` — compare each Kustomization's `lastAppliedRevision` against the GitRepository `artifact.revision`. SUSPEND=true or applied-lagging means GitOps is the root layer. |
| HelmReleases | `kubectl get helmreleases -A` → `kubectl -n arx-system get helmrelease <name> -o yaml` |
| SUC Plans | `kubectl -n system-upgrade get plans` → compare `spec.version` vs `status.latestVersion`; check `status.conditions[type=Complete]` |
| Pods | `kubectl -n arx-system get pods` → `kubectl -n arx-system logs <pod>` |
| Host service | `systemctl status <unit>` → `journalctl -u <unit> -n 100` |

For host service logs, see `host-service-deploy.md` for the systemd paradigm.

---

## 4. Analyze — reading rules

**error_code routing**

| error_code | Start at layer |
|------------|----------------|
| `UPGRADE_ERROR_CODE_SERVICE_DEPLOY` | Flux HelmReleases |
| `UPGRADE_ERROR_CODE_DOWNLOAD` | Image pre-pull — manager logs, registry reachability |
| OS / firmware related | manager (host service) |
| Unknown | Read core logs first; find the failing RPC, then decide |

**target-field triage (host service vs k8s service stuck)**

The `target` field in `upgrade-state` names the component the orchestrator is currently working on, and `action` says what it is doing to it. `message` is display text for the same pair: `upgrading <name>` / `installing <name>` / `deleting <name>` / `<name> upgraded` / `<name> installed` / `<name> deleted`, `downloading images for <name>`, or a stage message (`upgrading firmware`, `upgrading k3s`, `updating helm repositories`, `upgrading services`) while `target` holds the stage. `upgrade starting` has empty `action` and `target`.

Read `action` first. `UPGRADE_ACTION_DOWNLOAD` is written before each component's image pre-pull and stays until the next stage write — the OS flash when one runs, otherwise the first deploy stage — so it means one of three things:

- Core is still pulling that component's images — manager logs show pull activity. The stall is in the image pull (manager, registry reachability), whatever `target` names.
- The pulls are done, no OS flash ran, and core is in the Flux sync that runs before the first deploy stage (up to the 1h `syncFluxTimeout`) — `target` is the last component pulled and the manager logs are quiet. Check the core log and the GitRepository revision (§3 Flux GitOps row).
- Nothing is driving the upgrade: core restarted during the pre-pull and its recovery gave up without writing `failed` (recovery never re-runs the pre-pull). The manager logs are quiet here too; what tells it apart is the core log — no active `UpgradeService/Upgrade` RPC, and `Background task error` with `recover: refetch …`. That is "Zombie upgrade-state" in §6.

On `state=failed` with this action, `error_code` decides: `UPGRADE_ERROR_CODE_DOWNLOAD` is the pull; anything else failed after it. For any other action, use `target` to jump directly to the right layer:

| `target` value | Stuck at | First commands |
|-----------------|----------|----------------|
| `arx-manager` / `arx-discover` / `arx-hal` / `arx-console` | **Host service** — SUC Plan + systemd unit on host | `kubectl get plan -n system-upgrade <name>` (Complete?), `systemctl status <name>` (active?), `journalctl -u <name> --since=1h` |
| `arx-platform-core` / `arx-platform-api` (older firmware: `arx-platform-api-ng`) / `arx-platform-web` / `arx-oauth2` / `arx-redis` / `arx-flux` / any other helm-managed name | **K8s service** — HelmRelease + helm-controller | `kubectl get hr -A -o yaml \| grep -B2 -A10 <name>` (Ready? suspend? generation drift?), `kubectl -n flux-system logs deploy/helm-controller --since=10m \| grep <name>` |

When both SUC Plan shows `Complete=True` AND systemd shows `active (running)` AND the helm chart for that name shows `Ready=True` — but `target` still names that service: the issue is upstream (Flux not applying what core pushed, or core found Git already at the target and is waiting on readiness — see the caveat below). See "Flux GitOps not syncing — silent stuck" below.

**HelmRelease failure**

A release with `READY = False` is the suspect. Compare:
- `.status.lastAttemptedReleaseActionDuration`
- `.spec.timeout` (absent = Flux default 5m)

If both match → this is a timeout, not a functional failure. The pod may have become ready after Helm gave up.

Check `.status.conditions[type=Stalled].reason` — `RetriesExceeded` means Flux will not retry automatically.

**Manager failure**

If core logs show a call to manager returning an error, switch to the host service layer. Do not keep looking inside the cluster — the failure is on the host.

**Flux GitOps not syncing — silent stuck**

Symptoms when this layer is broken: upgrade-state `state: running` with `progress` stuck for tens of minutes, but all pods Running and no HelmRelease shows READY=False. Everything looks fine downstream because nothing downstream is being asked to change.

Check signals (any one triggers this branch):

- `Kustomization.spec.suspend: true` on any Kustomization in the `flux-system` namespace (typically `flux-system` / `apps` / `aimodels` / `mcp`, but the set may evolve). A previous upgrade or developer may have suspended them and forgotten to resume. kustomize-controller logs `"Reconciliation is suspended for this object"`.
- `Kustomization.status.lastAppliedRevision` lags behind `GitRepository.status.artifact.revision`. Means flux fetched the new commit but the kustomization is not applying it.
- arx-flux-git-server has no push session in its recent logs while the upgrade is supposedly progressing — meaning `core` did not push anything because Git already held the target; core logs `Deployment unchanged in Git, skipping Flux sync` (see the caveat below).

**Sources of state — they can all disagree**

`core` writes manifests through one shared git clone per process (`pkg/deployment/shared_client.go`). Every write session first re-syncs that clone to the server (fetch + hard reset, falling back to a fresh clone), so commits an earlier failed attempt left unpushed do not carry into the next session. Stuck-upgrade scenarios almost always show divergence among the layers below — read each one independently and look for which pair disagrees:

| Layer | Written by | Can be stale | How to read |
|-------|-----------|--------------|-------------|
| `core` git clone | arx-platform-core | Only within one session — the next session's fetch + reset drops unpushed commits | Not directly readable; restarting core does not change what the next session sees |
| `flux-manifests` git server | core via SSH push | Authoritative | arx-flux-git-server pod logs — look for SSH sessions that received a push |
| `GitRepository.status.artifact.revision` | flux source-controller | Yes — depends on poll interval | `kubectl get gitrepository -n flux-system` |
| `Kustomization.status.lastAppliedRevision` | flux kustomize-controller | Yes — stops moving when suspended | `kubectl get kustomization -A` |
| `upgrade-state` configmap | ARX upgrade controller | Yes — remains `failed`/`running` after manual recovery |
| HelmRelease status | Flux controller | Yes — pod ready but release still Stalled |
| systemd state | OS init system | No — reflects current process state |

Read each layer independently. Do not use one as evidence about another.

**Caveat: Git already at target → core waits on readiness, not on Flux**

`arx-platform-core/pkg/deployment/deployer.go` `commit()` treats `git.ErrEmptyCommit` as "nothing changed", and `push()` ignores `git.NoErrAlreadyUpToDate`. When a component's manifest on the git server already equals the target (an earlier attempt pushed it), core logs `Deployment unchanged in Git, skipping Flux sync` and goes straight to `WaitResourceReady` on the in-cluster resource, for up to the 1h `syncFluxTimeout`. If Flux is not applying that revision, core hangs there for the full hour. A suspended base-tier Kustomization is not the cause here: every upgrade run (recovery included) clears `spec.suspend` on the GitRepository and the `platform` / `infrastructure` / `systemd` / `k3s` Kustomizations before its first deploy stage (`resumeFlux`). What can still block it: a suspended HelmRelease, a suspended runtime-tier Kustomization (`applications`, `models`, `gateway`, `notifications`, `storage`) or `helm-repos`, or a lagging `lastAppliedRevision`. Restarting core does not help — Git is already right; fix the Flux layer (pre-flight scan in §6).

**Image pull failure — assume transient before acting**

`registry.ardge.xyz` and AWS S3 DNS failures during image pulls are usually transient (DNS hiccup). When ImagePullBackOff appears on a newly created pod during upgrade:

- First read `kubectl describe pod` — look for the actual reason ("dial tcp: lookup ... Try again" = DNS; "manifest unknown" = bad tag; "unauthorized" = credentials).
- For DNS / "Try again", let kubelet's exponential backoff retry (up to ~5 min between attempts). Verify recovery by `nslookup` from host and from a healthy pod in the same namespace before deciding the cluster DNS is actually broken.
- Only intervene if multiple backoff windows pass with persistent failure, or `describe pod` shows a non-transient reason.

**API error vs configmap state — cause vs symptom**

When both are present: check whether core is performing a precondition check before starting a new upgrade. If so, the API error is a symptom; the configmap state is the root cause.

---

## 5. Action rules

Anchored to the global rule **"Destructive Actions → always confirm"** in `~/.claude/rules/x-user-rules.md` §4. This section is the ARX-upgrade-specific application:

- **Read-only actions** (kubectl get / describe / logs, systemctl status, journalctl): execute directly
- **Modifying actions** (patch HelmRelease, delete configmap, restart pod, patch kustomization suspend, trigger reconcile): **report findings first, then ask for confirmation** before executing
  - Examples: `kubectl patch helmrelease`, `kubectl patch configmap upgrade-state`, `kubectl delete pod`, `kubectl patch kustomization`, `kubectl annotate kustomization ... reconcile.fluxcd.io/requestedAt`, `kubectl rollout restart`
  - This applies even when the fix looks obvious
  - **Confirm each modifying action separately**. Do not bundle multiple modifying actions into a single approval — even a plan-mode `ExitPlanMode` covering several modifying actions still requires confirming each one as you reach it.

---

## 6. Stuck-state recovery patterns

After analysis identifies one of these patterns, apply the matching recovery sequence. Order matters — skipping or reordering can leave the system in a worse state than before.

### Decision tree (pick the right pattern)

```
1. Pre-flight scan: any HelmRelease / Kustomization with spec.suspend=true?
   YES → "Suspended GitOps objects" — unsuspend with approval, then re-check upgrade-state.
         Often the upgrade self-resumes after un-suspend; no further action needed.

2. Upgrade-state.action is UPGRADE_ACTION_DOWNLOAD?
   → Not a deploy stall yet — see "Read `action` first" in §4 (image pull vs pre-stage Flux sync).
     Core log has no active upgrade and shows `Background task error … recover: refetch` → step 5, zombie.
     Steps 3–4 apply only to other actions.

3. Upgrade-state.target names a host service (arx-manager / discover / hal / console)?
   → Check SUC Plan Complete= and systemctl status. Bad → fix on host. Good → upstream/zombie.

4. Upgrade-state.target names a k8s helm-managed service (arx-platform-core / arx-platform-api / web / oauth2 / flux / ...)?
   → Check that HelmRelease Ready=, generation drift, helm-controller log.
     Bad → fix HR (unsuspend / resolve timeout / patch values). Good → upstream/zombie.

5. Everything downstream is healthy (SUC Complete, HR Ready, pods Running on new image)
   but upgrade-state still shows state=running with stuck progress:
   - If new versions confirmed live → "Physically complete but state stuck" — patch state=completed.
   - If versions did NOT advance → "Zombie upgrade-state" — restart core to resume, or clear + restart (atomic) to abandon.
```

### Pre-flight scan (run BEFORE any recovery action)

Most "stuck upgrades" on dev/test machines are not zombie state — they are GitOps objects intentionally suspended. Restarting / clearing without first finding the suspends will just stall again on the ones an upgrade does not clear (HelmReleases, runtime-tier Kustomizations, `helm-repos`, and the root `flux-system` Kustomization — which blocks only the objects the root applies itself, not the domains' own revisions).

```bash
# Scan every namespace for suspended HelmReleases and Kustomizations
kubectl get hr,kustomization -A -o json | python3 -c "
import json, sys
for i in json.load(sys.stdin)['items']:
    if i.get('spec', {}).get('suspend'):
        kind = i['kind']
        ns = i['metadata']['namespace']
        name = i['metadata']['name']
        print(f'SUSPENDED {kind} {ns}/{name}')
"
```

If anything is found: **ask the user whether the suspend is intentional** (e.g. dev pinning a version) BEFORE un-suspending. If they want to keep the version pinned, the answer is "do not trigger upgrade on this machine" — not "force recovery." Tell them the suspend itself is not a durable pin. Triggering an upgrade — and restarting core while `state=running`, which resumes one — clears `spec.suspend` on the GitRepository and the base-tier Kustomizations (`platform`, `infrastructure`, `systemd`, `k3s`) before its first deploy stage. The root `flux-system` Kustomization is not among them. Separately, on a Kustomization that carries the label `kustomize.toolkit.fluxcd.io/name: flux-system` (e.g. `platform`), the `flux-system` Kustomization's next apply (every 10 min) removes `spec.suspend` (observed 2026-09-21 on one machine; whether a HelmRelease's own suspend is removed the same way is unverified). The durable pin is the GitOps source: `clusters/<domain>/<ns>/<release>/release.yaml` `spec.chart.spec.version` (`<domain>` is the HelmRelease's `kustomize.toolkit.fluxcd.io/name` label — `platform` for the arx-system services, `infrastructure` for cilium / traefik / longhorn and the like) in the `flux-manifests` repo inside the `arx-flux-git-server` pod.

When un-suspending is approved:

```bash
kubectl patch kustomization <name> -n flux-system --type=merge -p '{"spec":{"suspend":false}}'
kubectl patch helmrelease <name> -n <ns> --type=merge -p '{"spec":{"suspend":false}}'
# trigger immediate reconcile instead of waiting for the next interval
kubectl annotate kustomization <name> -n flux-system reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
kubectl annotate helmrelease <name> -n <ns> reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

Note: each SUC Plan (`system-upgrade` ns) carries a `kustomize.toolkit.fluxcd.io/name` label naming the Kustomization that applies it; a suspend on that Kustomization freezes the Plan's updates even though the Plan itself shows `Complete=True`. Read it with `kubectl -n system-upgrade get plans -L kustomize.toolkit.fluxcd.io/name`. On the current layout the host-service Plans (`arx-manager` / `arx-discover` / `arx-hal` / `arx-console`) belong to `systemd` and `k3s-server` / `k3s-agent` to `k3s` (seen 2026-10-11 on 192.168.6.100, version 1.1.0-beta.6) — both are among the Kustomizations every upgrade run un-suspends. Older firmware applied them from the root `flux-system` Kustomization.

### Physically complete but state stuck running (UI escape hatch)

Symptom: all HelmReleases `Ready=True` at new chart versions, all SUC Plans `Complete=True`, core pod running new image (verify via `kubectl get pod -n arx-system -l app.kubernetes.io/name=arx-platform-core -o jsonpath="{.items[*].spec.containers[*].image}"`), but `upgrade-state` still shows `state=running` with some stuck `progress` value. UI stuck on "installing" screen.

This used to happen when `arx-platform-core` upgraded itself mid-flow and the orchestrator died with the old pod. Current core resumes in that case: on startup `recoverIfPending` (`upgrade.go`) sees `state=running`, re-fetches the manifest for `manifest_version`, and re-runs the upgrade to completion. So before patching, read the core log for why the resume has not finished (log lines under "Zombie upgrade-state" below) — a `completed` patched in while a resume is still running is overwritten by the resume's own result.

Fastest fix — patch `state=completed` to release the UI without re-running the orchestrator:

```bash
kubectl patch configmap upgrade-state -n arx-system --type=merge \
  -p '{"data":{"state":"completed","progress":"100","message":"","error_code":"UPGRADE_ERROR_CODE_UNSPECIFIED"}}'
```

Trade-off: this does NOT call `SaveMetadata(ctx, m.Spec.Version, m.Variant)`, so `arx-metadata` ConfigMap's `version` field will NOT be updated to the version that was just deployed. Next upgrade-availability check may then re-suggest the same version. If you need a clean `arx-metadata` record, use the Resume path under "Zombie upgrade-state" instead — the resumed run is the full orchestration, including `SaveMetadata`.

Use this escape hatch when: UI is the only blocker and the user accepts that the metadata record stays at the prior version.

### Zombie upgrade-state (state=running with no progress)

Symptom: configmap shows `state: running` with `progress` unchanged for tens of minutes; `core` log contains no active `UpgradeService/Upgrade` RPC, only `GetUpgradeStatus` polling. The pre-flight scan above must come back clean before reaching for this recovery.

**First decide whether the upgrade should resume.** A new core pod that finds `state: running` re-runs the upgrade itself (`recoverIfPending` → `runRecovery`), targeting the version in the configmap's `manifest_version` key:

| `manifest_version` | On core restart |
|---|---|
| set | re-fetches that release's manifest and runs the full upgrade again (idempotent; stages already at the target are skipped). Ends in `failed` instead if the manifest can never be read (message `upgrade could not resume: …`) or the GitOps source stays unavailable (message `upgrade could not resume because the GitOps source is unavailable; please retry`) |
| empty | flips `state` to `failed` with "upgrade was interrupted by service migration and cannot resume; please retry" |

**Resume** (the upgrade should finish): restart core only and leave the configmap alone.

```bash
kubectl rollout restart daemonset arx-platform-core -n arx-system
kubectl rollout status daemonset arx-platform-core -n arx-system
```

Then read the new pod's log:

| Log line | Meaning |
|---|---|
| `Resumed and completed upgrade interrupted by prior pod shutdown or node reboot` | Resumed and finished |
| `Upgrade recovery check completed` | Recovery returned without error: after the line above, alone when there was nothing to resume, or after one of the three `… FAILED …` give-up lines below. Read `state` to tell which |
| `Recovery attempt failed; kubelet will restart this pod and the next startup will retry recovery if upgrade-state remains RUNNING` | The resumed upgrade failed; it has already written `state=failed`, so the next startup does not retry (unless the pod was shutting down at the time — then `state` stays `running` and the next startup resumes again). Read `error_code` / `message` |
| `upgrade-state is RUNNING without a target version; cannot resume. Flipping to FAILED so the user can retry.` | Gave up: `manifest_version` was empty |
| `Upgrade recovery cannot read the target manifest and no retry will; flipping upgrade-state to FAILED` | Gave up: the release's manifest cannot be read on this device |
| `Upgrade recovery cannot create a deployer (GitOps source unavailable); flipping upgrade-state to FAILED so the user can retry` | Gave up: the Flux git source stayed unreachable through the retries |
| `Background task error` with `recover: refetch release …` / `recover: refetch manifest …` (and no `Upgrade recovery check completed` after it) | Recovery gave up without writing `failed`. `state` stays `running`, the pod keeps serving and is not restarted, so nothing retries until core is restarted again — this is the zombie this section is about |
| `Recovery fetch is unavailable; waiting to resume upgrade recovery` | Waiting on the device manager (release lookup or manifest key); repeats every 30s until it clears |
| `Flux repository is frozen by a cluster operation; waiting to resume upgrade recovery` | Waiting for a cluster operation (e.g. a restore) to release the Flux repo |

While recovery runs, a new upgrade request through the API waits for it (`waitForRecovery`).

**Abandon** (the upgrade should not resume): clear and restart. **Clear and restart are a SINGLE atomic step. Do not separate them.** Splitting leaves a window where the old core pod (still running) rewrites the configmap, defeating the clear. With the values empty, the new pod's recovery is a no-op.

```bash
# Clear VALUES while KEEPING the keys. The UI/state machine keys off field
# presence — wiping the keys themselves makes the UI display "no upgrade in
# progress" and you cannot observe recovery progress.
kubectl patch configmap upgrade-state -n arx-system --type=merge \
  -p '{"data":{"error_code":"","message":"","progress":"","state":""}}'

# IMMEDIATELY restart core (DaemonSet, not Deployment) in the SAME recovery step
kubectl rollout restart daemonset arx-platform-core -n arx-system
kubectl rollout status daemonset arx-platform-core -n arx-system
```

**Do NOT use `kubectl patch --type=json -p '[{"op":"replace","path":"/data","value":{}}]'`** — that removes the keys themselves, not just the values. Confirmed footgun, hit repeatedly in prior sessions.

After abandoning, start a fresh upgrade via the API (next section) if one is still wanted.

**Only restart `arx-platform-core`. Do NOT proactively restart other k8s services** (arx-platform-api / web / oauth2 / flux / redis). When the upgrade re-triggers, helm-controller will reconcile each HelmRelease and replace pods naturally as their charts advance. Pre-restarting them adds churn without helping recovery, and during a partial-upgrade state (see "arx-platform-api / core mismatch" below) it can push them off a known-good replica set.

### Re-triggering upgrade via API (when UI is broken)

UI is commonly white-screened during stuck/partial-upgrade states because `arx-platform-web` depends on `arx-platform-api` and `arx-oauth2`. The web pod's nginx passes `/api/` through to `arx-platform-api` unchanged. Its HTTPRoute attaches only to the traefik Gateway's HTTP listener (port 80), and only the node's InternalIP answers on it. (Older firmware served this under `:30080/arx/ng/api/v1/...`.)

```bash
# Check current vs available version
curl -sS 'http://<node-internal-ip>/api/v1/maintenance/upgrade-status' \
  -H 'Cookie: access_token=<token-from-browser-devtools>'

# Trigger upgrade to a specific version
curl -sS -X POST 'http://<node-internal-ip>/api/v1/maintenance/firmware-upgrade' \
  -H 'Content-Type: application/json' \
  -H 'Cookie: access_token=<token>' \
  -d '{"version":"<target>"}'
# Expected: {"apiVersion":"1.0","data":{"message":"firmware upgrade initiated"}}
```

Get `access_token` from browser DevTools (Application → Cookies on the cluster's UI origin) on any machine that still has a working UI session. The account needs the `cp-update:operate` permission.

The handler is `arx-platform-api` `internal/handler/v1/maintenance.go: UpgradeFirmware`, registered under `/api/v1/maintenance/firmware-upgrade` in `internal/handler/v1/routes.go`.

### arx-platform-api / core version mismatch from partial upgrade

Symptom: UI blank / "no shortcut to click". arx-platform-api logs:

```
grpc: failed to unmarshal the received message: string field contains invalid UTF-8
```

Cause: an earlier upgrade advanced `arx-platform-core` to a new chart version but the orchestrator stalled before advancing `arx-platform-api` (or vice versa). The two now hold incompatible proto schemas, and arx-platform-api can no longer parse core's response. The UI's `/web/desktop/shortcuts` call dies first because it returns a complex message.

Quick check:

```bash
kubectl get pods -n arx-system --sort-by=.metadata.creationTimestamp
# If core's AGE is minutes and arx-platform-api's is hours/days → mismatch confirmed.
```

Fix: complete the upgrade chain by re-triggering via the API above. The orchestrator will advance arx-platform-api/web/oauth2 to matching versions. Do NOT try to patch arx-platform-api's schema by hand or downgrade core piecewise — that just creates more divergence.

If re-triggering is not possible (e.g. version no longer available), `helm rollback arx-platform-core <previous-revision> -n arx-system` to restore core to the version arx-platform-api was compiled against.

### Transient ImagePullBackOff during upgrade

If a pod created mid-upgrade is in ImagePullBackOff and `describe pod` shows DNS "Try again" / temporary network errors: **wait, do not patch**. kubelet's backoff retries up to ~5 min apart. Recovery happens automatically once DNS or registry connectivity recovers. Verify by re-checking pod status after one or two backoff windows.

---

## 7. Report format

After completing collection and analysis, report using this structure:

```
## Upgrade Failure Report

**Root cause**: <one sentence>

**Layer status**:
- upgrade-state configmap: <state / error_code / progress / message>
- Flux GitOps: <Kustomizations all synced & not suspended / one is suspended / lagging revision>
- HelmReleases: <all OK / <name> failed — reason>
- SUC Plans: <all Complete=True / <name> not progressing>
- Pods: <all Running / issues>
- Manager (host service): <not involved / status>

**Proposed actions** (pending confirmation, each requires separate approval):
- <action 1>
- <action 2>

**Ready to retry upgrade**: Yes / No — <reason>

**Git source sync needed**: Yes (<what to change in the flux manifest repo>) / No
```
