# FoG Cue

Aplicativo Android (Flutter) experimental de um Trabalho de Conclusão de Curso
sobre **Freezing of Gait (FoG)** na Doença de Parkinson.

> Projeto acadêmico e experimental. O aplicativo **não é dispositivo médico**,
> não faz diagnóstico e não substitui acompanhamento profissional.

## 1. Objetivo

Investigar em que medida técnicas clássicas de processamento de sinais e
modelos leves de aprendizado de máquina, executados no próprio smartphone,
detectam episódios de FoG em sinais inerciais com desempenho e latência
adequados para acionar pistas sensoriais (vibração e metrônomo) em tempo real.

Esta primeira versão é a **infraestrutura**: aquisição de IMU, janelamento,
features, contrato de detector substituível, máquina de estados, Cue Engine,
registro de sessões e exportação para Python. Nenhum modelo foi treinado; o
detector heurístico existe só para testar a pipeline.

## 2. Arquitetura

```
Acelerômetro + giroscópio (sensors_plus)
  -> imu_service (fusão, timestamp do sensor)
  -> Windower (buffer circular, janelas por tempo, sobreposição)
  -> pré-processamento (lista de etapas, vazia nesta versão)
  -> features
  -> FogDetector (Mock | Heurístico | futuros modelos)
  -> FogStateMachine (NORMAL, POSSIBLE_FOG, FOG_DETECTED, RECOVERY)
  -> CueEngine (cooldown) -> vibração + metrônomo

Em paralelo: amostras e eventos -> SessionLogger (lotes) -> SQLite -> CSV/JSON
```

