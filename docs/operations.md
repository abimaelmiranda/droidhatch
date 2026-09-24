# Operação

## Build

```sh
./scripts/build.sh
./scripts/build-frame-agent.sh
./scripts/build-audio-hal.sh
./scripts/build-droidhatch-home-apk.sh
./image/build.sh
```

`build.sh` gera os produtos Swift e os bundles em `artifacts/native/`. O GUI
instalável é `DroidHatch.app`; ele inclui o kernel em
`Contents/Resources/kernel/vmlinux-arm64`.

`image/build.sh` recria a camada tar de bootstrap com o whiteout OCI de `/etc`
e produz a imagem local `droidhatch/redroid:stable` a partir da base oficial
Redroid 14 ARM64. O workflow do GitHub publica a mesma imagem como
`ghcr.io/abimaelmiranda/droidhatch/redroid:stable`. O kernel não fica dentro
da imagem OCI: o Apple Container recebe-o no momento da criação da VM.

## Uso

Abra `~/Applications/DroidHatch.app`. Ao selecionar um APK, o GUI:

1. cria `droidhatch-backend` se ele não existir;
2. usa o kernel empacotado e a imagem stable;
3. inicia o Android e instala/concede as permissões do APK;
4. inicia o app e abre o viewer.

Para encerrar a sessão, use o fechamento do GUI/viewer. O backend pode ser
recriado pelo próprio GUI quando necessário; não crie o container manualmente
com caminhos de socket fixos.

## Limpeza segura

Devem permanecer somente os containers de banco, `buildkit` e
`droidhatch-backend`. A imagem local de desenvolvimento é
`droidhatch/redroid:stable`; a imagem de distribuição é
`ghcr.io/abimaelmiranda/droidhatch/redroid:stable`. Imagens antigas de
experimentos não fazem parte do runtime.
