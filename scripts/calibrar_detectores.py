"""Calibra os limiares dos detectores com o Daphnet e com sessões do celular.

Como rodar (só numpy; dados ficam fora do repositório):

    python3 -I scripts/calibrar_detectores.py \
        ~/datasets/daphnet/dataset_fog_release/dataset \
        ~/datasets/fogcue_celular/2026-10-07/fogcue.db \
        --negativas 20261007-100207

  * Daphnet (coxa): mede sensibilidade por episódio, especificidade por janela
    e falsos alarmes por minuto, como scripts/avaliar_daphnet.py.
  * Celular: as sessões em --negativas são caminhada normal, sem freezing;
    qualquer alarme nelas é falso positivo. Alarmes antes de --aquecimento-s
    são ignorados (tempo de guardar o celular no bolso), como no app.

As features de cada janela não dependem dos limiares: são calculadas uma vez
por configuração de janela e os limiares são varridos em cima delas.
"""
import argparse
import itertools
import sqlite3
import sys
from pathlib import Path

import numpy as np

# -I não põe a pasta do script no sys.path; o módulo irmão é código nosso.
sys.path.insert(0, str(Path(__file__).resolve().parent))
import avaliar_daphnet as ad  # noqa: E402

JANELAS = [(2000, 0.5), (4000, 0.75)]
FI_LIMIARES = [1.5, 2.0, 2.5, 3.0, 4.0]
POT_LIMIARES = [0.2, 0.5, 1.0, 2.0]
HEUR_LIMIARES = [3.5, 5.0, 7.0]


def features(ts, mag, window_ms, overlap, rate_hz=50):
    """Por janela: (idx_ini, idx_fim, desvio padrão, energia total, freeze index)."""
    out = []
    for s, e in ad.windower_ends(ts, window_ms, window_ms * (1 - overlap)):
        t, m = ts[s:e + 1], mag[s:e + 1]
        f = ad.freeze_features(t, m, rate_hz) if len(m) >= 8 else dict(total_power=0.0, freeze_index=0.0)
        out.append((s, e, float(np.std(m)), f["total_power"], f["freeze_index"]))
    return np.array(out) if out else np.empty((0, 5))


def estados(detectado, confirm=2, recovery=2):
    sm = ad.FogStateMachine(confirm, recovery)
    st, alarme = [], []
    for d in detectado:
        frm, to = sm.update(bool(d))
        st.append(to)
        alarme.append(to == ad.FOG and frm != ad.FOG)
    return np.array(st), np.array(alarme)


def avaliar_daphnet(feat_por_arq, dados, detecta):
    tot = dict(tp=0, fp=0, tn=0, fn=0, ep=0, ep_det=0, lat=[], alarmes_falsos=0, min_sem_freeze=0.0)
    for nome, F in feat_por_arq.items():
        ts, _, lab = dados[nome]
        st, alarme = estados(detecta(F))
        idx_e = F[:, 1].astype(int)
        for (s, e), state, al in zip(F[:, :2].astype(int), st, alarme):
            w = lab[s:e + 1]
            if (w == 0).mean() > 0.5:
                continue
            truth = (w == 2).sum() / max((w > 0).sum(), 1) >= 0.5
            pred = state == ad.FOG
            tot["tp" if truth and pred else "fn" if truth else "fp" if pred else "tn"] += 1
            if al and lab[e] == 1:
                tot["alarmes_falsos"] += 1
        tot["min_sem_freeze"] += (lab == 1).sum() * (ts[1] - ts[0]) / 60000
        for i0, i1 in ad.episodios(lab):
            tot["ep"] += 1
            # Só conta alarme dentro do episódio: FOG herdado de antes não vale.
            hit = idx_e[alarme & (idx_e >= i0) & (idx_e <= i1)]
            if len(hit):
                tot["ep_det"] += 1
                tot["lat"].append((ts[hit[0]] - ts[i0]) / 1000)
    return ad.linha("daphnet", tot)


