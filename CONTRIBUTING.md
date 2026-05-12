# Contributing

## Branch naming

- `feat/<short-description>` — nuove funzionalità
- `fix/<short-description>` — bug fix
- `docs/<short-description>` — solo documentazione
- `chore/<short-description>` — manutenzione, build, CI
- `scaffold/<sprint>` — scaffold dei vari sprint

## Commit messages

[Conventional Commits](https://www.conventionalcommits.org/) consigliato:

```
feat(backend): add NP and IF computation
fix(ingest): handle missing wellness fields
docs: update architecture diagram
chore(ci): bump python to 3.12
```

## Pull Requests

- Titolo conciso ma descrittivo
- Descrizione: cosa cambia, perché, come testarlo
- Linka issue correlate con `Closes #N`
- Squash merge preferito per mantenere `main` lineare

## Code style

- Python: `ruff` per lint + format (configurato in CI)
- TS: prettier + eslint (verrà aggiunto con il frontend)
- Type hints OBBLIGATORI sul codice Python di produzione
