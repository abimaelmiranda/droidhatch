# Arquitetura atual

DroidHatch executa um único APK Android ARM64 dentro do Apple Container e o
apresenta em uma janela nativa Swift no macOS.

```text
Swift GUI/viewer
    ├── cria e controla droidhatch-backend
    ├── recebe frames por TCP
    ├── envia input por TCP
    └── recebe áudio pelo socket Unix publicado
              │
              ▼
Apple Container + Android 14 ARM64
    ├── kernel DMABUF/Binder/LMKD personalizado
    ├── gralloc e audio HAL DroidHatch
    ├── C++ frame-agent
    └── DroidHatch Home + APK selecionado
```

## Componentes

- `android/frame-agent`: captura HWC/gralloc, input via uinput e áudio via
  socket Unix.
- `android/home`: Home mínima que mantém o último app selecionado.
- `macos/DroidHatch.Native`: GUI, viewer, transporte, input, áudio e render.
- `image`: imagem OCI estável e kernel correspondente.
- `scripts`: builds e empacotamento.

## Contratos estáveis

- Container: `droidhatch-backend`.
- Imagem publicada: `ghcr.io/abimaelmiranda/droidhatch/redroid:stable`.
- Imagem local de desenvolvimento: `droidhatch/redroid:stable`.
- Memória: 2 GiB; shared memory: 1 GiB.
- Resolução: 1280×720; alvo: 30 FPS.
- ADB: `127.0.0.1:16092` → `5555`.
- Frames: `127.0.0.1:16090` → `5732`.
- Input: `127.0.0.1:16091` → `5733`.
- Áudio: `~/.droidhatch/run/backend-audio.sock` →
  `/ipc/droidhatch-audio.sock`.
- Kernel: `image/kernel/vmlinux-arm64`, empacotado também dentro do GUI.

O GUI calcula todos os caminhos do host a partir do `HOME` atual. Nenhum
caminho do ambiente de desenvolvimento deve ser colocado em receitas ou no
container.