def alarmes_celular(F, ts, detecta, aquecimento_ms):
    """Como no app: janelas que começam antes do fim do aquecimento não entram
    na detecção (contam como "não detectado" para a máquina de estados)."""
    ini = ts[F[:, 0].astype(int)]
    _, alarme = estados(detecta(F) & (ini - ts[0] >= aquecimento_ms))
    return int(alarme.sum())


def carregar_celular(db, sessao):
    """Amostras de uma única sessão, pelo prefixo do id. Magnitude nula (o app
    grava NULL quando o valor não é finito) fica de fora."""
    c = sqlite3.connect(f"file:{db}?mode=ro", uri=True)
    ids = [r[0] for r in c.execute("select id from sessions where id like ?", (sessao + "%",))]
    if len(ids) != 1:
        sys.exit(f"o prefixo {sessao} casa com {len(ids)} sessões em {db}; use um prefixo único")
    r = np.array(c.execute(
        "select timestamp, acc_magnitude from samples where session_id = ? and acc_magnitude is not null "
        "order by timestamp", (ids[0],)
    ).fetchall(), dtype=float)
    if not len(r):
        sys.exit(f"sessão {sessao} sem amostras em {db}")
    return r[:, 0], r[:, 1]


def selftest():
    # Parado nunca alarma; tremor de 5 Hz alarma pelo FI; marcha de 1,5 Hz não.
    ts = np.arange(0, 30000, 20.0)
    for sinal, esperado in [
        (np.full(len(ts), 9.81), 0),
        (9.81 + 2 * np.sin(2 * np.pi * 5 * ts / 1000), 1),
        (9.81 + 2 * np.sin(2 * np.pi * 1.5 * ts / 1000), 0),
    ]:
        F = features(ts, sinal, 4000, 0.75)
        n = alarmes_celular(F, ts, lambda F: (F[:, 3] >= 0.2) & (F[:, 4] > 2.0), 0)
        assert n == esperado, (n, esperado)
    print("selftest ok")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("daphnet")
    ap.add_argument("db")
    ap.add_argument("--negativas", nargs="+", required=True, help="prefixos de id de sessões só com caminhada normal")
    ap.add_argument("--aquecimento-s", type=float, default=15)
    a = ap.parse_args()
    selftest()

    arqs = sorted(Path(a.daphnet).glob("S[0-9][0-9]R[0-9][0-9].txt"))
    dados = {p.stem: ad.carregar(p, "coxa", 50) for p in arqs}
    negativas = {s: carregar_celular(a.db, s) for s in a.negativas}

    linhas = []
    for win, ovl in JANELAS:
        fd = {k: features(ts, mag, win, ovl) for k, (ts, mag, _) in dados.items()}
        fc = {k: (features(ts, mag, win, ovl), ts) for k, (ts, mag) in negativas.items()}
        candidatos = [(f"heur std>{h}", lambda F, h=h: F[:, 2] > h) for h in HEUR_LIMIARES]
        candidatos += [
            (f"FI>{fi} pot>={pt}", lambda F, fi=fi, pt=pt: (F[:, 3] >= pt) & (F[:, 4] > fi))
            for fi, pt in itertools.product(FI_LIMIARES, POT_LIMIARES)
        ]
        for nome, detecta in candidatos:
            r = avaliar_daphnet(fd, dados, detecta)
            cel = sum(alarmes_celular(F, ts, detecta, a.aquecimento_s * 1000) for F, ts in fc.values())
            linhas.append(dict(janela=f"{win / 1000:.0f}s/{ovl}", detector=nome,
                               sens_ep=r["sens_episodio"], espec=r["espec_janela"],
                               fa_min=r["falsos_alarmes_por_min"], lat_med=r["lat_mediana_s"],
                               alarmes_caminhada=cel))
    linhas.sort(key=lambda l: (l["alarmes_caminhada"] > 0, -l["sens_ep"]))
    ad.imprimir(linhas)


if __name__ == "__main__":
    main()
