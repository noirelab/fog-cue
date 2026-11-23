"""Avalia OFFLINE os detectores de FoG do app (lib/fog, lib/signal) no Daphnet.

Como rodar (só numpy; o dataset fica fora do repositório):

    python3 -I scripts/avaliar_daphnet.py --selftest
    python3 -I scripts/avaliar_daphnet.py ~/datasets/daphnet/dataset_fog_release/dataset \
        --saida ~/datasets/daphnet_resultados [--sensor coxa] [--detector heuristic|freezeIndex|all]

Escolhas (ver também os comentários "DUVIDA"/"DECISAO" no código):
  * Sensor: coxa (upper leg). É o mais parecido com um celular no bolso da
    calça. Eixos do Daphnet não coincidem com os do celular, mas os dois
    detectores usam a magnitude do vetor, que não depende da orientação.
  * Unidades: Daphnet vem em mg a 64 Hz. Converte para m/s2 (x 9.80665e-3) e
    reamostra por interpolação linear para 50 Hz (sampleRateHz padrão do app),
    com timestamps inteiros em ms (i * 20), como a grade uniforme do app.
  * Rótulos: 0 = fora do experimento (ignorado), 1 = sem freeze, 2 = freeze.
    O rótulo vai para a grade de 50 Hz pelo vizinho mais próximo.
  * Verdade por janela: freeze se >= 50% das amostras rotuladas (1 ou 2) da
    janela forem 2; janelas com > 50% de amostras 0 são ignoradas.
  * Predição por janela: estado da máquina == FOG_DETECTED depois da janela
    (é o estado que dispara o cue no app).
  * Episódio = sequência contígua de rótulo 2. Detectado se houver um alarme
    (transição para FOG_DETECTED) numa janela cujo fim caia dentro do
    episódio; um estado FOG herdado de antes do episódio não conta. Latência =
    fim da janela do primeiro desses alarmes menos o início do episódio.
  * Alarme = transição para FOG_DETECTED (evento fogDetected do app). O
    cooldown do cue (5 s) não é aplicado. Falso alarme = alarme cujo instante
    cai em rótulo 1; a taxa é por minuto de caminhada rotulada sem freeze
    (rótulo 1), não por minuto de gravação.
"""
import argparse
import csv
import math
import sys
from pathlib import Path

import numpy as np

# Parâmetros: espelham defaultSettings em lib/config/experiment.dart.
PARAMS = dict(
    sample_rate_hz=50, window_size_ms=4000, window_overlap=0.75,
    fog_threshold=3.5, freeze_index_threshold=2.0, power_threshold=0.5,
    confirm_windows=2, recovery_windows=2,
)
LOCOMOTOR_BAND = (0.5, 3.0)
FREEZE_BAND = (3.0, 8.0)
COLUNAS_SENSOR = {"tornozelo": (1, 4), "coxa": (4, 7), "tronco": (7, 10)}  # colunas x,y,z
G_MG = 9.80665e-3  # mg -> m/s2

NORMAL, POSSIBLE, FOG, RECOVERY = "NORMAL", "POSSIBLE_FOG", "FOG_DETECTED", "RECOVERY"


# ---------------- lib/signal ----------------
def windower_ends(ts, window_ms, hop_ms):
    """Porta de Windower.push: devolve (índice_início, índice_fim) de cada janela.

    O buffer do Dart mantém uma amostra anterior ao início só para checar
    cobertura; a janela emitida contém apenas amostras com t >= end - window.
    """
    out, first, last_end = [], 0, None
    for i, end in enumerate(ts):
        start = end - window_ms
        while first < i and ts[first + 1] <= start:
            first += 1
        if end - ts[first] < window_ms:
            continue
        if last_end is not None and end - last_end < hop_ms:
            continue
        last_end = end
        s = first
        while ts[s] < start:
            s += 1
        out.append((s, i))
    return out


