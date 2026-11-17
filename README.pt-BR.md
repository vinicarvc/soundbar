# SoundBar

App nativo de menubar para macOS (Swift + SwiftUI) para controlar o som: escolher o dispositivo de saída,
ajustar o volume geral e **o volume e a saída de cada app**.

## Recursos
- Volume geral e mudo
- Troca do dispositivo de saída e do dispositivo de sons do sistema
- Volume e saída por app (ex.: Spotify na caixa, Chrome no AirPods)
- Configurações por app salvas entre execuções
- Sem driver virtual: usa process taps do Core Audio

## Requisitos
macOS 14.2+, Xcode command line tools.

## Compilar e rodar
```bash
./build.sh
open build/SoundBar.app
```
Na primeira alteração por app, o macOS pede permissão de **captura de áudio**.

## Limitações
Veja a seção *Known limitations* no [README](README.md). Licença [MIT](LICENSE).
