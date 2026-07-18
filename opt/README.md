# Pacotes locais

Coloque arquivos Debian (`*.deb`) ou AppImage (`*.AppImage`) nesta pasta e
execute `Setup` ou `Rebuild`. O Vibespace monta esta pasta como `/packages`.

- Pacotes `.deb` são instalados no container Ubuntu com `apt`.
- AppImages são copiados para `/opt/appimages` com permissão de execução e
  recebem um comando normalizado sem versão, mostrado durante o Setup. Por
  exemplo, `ZCode-3.2.3-win-x64.AppImage` recebe o comando `zcode`.

Os arquivos de origem não são copiados para a imagem e são ignorados pelo Git.
Durante o Setup, AppImages modernos do tipo 2 são validados e extraídos uma vez
no armazenamento persistente, sem FUSE ou privilégios adicionais. AppImages
legados do tipo 1 não oferecem essa extração e são rejeitados antes da criação
do comando.

O T3 Code não é instalado nativamente. Para usá-lo, coloque o AppImage dele
nesta pasta como qualquer outro aplicativo local.