def resample_uniform(t, v, rate_hz):
    """resampleUniform: grade uniforme por interpolação linear (np.interp equivale
    ao clamp de 'a' em [0,1] do Dart para t estritamente crescente)."""
    if len(t) < 2:
        return np.asarray(v, float)
    step = 1000 / rate_hz
    n = int(math.floor((t[-1] - t[0]) / step)) + 1
    return np.interp(t[0] + np.arange(n) * step, t, v)


def power_spectrum(x, rate_hz):
    """powerSpectrum: Hann (n-1), zero padding até potência de 2, escala de Parseval."""
    n = len(x)
    m = 1
    while m < max(n, 2):
        m <<= 1
    w = np.ones(1) if n == 1 else 0.5 - 0.5 * np.cos(2 * np.pi * np.arange(n) / (n - 1))
    energy = float(np.sum(w * w))
    half = m // 2
    power = np.zeros(half + 1)
    if energy > 0:
        X = np.fft.rfft(np.asarray(x) * w, n=m)
        one = np.full(half + 1, 2.0)
        one[0] = one[half] = 1.0
        power = one * (X.real ** 2 + X.imag ** 2) / (m * energy)
    return power, rate_hz / m


def band(power, bin_hz, lo, hi):
    f = np.arange(len(power)) * bin_hz
    return float(power[(f >= lo) & (f < hi)].sum())


def freeze_features(t, mag, rate_hz):
    u = resample_uniform(t, mag, rate_hz)
    p, b = power_spectrum(u - u.mean(), rate_hz)
    loc, frz = band(p, b, *LOCOMOTOR_BAND), band(p, b, *FREEZE_BAND)
    return dict(locomotor_power=loc, freeze_power=frz, total_power=loc + frz,
                freeze_index=frz / max(loc, 1e-9))


# ---------------- lib/fog ----------------
def detect_heuristic(t, mag, prm):
    """HeuristicFogDetector: std populacional (ddof=0) da magnitude > fogThreshold."""
    v = float(np.std(mag)) if len(mag) else float("nan")
    return math.isfinite(v) and v > prm["fog_threshold"]


def detect_freeze_index(t, mag, prm):
    """FreezeIndexDetector: precisa de >= 8 amostras, potência >= limiar e FI > limiar."""
    if len(mag) < 8:
        return False
    f = freeze_features(t, mag, prm["sample_rate_hz"])
    return f["total_power"] >= prm["power_threshold"] and f["freeze_index"] > prm["freeze_index_threshold"]


DETECTORES = {"heuristic": detect_heuristic, "freezeIndex": detect_freeze_index}


class FogStateMachine:
    """Porta literal de lib/fog/state_machine.dart."""

    def __init__(self, confirm_windows, recovery_windows):
        self.confirm, self.recovery = confirm_windows, recovery_windows
        self.state, self.pos, self.neg = NORMAL, 0, 0

    def update(self, detected):
        frm = self.state
        self.state = self._next(detected)
        return frm, self.state

    def _next(self, d):
        s = self.state
        if s in (NORMAL, POSSIBLE):
            if not d:
                self.pos = 0
                return NORMAL
            self.pos += 1
            return FOG if self.pos >= self.confirm else POSSIBLE
        if s == FOG:
            if d:
                return FOG
            self.neg = 0
            return RECOVERY
        if d:  # RECOVERY
            return FOG
        self.neg += 1
        if self.neg >= self.recovery:
            self.pos = 0
            return NORMAL
        return RECOVERY


def run_detector(ts, mag, prm, detector):
    """Roda janelamento + detector + máquina. Devolve lista (idx_ini, idx_fim, estado, alarme)."""
    hop = prm["window_size_ms"] * (1 - prm["window_overlap"])
    sm = FogStateMachine(prm["confirm_windows"], prm["recovery_windows"])
    out = []
    for s, e in windower_ends(ts, prm["window_size_ms"], hop):
        frm, to = sm.update(detector(ts[s:e + 1], mag[s:e + 1], prm))
        out.append((s, e, to, to == FOG and frm != FOG))
    return out


