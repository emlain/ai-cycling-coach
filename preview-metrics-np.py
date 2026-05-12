def compute_np(watts: Sequence[float | None], window_sec: int = 30) -> float | None:
    """Normalized Power per algoritmo Coggan.

    Pipeline:
      1. None/null → 0 (coasting)
      2. Media mobile {window_sec} secondi (rolling, trailing)
      3. Ogni valore elevato alla 4ª potenza
      4. Media dei valori elevati
      5. Radice 4ª finale

    Filosofia: penalizza esponenzialmente gli sforzi sopra avg →
    rappresenta meglio il "costo fisiologico" di workout variabili (intervalli, salite)
    rispetto a uno steady-state.

    Returns None se meno di {window_sec} samples disponibili.
    """
    if not watts or len(watts) < window_sec:
        return None

    cleaned = [float(w) if w is not None else 0.0 for w in watts]

    # Rolling sum O(n) tramite finestra scorrevole
    rolling: list[float] = []
    window_sum = sum(cleaned[:window_sec])
    rolling.append(window_sum / window_sec)
    for i in range(window_sec, len(cleaned)):
        window_sum += cleaned[i] - cleaned[i - window_sec]
        rolling.append(window_sum / window_sec)

    # Media 4ª potenza (escludiamo 0 per non drogare a basso)
    fourth_powers = [r ** 4 for r in rolling if r > 0]
    if not fourth_powers:
        return None
    mean_fp = sum(fourth_powers) / len(fourth_powers)
    return mean_fp ** 0.25