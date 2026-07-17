# Pacotes locais

Coloque arquivos Debian (`*.deb`) nesta pasta e execute `Setup` ou `Rebuild`.
O Vibespace monta esta pasta como `/packages` e instala todos os pacotes no
container Ubuntu. Os instaladores não são copiados para a imagem.

O T3 Code já é instalado na imagem pelo pacote npm oficial e não precisa de um
arquivo `.deb` aqui.