# ---------------- Daphnet ----------------
def carregar(path, sensor, rate_hz):
    """Lê um arquivo Daphnet e devolve (ts_ms, magnitude m/s2, rótulos) a rate_hz."""
    d = np.loadtxt(path, dtype=float)  # dado externo: só parse numérico
    if d.ndim != 2 or d.shape[1] != 11 or not np.isfinite(d).all():
        raise ValueError(f"formato inesperado em {path}")
    a, b = COLUNAS_SENSOR[sensor]
    t0 = d[:, 0]  # ms
    mag0 = np.linalg.norm(d[:, a:b], axis=1) * G_MG
    n = int((t0[-1] - t0[0]) // (1000 / rate_hz)) + 1
    ts = np.arange(n) * (1000 / rate_hz)  # DECISAO: grade inteira em ms (20 ms a 50 Hz)
    ts = np.round(ts)
    mag = np.interp(ts + t0[0], t0, mag0)
    idx = np.clip(np.searchsorted(t0, ts + t0[0]), 1, len(t0) - 1)
    near = np.where(np.abs(t0[idx] - (ts + t0[0])) < np.abs(t0[idx - 1] - (ts + t0[0])), idx, idx - 1)
    return ts, mag, d[near, 10].astype(int)


def episodios(lab):
    """(início_idx, fim_idx) inclusivos de cada sequência contígua de rótulo 2."""
    m = np.concatenate([[0], (lab == 2).astype(int), [0]])
    d = np.diff(m)
    return list(zip(np.where(d == 1)[0], np.where(d == -1)[0] - 1))


def avaliar(ts, mag, lab, prm, detector):
    wins = run_detector(ts, mag, prm, detector)
    r = dict(tp=0, fp=0, tn=0, fn=0, ep=0, ep_det=0, lat=[], alarmes_falsos=0, min_sem_freeze=0.0)
    dt = ts[1] - ts[0]
    for s, e, state, alarm in wins:
        w = lab[s:e + 1]
        if (w == 0).mean() > 0.5:
            continue
        truth = (w == 2).sum() / max((w > 0).sum(), 1) >= 0.5
        pred = state == FOG
        r["tp" if truth and pred else "fn" if truth else "fp" if pred else "tn"] += 1
        if alarm and lab[e] == 1:
            r["alarmes_falsos"] += 1
    r["min_sem_freeze"] = (lab == 1).sum() * dt / 60000
    for i0, i1 in episodios(lab):
        r["ep"] += 1
        hit = [e for s, e, _, alarm in wins if alarm and i0 <= e <= i1]
        if hit:
            r["ep_det"] += 1
            r["lat"].append((ts[hit[0]] - ts[i0]) / 1000)
    return r


def somar(rs):
    out = dict(tp=0, fp=0, tn=0, fn=0, ep=0, ep_det=0, lat=[], alarmes_falsos=0, min_sem_freeze=0.0)
    for r in rs:
        for k in out:
            out[k] = out[k] + r[k]
    return out


def linha(nome, r):
    div = lambda a, b: a / b if b else float("nan")
    lat = np.array(r["lat"])
    q = (lambda p: float(np.percentile(lat, p))) if len(lat) else (lambda p: float("nan"))
    return dict(
        id=nome, janelas_freeze=r["tp"] + r["fn"], janelas_normal=r["tn"] + r["fp"],
        sens_janela=div(r["tp"], r["tp"] + r["fn"]), espec_janela=div(r["tn"], r["tn"] + r["fp"]),
        episodios=r["ep"], detectados=r["ep_det"], sens_episodio=div(r["ep_det"], r["ep"]),
        lat_mediana_s=q(50), lat_p25_s=q(25), lat_p75_s=q(75), lat_max_s=float(lat.max()) if len(lat) else float("nan"),
        falsos_alarmes=r["alarmes_falsos"], falsos_alarmes_por_min=div(r["alarmes_falsos"], r["min_sem_freeze"]),
    )


def imprimir(rows):
    cols = list(rows[0])
    fmt = lambda v: f"{v:.3f}" if isinstance(v, float) else str(v)
    tab = [cols] + [[fmt(r[c]) for c in cols] for r in rows]
    w = [max(len(l[i]) for l in tab) for i in range(len(cols))]
    for l in tab:
        print("  ".join(c.rjust(w[i]) for i, c in enumerate(l)))


# ---------------- teste mínimo ----------------
def selftest():
    prm = PARAMS
    ts = np.arange(0, 60000, 20.0)
    parado = np.full(len(ts), 9.80665)
    for det in DETECTORES.values():
        assert not any(w[3] or w[2] == FOG for w in run_detector(ts, parado, prm, det)), "parado nao pode alarmar"
    # janelamento: 4 s a cada 1 s a 50 Hz => primeira janela termina em 4 s
    ws = windower_ends(ts, 4000, 1000)
    assert ts[ws[0][1]] == 4000 and ts[ws[1][1]] == 5000 and ws[0][1] - ws[0][0] == 200
    # Parseval: seno de amplitude A tem potência ~ A^2/2 na banda certa
    x = 2 * np.sin(2 * np.pi * 5 * np.arange(201) / 50)
    p, b = power_spectrum(x - x.mean(), 50)
    assert abs(band(p, b, 3, 8) - 2.0) < 0.2
    # tremor de 5 Hz: FI alto, alarme depois de confirm_windows=2 janelas
    tremor = 9.80665 + 2 * np.sin(2 * np.pi * 5 * ts / 1000)
    al = [w for w in run_detector(ts, tremor, prm, detect_freeze_index) if w[3]]
    assert al and ts[al[0][1]] == 5000, "alarme esperado na 2a janela (fim em 5 s)"
    # marcha de 1,5 Hz: energia locomotora, FI baixo, sem alarme
    marcha = 9.80665 + 2 * np.sin(2 * np.pi * 1.5 * ts / 1000)
    assert not any(w[3] for w in run_detector(ts, marcha, prm, detect_freeze_index))
    # máquina de estados (confirm=2, recovery=2)
    sm = FogStateMachine(2, 2)
    seq = [sm.update(d)[1] for d in [1, 0, 1, 1, 1, 0, 1, 0, 0, 0]]
    assert seq == [POSSIBLE, NORMAL, POSSIBLE, FOG, FOG, RECOVERY, FOG, RECOVERY, RECOVERY, NORMAL], seq
    print("selftest ok")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("dados", nargs="?", help="pasta com S01R01.txt ... (dado não confiável, só lido)")
    ap.add_argument("--saida", default="resultados_daphnet")
    ap.add_argument("--sensor", choices=COLUNAS_SENSOR, default="coxa")
    ap.add_argument("--detector", choices=[*DETECTORES, "all"], default="all")
    ap.add_argument("--selftest", action="store_true")
    a = ap.parse_args()
    selftest()
    if a.selftest or not a.dados:
        return
    arqs = sorted(Path(a.dados).glob("S[0-9][0-9]R[0-9][0-9].txt"))
    if not arqs:
        sys.exit("nenhum arquivo SxxRxx.txt encontrado")
    saida = Path(a.saida)
    saida.mkdir(parents=True, exist_ok=True)
    dados = {p.stem: carregar(p, a.sensor, PARAMS["sample_rate_hz"]) for p in arqs}
    for nome in (DETECTORES if a.detector == "all" else [a.detector]):
        por_arq = {k: avaliar(*v, PARAMS, DETECTORES[nome]) for k, v in dados.items()}
        por_suj = {}
        for k, r in por_arq.items():
            por_suj.setdefault(k[:3], []).append(r)
        rows = [linha(k, r) for k, r in por_arq.items()]
        rows += [linha(k, somar(v)) for k, v in sorted(por_suj.items())]
        rows.append(linha("TODOS", somar(por_arq.values())))
        print(f"\n== {nome} | sensor={a.sensor} | {PARAMS}")
        imprimir(rows)
        with open(saida / f"daphnet_{nome}_{a.sensor}.csv", "w", newline="") as f:
            wr = csv.DictWriter(f, fieldnames=list(rows[0]))
            wr.writeheader()
            wr.writerows(rows)
    print(f"\nCSV em {saida}")


if __name__ == "__main__":
    main()
