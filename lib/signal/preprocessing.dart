import '../core/imu.dart';

/// Etapa de pré-processamento: recebe uma janela e devolve outra janela no
/// mesmo formato (por exemplo filtrada ou sem gravidade).
///
/// Etapas previstas: remoção de gravidade, passa-baixa, passa-alta,
/// passa-banda. Cada uma deve ser uma função pura deste tipo, para poder ser
/// testada isoladamente e reproduzida em Python com o mesmo resultado.
typedef Preprocessor = SignalWindow Function(SignalWindow window);

/// Aplica as etapas em ordem. Com a lista vazia, devolve a janela intacta.
SignalWindow preprocess(SignalWindow window, List<Preprocessor> steps) =>
    steps.fold(window, (w, step) => step(w));