Detalhes e diagramas em [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## 3. Stack

| Necessidade | Pacote |
| --- | --- |
| Base | Flutter 3.47, Dart 3.13 |
| Acelerômetro e giroscópio | sensors_plus |
| Vibração | vibration |
| Metrônomo | audioplayers (modo de baixa latência) |
| Banco local | sqflite |
| Exportação | path_provider + share_plus |
| Tela ligada durante a sessão | wakelock_plus |
| Versão do app nos metadados | package_info_plus |
| Ícones | lucide_icons_flutter |
| Testes | flutter_test + fake_async + clock |

Gráficos são desenhados com `CustomPainter`, sem biblioteca. Sem backend,
login, analytics ou nuvem: tudo fica no aparelho, e a exportação só acontece
quando você escolhe o destino na tela de compartilhamento do Android.

## 4. Instalação do ambiente (Linux, sem root)

O ambiente fica em `~/devtools` (Flutter, JDK 17 e Android SDK). Em cada
terminal novo:

```bash
source ~/devtools/env.sh
```

Uma única vez, aceite as licenças do Android SDK:

```bash
yes | sdkmanager --licenses
```

Depois, na pasta do projeto:

```bash
flutter pub get
```

## 5. Executar, testar e compilar

```bash
flutter test            # testes (rodam sem celular)
dart analyze            # análise estática
flutter build apk --release
```

O APK fica em `build/app/outputs/flutter-apk/app-release.apk`.

## 6. Instalar no celular

- **Pelo arquivo:** copie o `app-release.apk` para o celular (cabo, Drive,
  Telegram etc.), abra e permita "instalar apps desconhecidos" quando o
  Android pedir.
- **Pelo cabo:** ative "Depuração USB" nas opções de desenvolvedor, conecte
  e rode `flutter install` (ou `flutter run` para ver logs ao vivo).

O APK de release é assinado com a chave de debug, o que é suficiente para
testes. Para publicar em loja seria preciso uma chave própria.

### Roteiro de teste manual

1. Home: os dois sensores aparecem como "disponível".
2. Configurações: "Testar cue por 4 s" vibra e toca o metrônomo.
3. Nova sessão, Iniciar: os gráficos andam e a taxa real fica perto de 50 Hz.
4. Modo pesquisa, "Simular FoG": FOG_DETECTED, cue toca, depois RECOVERY e NORMAL.
5. Detector Heurístico: sacudir o celular leva a POSSIBLE_FOG e FOG_DETECTED.
6. Encerrar sessão, "Exportar CSV e JSON" e abrir os arquivos no Python (seção 9).

## 7. Estrutura

```
lib/
  main.dart                 app, tema claro/escuro
  app_settings.dart         configurações carregadas do banco
  config/experiment.dart    parâmetros experimentais, limites e validação
  core/                     ImuSample, SignalWindow, Vector3, relógio
  signal/                   CircularBuffer, Windower, features, preprocessing
  fog/                      FogDetector, FogStateMachine, detectores
  cues/cue_engine.dart      metrônomo com cooldown
  sessions/                 modelos, SessionLogger, serialização CSV/JSON
  monitoring/               MonitoringEngine (liga a pipeline toda)
  services/                 sensores, vibração/áudio, SQLite, exportação
  ui/                       tema, componentes, gráfico, formatação
  screens/                  Home, Nova sessão, Monitoramento, Histórico,
                            Detalhe da sessão, Configurações
test/                       testes da lógica (sem celular)
assets/sounds/click.wav     clique do metrônomo
legacy-expo/                primeira versão (React Native/Expo), só referência
```

## 8. Pipeline

- **Aquisição**: acelerômetro (m/s², com gravidade) e giroscópio (rad/s) na
  frequência `sampleRateHz`. O acelerômetro dita o ritmo; cada amostra leva a
  leitura mais recente do giroscópio. O timestamp vem do relógio do sensor.
- **Janelamento**: janelas de `windowSizeMs` a cada
  `windowSizeMs * (1 - windowOverlap)`. Padrão: 4 s, com um resultado novo a cada 1 s.
- **Pré-processamento**: lista de funções janela para janela, vazia por ora.
- **Features**: média, desvio padrão (ddof=0, igual ao NumPy), RMS, mínimo e
  máximo da magnitude do acelerômetro; e as features espectrais do Freeze
  Index (FFT com janela de Hann, energia nas bandas 0,5 a 3 Hz e 3 a 8 Hz).
- **Detector** (escolhido nas configurações):
  - `HeuristicFogDetector` (padrão): limiar no desvio padrão da magnitude;
    **somente teste, sem validade clínica**.
  - `FreezeIndexDetector`: Freeze Index (Moore et al., 2008; Bächlin et al.,
    2010) com limiar de energia para separar "parado" de "congelado". Nos
    testes no bolso ficou sensível demais com os limiares iniciais.
  - `MockFogDetector`: nunca detecta (episódios só via "Simular FoG").
- **Máquina de estados**: `confirmWindows` janelas positivas para confirmar e
  `recoveryWindows` negativas para encerrar o episódio.
- **Cue Engine**: dispara em FOG_DETECTED, respeitando `cueCooldownMs`.
- **Latência**: `processingLatency = detecção - fim da janela` e
  `cueLatency = início do cue - fim da janela`, gravadas nos eventos.

## 9. Formato dos dados exportados

Cada sessão gera três arquivos abertos:

**`session_<id>_samples.csv`**

| Coluna | Unidade / valores |
| --- | --- |
| timestamp | ms desde 1970 (Unix epoch, com fração) |
| acc_x, acc_y, acc_z | m/s² (inclui gravidade) |
| acc_magnitude | m/s², sqrt(x² + y² + z²) |
| gyro_x, gyro_y, gyro_z | rad/s (vazio antes da primeira leitura do giroscópio) |
| fog_state | NORMAL, POSSIBLE_FOG, FOG_DETECTED, RECOVERY |
| fog_confidence | 0 a 1 (última janela analisada) |
| cue_triggered | 1 enquanto um cue está tocando, senão 0 |

**`session_<id>_events.csv`**: `timestamp,type,metadata`. Tipos:
SESSION_STARTED, SESSION_FINISHED, FOG_POSSIBLE, FOG_DETECTED, CUE_STARTED,
CUE_FINISHED, RECOVERY. `metadata` é JSON em texto (latências, confiança,
`simulated: true` no FoG simulado, duração do episódio).

**`session_<id>_metadata.json`**: sessão, participante, posição,
observações, `sampleRate`, `windowSize`, `windowOverlap`, `detectorName`,
`detectorVersion`, `cueSettings`, `appVersion`, plataforma, todas as
configurações e unidades.

```python
import json
import pandas as pd

samples = pd.read_csv("session_<id>_samples.csv")
events = pd.read_csv("session_<id>_events.csv")
events["metadata"] = events["metadata"].apply(json.loads)
meta = json.load(open("session_<id>_metadata.json"))

samples["t"] = (samples["timestamp"] - samples["timestamp"].iloc[0]) / 1000  # segundos
fs = meta["metadata"]["sampleRate"]
```

## Limitações conhecidas

- A coleta só ocorre com o app aberto em primeiro plano (a tela fica ligada).
- A taxa real varia em torno da pedida; o CSV guarda o timestamp de cada
  amostra para reamostragem em Python.
- O metrônomo usa `Timer` do Dart (jitter de alguns ms por beat).
- A exportação monta os arquivos inteiros em memória.
